import AppKit
import HerdrCore
import SwiftUI

extension HotKeySpec {
    init(event: NSEvent) {
        var modifiers: Set<Modifier> = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    var display: String {
        let order: [Modifier] = [.control, .option, .shift, .command]
        let symbols: [Modifier: String] = [.control: "⌃", .option: "⌥", .shift: "⇧", .command: "⌘"]
        let prefix = order.filter(modifiers.contains).compactMap { symbols[$0] }.joined()
        return prefix + Self.keyName(for: keyCode)
    }

    /// Display names for ANSI virtual key codes. Not exhaustive — unknown
    /// codes render as `#n`, which still identifies the binding.
    static func keyName(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
            27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
            36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
            109: "F10", 111: "F12", 118: "F4", 120: "F2", 122: "F1",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return names[keyCode] ?? "#\(keyCode)"
    }
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published private(set) var preferences: HerdrPreferences
    @Published private(set) var knownHosts: [String] = []
    @Published private(set) var hostsLoading = false
    @Published var newHiddenHost = ""
    @Published private(set) var hostError: String?
    @Published private(set) var isRecordingHotKey = false
    @Published private(set) var hotKeyError: String?
    @Published private(set) var saveError: String?
    @Published private(set) var diagnosticsCopied = false
    @Published private(set) var diagnosticsCopying = false

    private let controller: PreferencesController
    private var recordingMonitor: Any?

    init(controller: PreferencesController = .shared) {
        self.controller = controller
        preferences = controller.current
        controller.observe { [weak self] updated in
            guard let self else { return }
            self.preferences = updated
        }
    }

    func apply(_ transform: (inout HerdrPreferences) -> Void) {
        preferences = controller.update(transform)
        saveError = controller.lastSaveError
    }

    func bind<Value>(_ keyPath: WritableKeyPath<HerdrPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { [weak self] in (self?.preferences ?? .default())[keyPath: keyPath] },
            set: { [weak self] value in self?.apply { $0[keyPath: keyPath] = value } }
        )
    }

    // MARK: Hotkey recording

    func beginRecordingHotKey() {
        guard recordingMonitor == nil else { return }
        isRecordingHotKey = true
        hotKeyError = nil
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.endRecordingHotKey()
                return nil
            }
            let spec = HotKeySpec(event: event)
            if let error = spec.validationError {
                self.hotKeyError = error
                return nil
            }
            self.apply { $0.herdrPanelHotKey = spec }
            self.endRecordingHotKey()
            return nil
        }
    }

    func endRecordingHotKey() {
        if let recordingMonitor { NSEvent.removeMonitor(recordingMonitor) }
        recordingMonitor = nil
        isRecordingHotKey = false
    }

    // MARK: Hidden hosts

    func loadKnownHosts() {
        guard !hostsLoading else { return }
        hostsLoading = true
        Task { [weak self] in
            let hosts = await Task.detached(priority: .userInitiated) {
                HerdrService.unfilteredSnapshot().remoteHosts.map(\.host)
            }.value
            guard let self else { return }
            self.knownHosts = hosts
            self.hostsLoading = false
        }
    }

    /// Reachable hosts plus already-hidden ones (a hidden host stays listed so
    /// it can be unhidden even while offline).
    var hostRows: [String] {
        var rows = knownHosts
        for hidden in preferences.hiddenHosts where !rows.contains(where: { $0.caseInsensitiveCompare(hidden) == .orderedSame }) {
            rows.append(hidden)
        }
        return rows.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func setHost(_ host: String, hidden: Bool) {
        apply { prefs in
            prefs.hiddenHosts.removeAll { $0.caseInsensitiveCompare(host) == .orderedSame }
            if hidden { prefs.hiddenHosts.append(host) }
        }
    }

    func addHiddenHost() {
        let host = newHiddenHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }
        guard HerdrPreferences.isValidHostName(host) else {
            hostError = "Hostnames may only contain letters, digits, dots, and dashes."
            return
        }
        hostError = nil
        newHiddenHost = ""
        setHost(host, hidden: true)
    }

    func clearHostError() { hostError = nil }

    func copyDiagnostics() {
        guard !diagnosticsCopying else { return }
        diagnosticsCopying = true
        diagnosticsCopied = false
        let preferences = preferences
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
        Task { [weak self] in
            let snapshot = await Task.detached(priority: .userInitiated) {
                HerdrService.snapshot()
            }.value
            guard let self else { return }
            let report = HerdrDiagnostics.report(
                snapshot: snapshot,
                preferences: preferences,
                appVersion: appVersion,
                operatingSystem: operatingSystem
            )
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)
            diagnosticsCopying = false
            diagnosticsCopied = true
            try? await Task.sleep(for: .seconds(2))
            self.diagnosticsCopied = false
        }
    }
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private let model = SettingsModel()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsRootView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Herdr Controls Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 440, height: 560))
            window.center()
            self.window = window
        }
        model.loadKnownHosts()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
