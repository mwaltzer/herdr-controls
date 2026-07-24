import Foundation

/// A user-configurable global shortcut, stored with semantic modifier names so
/// the on-disk format is not coupled to Carbon flag values.
public struct HotKeySpec: Codable, Equatable, Sendable {
    public enum Modifier: String, Codable, CaseIterable, Sendable {
        case command, option, control, shift
    }

    public var keyCode: UInt32
    public var modifiers: Set<Modifier>

    public init(keyCode: UInt32, modifiers: Set<Modifier>) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// kVK_ANSI_H + command: the prototype's hardcoded Herdr panel toggle.
    public static let defaultHerdrToggle = HotKeySpec(keyCode: 4, modifiers: [.command])

    /// Global hotkeys must carry at least one modifier (a bare key would
    /// shadow normal typing) and a plausible virtual key code.
    public var validationError: String? {
        if modifiers.isEmpty { return "Add at least one modifier (⌘, ⌥, ⌃, or ⇧)." }
        if keyCode > 127 { return "Unsupported key." }
        return nil
    }

    public var isValid: Bool { validationError == nil }
}

/// Terminals the remote-session launch path knows how to drive. The raw value
/// is both the stored preference and the app bundle name; the launch helper
/// (`open-tailnet-session.sh`) matches on these exact names and falls back to
/// Ghostty for anything else, so an unknown value can never inject arguments.
public enum HerdrTerminal: String, Codable, CaseIterable, Sendable {
    case ghostty = "Ghostty"
    case kitty
    case wezterm = "WezTerm"
    case alacritty = "Alacritty"

    public static let `default` = HerdrTerminal.ghostty
}

