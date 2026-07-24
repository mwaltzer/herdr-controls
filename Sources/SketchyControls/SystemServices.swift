import AppKit
import CoreAudio
import EventKit
import Foundation
import HerdrCore
import SketchyControlsCore
import ServiceManagement
import UserNotifications

struct AudioSnapshot {
    var volume = 0.0
    var muted = false
    var outputs: [AudioDevice] = []
    var defaultOutputID: AudioDeviceID = 0
}

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
}

enum AudioService {
    static func snapshot() -> AudioSnapshot {
        AudioSnapshot(
            volume: Double(shell("osascript", ["-e", "output volume of (get volume settings)"])) ?? 0,
            muted: shell("osascript", ["-e", "output muted of (get volume settings)"]) == "true",
            outputs: devices(scope: kAudioDevicePropertyScopeOutput),
            defaultOutputID: defaultOutput()
        )
    }

    static func setVolume(_ volume: Double) {
        _ = shell("osascript", ["-e", "set volume output volume \(Int(volume.rounded()))"])
    }

    static func setMuted(_ muted: Bool) {
        _ = shell("osascript", ["-e", "set volume output muted \(muted)"])
    }

    static func setDefaultOutput(_ id: AudioDeviceID) {
        var deviceID = id
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )
    }

    private static func defaultOutput() -> AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    private static func devices(scope: AudioObjectPropertyScope) -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            var streamsAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: scope,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamsSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streamsAddress, 0, nil, &streamsSize) == noErr, streamsSize > 0 else { return nil }

            var unmanagedName: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &unmanagedName) == noErr,
                  let name = unmanagedName?.takeUnretainedValue() else { return nil }
            return AudioDevice(id: id, name: name as String)
        }
    }
}

struct NetworkSnapshot {
    var powered = false
    var connected = false
    var ssid = "Not connected"
    var address = ""
}

enum NetworkService {
    static func snapshot() -> NetworkSnapshot {
        let power = shell("networksetup", ["-getairportpower", "en0"]).hasSuffix("On")
        let current = shell("networksetup", ["-getairportnetwork", "en0"])
        let connected = !current.localizedCaseInsensitiveContains("not associated") && current.contains(":")
        let ssid = connected ? current.split(separator: ":", maxSplits: 1).last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "Connected" : "Not connected"
        let address = shell("ipconfig", ["getifaddr", "en0"])
        return NetworkSnapshot(powered: power, connected: connected, ssid: ssid, address: address)
    }

    static func setPower(_ powered: Bool) {
        _ = shell("networksetup", ["-setairportpower", "en0", powered ? "on" : "off"])
    }
}

struct PowerSnapshot {
    var percent = 0
    var charging = false
    var source = "Unknown"
    var detail = ""
}

enum PowerService {
    static func snapshot() -> PowerSnapshot {
        let output = shell("pmset", ["-g", "batt"])
        let percent = output.firstMatch("([0-9]+)%").flatMap(Int.init) ?? 0
        let charging = output.localizedCaseInsensitiveContains("charging") || output.contains("AC Power")
        let source = output.contains("AC Power") ? "Power adapter" : "Battery"
        let detail = output.split(separator: ";").dropFirst().first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return PowerSnapshot(percent: percent, charging: charging, source: source, detail: detail)
    }
}

struct PerformanceSnapshot {
    var cpu = "—"
    var memory = "—"
    var swap = "—"
}

enum PerformanceService {
    static func snapshot() -> PerformanceSnapshot {
        let cpuLine = shell("sh", ["-c", "top -l 1 -n 0 | awk '/CPU usage/ {print $3 \" used\"}'"])
        let vm = shell("vm_stat", [])
        let pageSize = vm.firstMatch("page size of ([0-9]+) bytes").flatMap(Double.init) ?? 4096
        let active = vm.firstMatch("Pages active:\\s+([0-9]+)").flatMap(Double.init) ?? 0
        let wired = vm.firstMatch("Pages wired down:\\s+([0-9]+)").flatMap(Double.init) ?? 0
        let compressed = vm.firstMatch("Pages occupied by compressor:\\s+([0-9]+)").flatMap(Double.init) ?? 0
        let usedGB = (active + wired + compressed) * pageSize / 1_073_741_824
        let swapLine = shell("sysctl", ["-n", "vm.swapusage"]).firstMatch("used = ([0-9.]+[MG])") ?? "0M"
        return PerformanceSnapshot(cpu: cpuLine.isEmpty ? "—" : cpuLine, memory: String(format: "%.1f GB used", usedGB), swap: "\(swapLine) swap")
    }
}

struct ProcessCommandRunner: HerdrCommandRunning {
    func output(executable: String, arguments: [String]) -> Data {
        shellData(executable, arguments, timeout: 8)
    }
}

