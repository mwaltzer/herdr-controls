import AppKit
import Foundation
import HerdrCore
import SketchyControlsCore

@MainActor
final class AppModel: ObservableObject {
    @Published var panel: PanelKind = .controlCenter
    @Published var audio = AudioSnapshot()
    @Published var network = NetworkSnapshot()
    @Published var power = PowerSnapshot()
    @Published var performance = PerformanceSnapshot()
    @Published var herdr = HerdrSnapshot()
    @Published var vpn = VPNStatus()
    @Published var events: [CalendarItem] = []
    @Published var calendarAuthorized = true
    @Published var sessionConfirmation: SessionAction?
    @Published var selectedHerdrKey: String?
    @Published var herdrLocation: HerdrLocation
    @Published var herdrTargetKind: HerdrTargetKind
    @Published var herdrHealth = HerdrDiscoveryHealth()
    /// When the next automatic Herdr retry fires; nil when none is scheduled.
    @Published var nextHerdrRetry: Date?

    init() {
        let preferences = PreferencesController.shared.current
        herdrLocation = preferences.defaultLocation
        herdrTargetKind = preferences.defaultTargetKind
    }

    let isWork = ProcessInfo.processInfo.environment["SKETCHY_CONTROLS_PROFILE"] == "work"
    let calendarService = CalendarService()
    var showPanel: ((PanelKind) -> Void)?
    var dismissPanel: (() -> Void)?
    var didRefresh: ((PanelKind) -> Void)?
    private var herdrRefreshTask: Task<Void, Never>?
    private var herdrRetryTask: Task<Void, Never>?
    private var previousAgentStates: [String: (status: String, sequence: UInt64)] = [:]

    func refresh(_ panel: PanelKind) {
        self.panel = panel
        if panel == .herdr {
            refreshHerdrSnapshot(priority: .userInitiated)
            return
        }
        Task {
            switch panel {
            case .audio:
                audio = await Task.detached(priority: .userInitiated) { AudioService.snapshot() }.value
            case .network:
                network = await Task.detached(priority: .userInitiated) { NetworkService.snapshot() }.value
            case .power:
                power = await Task.detached(priority: .userInitiated) { PowerService.snapshot() }.value
            case .performance:
                performance = await Task.detached(priority: .userInitiated) { PerformanceService.snapshot() }.value
            case .herdr:
                break
            case .calendar:
                let result = await calendarService.events()
                calendarAuthorized = result.authorized
                events = result.items
            case .controlCenter:
                async let nextAudio = Task.detached(priority: .userInitiated) { AudioService.snapshot() }.value
                async let nextNetwork = Task.detached(priority: .userInitiated) { NetworkService.snapshot() }.value
                async let nextPower = Task.detached(priority: .userInitiated) { PowerService.snapshot() }.value
                audio = await nextAudio
                network = await nextNetwork
                power = await nextPower
                if isWork {
                    vpn = await Task.detached(priority: .userInitiated) { VPNService.status() }.value
                }
            case .focusDisplay, .session:
                break
            }
            didRefresh?(panel)
        }
    }

    func open(_ kind: PanelKind) { showPanel?(kind) }
    func dismiss() { dismissPanel?() }

    func refreshHerdrSnapshot(priority: TaskPriority = .utility) {
        guard herdrRefreshTask == nil else { return }
        herdrRefreshTask = Task {
            defer { herdrRefreshTask = nil }
            applyHerdrSnapshot(await Task.detached(priority: priority) { HerdrService.snapshot() }.value)
            didRefresh?(.herdr)
        }
    }