/// Versioned preferences for the Herdr menu-bar app. Decoding tolerates
/// missing fields (each falls back to its default) so older files keep
/// working as fields are added; unknown fields are ignored for the reverse.
public struct HerdrPreferences: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var herdrExecutable: String
    public var tailnetSessionsExecutable: String
    public var openTailnetSessionExecutable: String
    /// Terminal used when attaching to a remote session; passed to the
    /// open-tailnet-session helper as an argv element, where only exact
    /// `HerdrTerminal` names are honored (anything else falls back to Ghostty).
    public var terminalApp: String
    public var tailnetDiscoveryEnabled: Bool
    public var herdrPanelHotKey: HotKeySpec
    /// Seconds between background session refreshes (status item badge, open
    /// Herdr panel). Clamped to `refreshIntervalRange` on init and decode.
    public var refreshInterval: TimeInterval {
        didSet { refreshInterval = Self.clampedRefreshInterval(refreshInterval) }
    }
    /// Scope the Herdr panel opens in.
    public var defaultLocation: HerdrLocation
    public var defaultTargetKind: HerdrTargetKind
    /// Tailnet hosts excluded from discovery, matched case-insensitively.
    public var hiddenHosts: [String]
    /// Whether the first-run welcome window has been dismissed. Backfills
    /// false for pre-onboarding preference files, so existing installs see the
    /// welcome window exactly once.
    public var onboardingCompleted: Bool

    public static let refreshIntervalRange: ClosedRange<TimeInterval> = 5...3600

    public init(
        version: Int = HerdrPreferences.currentVersion,
        herdrExecutable: String,
        tailnetSessionsExecutable: String,
        openTailnetSessionExecutable: String,
        terminalApp: String = HerdrTerminal.default.rawValue,
        tailnetDiscoveryEnabled: Bool = true,
        herdrPanelHotKey: HotKeySpec = .defaultHerdrToggle,
        refreshInterval: TimeInterval = 30,
        defaultLocation: HerdrLocation = .local,
        defaultTargetKind: HerdrTargetKind = .containers,
        hiddenHosts: [String] = [],
        onboardingCompleted: Bool = false
    ) {
        self.version = version
        self.herdrExecutable = herdrExecutable
        self.tailnetSessionsExecutable = tailnetSessionsExecutable
        self.openTailnetSessionExecutable = openTailnetSessionExecutable
        self.terminalApp = terminalApp
        self.tailnetDiscoveryEnabled = tailnetDiscoveryEnabled
        self.herdrPanelHotKey = herdrPanelHotKey
        self.refreshInterval = Self.clampedRefreshInterval(refreshInterval)
        self.defaultLocation = defaultLocation
        self.defaultTargetKind = defaultTargetKind
        self.hiddenHosts = hiddenHosts
        self.onboardingCompleted = onboardingCompleted
    }

    public static func clampedRefreshInterval(_ value: TimeInterval) -> TimeInterval {
        min(max(value, refreshIntervalRange.lowerBound), refreshIntervalRange.upperBound)
    }

    /// Hostname charset the tailnet helper scripts accept; hidden-host entries
    /// are validated against the same rule so the lists stay consistent.
    public static func isValidHostName(_ host: String) -> Bool {
        !host.isEmpty && host.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression) != nil
    }

    public func isHostHidden(_ host: String) -> Bool {
        hiddenHosts.contains { $0.caseInsensitiveCompare(host) == .orderedSame }
    }

    public static func `default`() -> HerdrPreferences {
        let bin = NSHomeDirectory() + "/.local/bin"
        return HerdrPreferences(
            herdrExecutable: bin + "/herdr",
            tailnetSessionsExecutable: bin + "/herdr-tailnet-sessions",
            openTailnetSessionExecutable: bin + "/herdr-open-tailnet-session"
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = HerdrPreferences.default()
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        herdrExecutable = try container.decodeIfPresent(String.self, forKey: .herdrExecutable)
            ?? defaults.herdrExecutable
        tailnetSessionsExecutable = try container.decodeIfPresent(String.self, forKey: .tailnetSessionsExecutable)
            ?? defaults.tailnetSessionsExecutable
        openTailnetSessionExecutable = try container.decodeIfPresent(String.self, forKey: .openTailnetSessionExecutable)
            ?? defaults.openTailnetSessionExecutable
        terminalApp = try container.decodeIfPresent(String.self, forKey: .terminalApp) ?? defaults.terminalApp
        tailnetDiscoveryEnabled = try container.decodeIfPresent(Bool.self, forKey: .tailnetDiscoveryEnabled)
            ?? defaults.tailnetDiscoveryEnabled
        let decodedHotKey = try container.decodeIfPresent(HotKeySpec.self, forKey: .herdrPanelHotKey)
            ?? defaults.herdrPanelHotKey
        herdrPanelHotKey = decodedHotKey.isValid ? decodedHotKey : defaults.herdrPanelHotKey
        refreshInterval = Self.clampedRefreshInterval(
            try container.decodeIfPresent(TimeInterval.self, forKey: .refreshInterval) ?? defaults.refreshInterval
        )
        // Decoded via String so a raw value from a newer app version degrades
        // to the default instead of discarding the whole file.
        defaultLocation = (try container.decodeIfPresent(String.self, forKey: .defaultLocation))
            .flatMap(HerdrLocation.init(rawValue:)) ?? defaults.defaultLocation
        defaultTargetKind = (try container.decodeIfPresent(String.self, forKey: .defaultTargetKind))
            .flatMap(HerdrTargetKind.init(rawValue:)) ?? defaults.defaultTargetKind
        hiddenHosts = (try container.decodeIfPresent([String].self, forKey: .hiddenHosts) ?? defaults.hiddenHosts)
            .filter(Self.isValidHostName)
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted)
            ?? defaults.onboardingCompleted
    }
}

public protocol HerdrPreferencesStore: Sendable {
    func readData() throws -> Data?
    func writeData(_ data: Data) throws
}

public struct JSONFilePreferencesStore: HerdrPreferencesStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func readData() throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func writeData(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}

public extension HerdrPreferences {
    static var defaultStoreURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return support.appendingPathComponent("HerdrControls/preferences.json")
    }

    /// A missing or unreadable file yields defaults; a corrupt file also
    /// yields defaults rather than blocking launch (the file is regenerated on
    /// the next save).
    static func load(from store: any HerdrPreferencesStore) -> HerdrPreferences {
        guard let data = try? store.readData(), !data.isEmpty else { return .default() }
        return (try? JSONDecoder().decode(HerdrPreferences.self, from: data)) ?? .default()
    }

    func save(to store: any HerdrPreferencesStore) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try store.writeData(encoder.encode(self))
    }
}