enum HerdrService {
    /// Live value — every discovery/launch call sees the latest settings.
    static var preferences: HerdrPreferences { PreferencesController.shared.current }

    static func snapshot() -> HerdrSnapshot {
        HerdrSessionDiscovery(preferences: preferences, runner: ProcessCommandRunner()).snapshot()
    }

    /// Discovery with the hidden-host filter disabled, so the settings window
    /// can list every reachable host as a hide/show candidate.
    static func unfilteredSnapshot() -> HerdrSnapshot {
        var prefs = preferences
        prefs.hiddenHosts = []
        return HerdrSessionDiscovery(preferences: prefs, runner: ProcessCommandRunner()).snapshot()
    }

    static func focusWorkspace(_ id: String) { _ = shell(preferences.herdrExecutable, ["workspace", "focus", id]) }
    static func focusAgent(_ id: String) { _ = shell(preferences.herdrExecutable, ["agent", "focus", id]) }

    static func openRemote(host: String, paneID: String) {
        let preferences = preferences
        let process = Process()
        process.executableURL = URL(fileURLWithPath: preferences.openTailnetSessionExecutable)
        // The terminal travels as a plain argv element — never through a
        // shell — and the helper script matches it against known names only.
        process.arguments = [host, paneID, preferences.terminalApp]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

enum HerdrMacIntegration {
    static func applyLaunchAtLogin(_ enabled: Bool) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // The settings UI remains the source of intent. Registration may
            // be unavailable for an unsigned development bundle.
        }
    }

    static func requestNotificationsIfNeeded(_ enabled: Bool) {
        guard enabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(agent: HerdrAgent, workspaceLabel: String?, status: String) {
        let content = UNMutableNotificationContent()
        content.title = status == "blocked" ? "Agent needs attention" : "Agent finished"
        content.body = "\(workspaceLabel ?? "Herdr") · \(agent.terminalTitleStripped)"
        content.sound = .default
        content.userInfo = ["pane_id": agent.id]
        let request = UNNotificationRequest(
            identifier: "herdr-agent-\(agent.id)-\(agent.stateChangeSequence)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    @MainActor
    static func donateActivity(
        title: String,
        identifier: String,
        url: URL
    ) {
        let activity = NSUserActivity(activityType: "com.mwaltzer.herdr-controls.open")
        activity.title = title
        activity.targetContentIdentifier = identifier
        activity.webpageURL = url
        activity.isEligibleForSearch = true
        activity.keywords = ["Herdr", "workspace", "agent"]
        activity.becomeCurrent()
    }
}

struct VPNStatus {
    var label = "Unavailable"
    var healthy = false
}

enum VPNService {
    static func status() -> VPNStatus {
        let output = shell("launchctl", ["print", "system/net.futurex.openconnect"])
        if output.contains("state = running") { return VPNStatus(label: "Connected", healthy: true) }
        if output.isEmpty { return VPNStatus(label: "Not installed", healthy: false) }
        return VPNStatus(label: "Reconnecting", healthy: false)
    }
}

struct CalendarItem: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let location: String?
    let url: URL?
    let color: NSColor
}

@MainActor
final class CalendarService {
    private let store = EKEventStore()

    func events() async -> (authorized: Bool, items: [CalendarItem]) {
        do {
            let allowed = try await store.requestFullAccessToEvents()
            guard allowed else { return (false, []) }
            let start = Calendar.current.startOfDay(for: Date())
            let end = Calendar.current.date(byAdding: .day, value: 2, to: start) ?? Date().addingTimeInterval(172800)
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            let items = store.events(matching: predicate)
                .filter { !$0.isAllDay }
                .prefix(8)
                .map {
                    CalendarItem(
                        id: $0.eventIdentifier,
                        title: $0.title ?? "Untitled event",
                        start: $0.startDate,
                        end: $0.endDate,
                        location: $0.location,
                        url: $0.url,
                        color: NSColor(cgColor: $0.calendar.cgColor) ?? .systemPurple
                    )
                }
            return (true, Array(items))
        } catch {
            return (false, [])
        }
    }
}

@discardableResult
func shell(_ command: String, _ arguments: [String]) -> String {
    String(data: shellData(command, arguments), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

func shellData(_ command: String, _ arguments: [String], timeout: TimeInterval = 5) -> Data {
    let resolved = command.contains("/") ? command : "/usr/bin/env"
    let resolvedArguments = command.contains("/") ? arguments : [command] + arguments
    guard let result = BoundedProcess.run(
        executable: resolved,
        arguments: resolvedArguments,
        timeout: timeout
    ), !result.timedOut else { return Data() }
    return result.output
}

extension String {
    func firstMatch(_ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: self)
        else { return nil }
        return String(self[range])
    }
}