    /// Single sink for every Herdr snapshot: updates content, selection, and
    /// connection health, and schedules a bounded automatic retry while the
    /// local CLI is unavailable (the shell's cadence timer keeps checking
    /// after the retry policy is exhausted).
    private func applyHerdrSnapshot(_ snapshot: HerdrSnapshot) {
        deliverAgentNotifications(from: snapshot)
        herdr = snapshot
        let refreshInterval = HerdrService.preferences.refreshInterval
        Task.detached(priority: .utility) {
            HerdrStatusCache.write(snapshot, refreshInterval: refreshInterval)
        }
        normalizeHerdrSelection()
        herdrHealth = herdrHealth.updating(with: snapshot, policy: .panelRetry)

        herdrRetryTask?.cancel()
        herdrRetryTask = nil
        if let delay = herdrHealth.retryDelay {
            nextHerdrRetry = Date().addingTimeInterval(delay)
            herdrRetryTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.refreshHerdrSnapshot()
            }
        } else {
            nextHerdrRetry = nil
        }
    }

    private func deliverAgentNotifications(from snapshot: HerdrSnapshot) {
        let enabled = HerdrService.preferences.agentNotificationsEnabled
        for agent in snapshot.agents {
            let previous = previousAgentStates[agent.id]
            let changed = previous != nil
                && previous?.sequence != agent.stateChangeSequence
                && previous?.status != agent.agentStatus
            if enabled, changed, agent.agentStatus == "done" || agent.agentStatus == "blocked" {
                let label = snapshot.workspaces.first(where: { $0.id == agent.workspaceID })?.label
                HerdrMacIntegration.notify(agent: agent, workspaceLabel: label, status: agent.agentStatus)
            }
            previousAgentStates[agent.id] = (agent.agentStatus, agent.stateChangeSequence)
        }
        let live = Set(snapshot.agents.map(\.id))
        previousAgentStates = previousAgentStates.filter { live.contains($0.key) }
    }

    /// User-initiated retry: restarts the backoff schedule from the top.
    func retryHerdrNow() {
        herdrRetryTask?.cancel()
        herdrRetryTask = nil
        nextHerdrRetry = nil
        herdrHealth = HerdrDiscoveryHealth()
        refreshHerdrSnapshot()
    }

    func isHerdrSelected(_ key: String) -> Bool { selectedHerdrKey == key }
    func clearHerdrSelection() {
        let preferences = PreferencesController.shared.current
        selectedHerdrKey = nil
        herdrLocation = preferences.defaultLocation
        herdrTargetKind = preferences.defaultTargetKind
    }

    func moveHerdrSelection(_ delta: Int) {
        selectedHerdrKey = HerdrNavigation.movedSelection(from: selectedHerdrKey, by: delta, in: scopedHerdrTargets)
    }

    func setHerdrLocation(_ location: HerdrLocation) {
        herdrLocation = location
        normalizeScopedHerdrSelection()
    }

    func toggleHerdrLocation() {
        setHerdrLocation(herdrLocation == .local ? .tailnet : .local)
    }

    func setHerdrTargetKind(_ kind: HerdrTargetKind) {
        guard kind != herdrTargetKind else { return }
        selectedHerdrKey = HerdrNavigation.selectionWhenChangingKind(
            from: selectedHerdrKey,
            to: kind,
            location: herdrLocation,
            in: herdr
        )
        herdrTargetKind = kind
    }

    private func normalizeScopedHerdrSelection() {
        selectedHerdrKey = HerdrNavigation.scopedSelection(selectedHerdrKey, in: scopedHerdrTargets)
    }

    func activateHerdrSelection() {
        guard let target = HerdrNavigation.targets(in: herdr).first(where: { $0.key == selectedHerdrKey }) else { return }
        switch target.action {
        case let .workspace(id):
            HerdrService.focusWorkspace(id)
            donate(title: "Open Herdr workspace", identifier: "workspace:\(id)", path: "workspace/\(id)")
        case let .agent(id):
            HerdrService.focusAgent(id)
            donate(title: "Open Herdr agent", identifier: "agent:\(id)", path: "agent/\(id)")
        case let .remoteHost(host, paneID):
            HerdrService.openRemote(host: host, paneID: paneID)
            donate(title: "Open Herdr on \(host)", identifier: "remote:\(host):\(paneID)", path: "remote/\(host)/\(paneID)")
        case let .remoteAgent(host, paneID):
            HerdrService.openRemote(host: host, paneID: paneID)
            donate(title: "Open Herdr agent on \(host)", identifier: "remote:\(host):\(paneID)", path: "remote/\(host)/\(paneID)")
        }
        dismiss()
    }

    private func donate(title: String, identifier: String, path: String) {
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "herdr-controls://\(encoded)")
        else { return }
        HerdrMacIntegration.donateActivity(title: title, identifier: identifier, url: url)
    }

    private func normalizeHerdrSelection() {
        selectedHerdrKey = HerdrNavigation.normalizedSelection(selectedHerdrKey, in: HerdrNavigation.targets(in: herdr))
    }

    private var scopedHerdrTargets: [HerdrTarget] {
        HerdrNavigation.scopedTargets(in: herdr, location: herdrLocation, kind: herdrTargetKind)
    }

    /// Why the current Herdr scope has nothing to list; nil when it has
    /// content.
    var herdrIssue: HerdrPanelIssue? {
        HerdrPanelStatus.issue(
            snapshot: herdr,
            location: herdrLocation,
            kind: herdrTargetKind,
            tailnetDiscoveryEnabled: HerdrService.preferences.tailnetDiscoveryEnabled
        )
    }

    func openURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
}
