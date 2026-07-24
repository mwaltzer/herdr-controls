import Foundation
import HerdrCore
import SketchyControlsCore

let largeProcessOutput = BoundedProcess.run(
    executable: "/bin/sh",
    arguments: ["-c", "yes x | head -c 262144"],
    timeout: 2,
    outputLimit: 32_768
)
require(
    largeProcessOutput?.timedOut == false && largeProcessOutput?.output.count == 32_768,
    "bounded process drains and caps output while child runs"
)

let timeoutStart = Date()
let timedOutProcess = BoundedProcess.run(
    executable: "/bin/sh",
    arguments: ["-c", "sleep 5"],
    timeout: 0.1
)
require(
    timedOutProcess?.timedOut == true && Date().timeIntervalSince(timeoutStart) < 1.5,
    "bounded process terminates hung child"
)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("check failed: \(message)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

do {
    let toggle = try PanelCommand.parse(arguments: ["toggle", "audio", "--source", "volume"], mouse: (12.5, 44))
    require(toggle.action == .toggle, "toggle action")
    require(toggle.panel == .audio, "audio panel")
    require(toggle.source == "volume", "source parsing")
    require(toggle.mouseX == 12.5 && toggle.mouseY == 44, "mouse position")

    let anchored = try PanelCommand.parse(arguments: [
        "show", "herdr", "--source", "herdr", "--mouse-x", "2827", "--mouse-y", "1959"
    ])
    require(anchored.mouseX == 2827 && anchored.mouseY == 1959, "argument mouse position")

    let status = try PanelCommand.parse(arguments: ["status"])
    require(status.action == .status && status.panel == nil, "status parsing")

    do {
        _ = try PanelCommand.parse(arguments: ["show", "not-a-panel"])
        require(false, "invalid panel must fail")
    } catch { }

    print("PanelCommand checks passed")
} catch {
    fputs("unexpected check error: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}

// MARK: - HerdrCore contract checks

let workspaceJSON = Data("""
{"result":{"workspaces":[
  {"workspace_id":"ws-1","label":"docs","number":1,"agent_status":"running","focused":true,"future_field":"ignored"},
  {"workspace_id":"ws-2","label":"infra","number":2,"agent_status":"idle","focused":false}
]}}
""".utf8)
let agentJSON = Data("""
{"result":{"agents":[
  {"agent":"claude","agent_status":"running","pane_id":"p-1","workspace_id":"ws-1","terminal_title_stripped":"docs review","focused":true},
  {"agent":"codex","agent_status":"idle","pane_id":"p-2","workspace_id":"ws-2","terminal_title_stripped":"infra","focused":false}
]}}
""".utf8)
let tailnetJSON = Data("""
[{"host":"studio","agents":[
  {"agent":"pi","agent_status":"running","pane_id":"r-1","workspace_id":"ws-9","terminal_title_stripped":"remote","focused":false}
]}]
""".utf8)
let nativeSnapshotJSON = Data("""
{"result":{"snapshot":{"workspaces":[
  {"workspace_id":"ws-1","label":"docs","number":1,"agent_status":"idle","focused":true,
   "tokens":{"vcs_provider":"jj","vcs_ref":"main","vcs_change":"abc123","vcs_dirty":"true"}}
],"agents":[
  {"agent":"codex","agent_status":"idle","pane_id":"p-1","workspace_id":"ws-1",
   "terminal_title_stripped":"docs","focused":true,"cwd":"/repo","state_change_seq":42}
]}}}
""".utf8)

do {
    let workspaces = try HerdrLocalContract.decodeWorkspaces(workspaceJSON)
    require(workspaces.count == 2 && workspaces[0].id == "ws-1" && workspaces[0].focused, "workspace envelope decoding")
    let agents = try HerdrLocalContract.decodeAgents(agentJSON)
    require(agents.count == 2 && agents[0].id == "p-1" && agents[0].workspaceID == "ws-1", "agent envelope decoding")
    let hosts = try HerdrTailnetContract.decodeHosts(tailnetJSON)
    require(hosts.count == 1 && hosts[0].host == "studio" && hosts[0].agents.count == 1, "tailnet host decoding")
    let native = try HerdrLocalContract.decodeSnapshot(nativeSnapshotJSON)
    require(native.workspaces[0].vcs?.provider == "jj", "allowlisted VCS metadata decoding")
    require(native.workspaces[0].vcs?.dirty == true, "VCS dirty state decoding")
    require(native.agents[0].cwd == "/repo" && native.agents[0].stateChangeSequence == 42, "native agent metadata decoding")
} catch {
    fputs("unexpected contract error: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}

do {
    _ = try HerdrLocalContract.decodeWorkspaces(Data())
    require(false, "empty workspace payload must fail")
} catch {
    require(error as? HerdrContractError == .emptyPayload(.workspaces), "empty payload error kind")
}

do {
    _ = try HerdrLocalContract.decodeAgents(Data("not json".utf8))
    require(false, "malformed agent payload must fail")
} catch let error as HerdrContractError {
    if case .malformed(.agents, _) = error {} else { require(false, "malformed payload error kind") }
} catch {
    require(false, "malformed payload error type")
}

// MARK: - HerdrCore discovery checks

struct FakeRunner: HerdrCommandRunning {
    let outputs: [String: Data]
    func output(executable: String, arguments: [String]) -> Data {
        outputs[([executable] + arguments).joined(separator: " ")] ?? Data()
    }
}

let checkPreferences = HerdrPreferences(
    herdrExecutable: "/fake/herdr",
    tailnetSessionsExecutable: "/fake/herdr-tailnet-sessions",
    openTailnetSessionExecutable: "/fake/herdr-open-tailnet-session"
)

let liveRunner = FakeRunner(outputs: [
    "/fake/herdr workspace list": workspaceJSON,
    "/fake/herdr agent list": agentJSON,
    "/fake/herdr-tailnet-sessions": tailnetJSON,
])
let liveSnapshot = HerdrSessionDiscovery(preferences: checkPreferences, runner: liveRunner).snapshot()
require(liveSnapshot.localStatus == .ok && liveSnapshot.available, "discovery success status")
require(liveSnapshot.workspaces.count == 2 && liveSnapshot.agents.count == 2 && liveSnapshot.remoteHosts.count == 1, "discovery success payload")

let nativeRunner = FakeRunner(outputs: [
    "/fake/herdr api snapshot": nativeSnapshotJSON,
    "/fake/herdr-tailnet-sessions": tailnetJSON,
])
let nativeSnapshot = HerdrSessionDiscovery(preferences: checkPreferences, runner: nativeRunner).snapshot()
require(nativeSnapshot.workspaces[0].vcs?.reference == "main", "native API snapshot preferred")

let deadLocalSnapshot = HerdrSessionDiscovery(
    preferences: checkPreferences,
    runner: FakeRunner(outputs: ["/fake/herdr-tailnet-sessions": tailnetJSON])
).snapshot()
require(deadLocalSnapshot.workspaces.isEmpty && deadLocalSnapshot.available, "dead local CLI keeps tailnet availability")
if case .unavailable = deadLocalSnapshot.localStatus {} else { require(false, "dead local CLI status") }

let deadSnapshot = HerdrSessionDiscovery(preferences: checkPreferences, runner: FakeRunner(outputs: [:])).snapshot()
require(!deadSnapshot.available, "fully dead discovery is unavailable")

var offlinePreferences = checkPreferences
offlinePreferences.tailnetDiscoveryEnabled = false
let offlineSnapshot = HerdrSessionDiscovery(preferences: offlinePreferences, runner: liveRunner).snapshot()
require(offlineSnapshot.remoteHosts.isEmpty && offlineSnapshot.localStatus == .ok, "tailnet discovery toggle")

// MARK: - HerdrCore navigation checks

let targets = HerdrNavigation.targets(in: liveSnapshot)
require(
    targets.map(\.key) == ["workspace:ws-1", "agent:p-1", "workspace:ws-2", "agent:p-2", "host:studio", "remote:studio:r-1"],
    "target ordering interleaves workspaces, agents, hosts"
)

let localAgents = HerdrNavigation.scopedTargets(in: liveSnapshot, location: .local, kind: .agents)
require(localAgents.map(\.key) == ["agent:p-1", "agent:p-2"], "local agent scoping")
let tailnetHosts = HerdrNavigation.scopedTargets(in: liveSnapshot, location: .tailnet, kind: .containers)
require(tailnetHosts.map(\.key) == ["host:studio"], "tailnet host scoping")
require(tailnetHosts[0].action == .remoteHost(host: "studio", firstPane: "r-1"), "host action carries first pane")

require(HerdrNavigation.movedSelection(from: nil, by: 1, in: localAgents) == "agent:p-1", "move into list selects first")
require(HerdrNavigation.movedSelection(from: nil, by: -1, in: localAgents) == "agent:p-2", "move up into list selects last")
require(HerdrNavigation.movedSelection(from: "agent:p-2", by: 1, in: localAgents) == "agent:p-1", "move wraps forward")
require(HerdrNavigation.movedSelection(from: "agent:p-1", by: -1, in: localAgents) == "agent:p-2", "move wraps backward")
require(HerdrNavigation.movedSelection(from: "agent:p-1", by: 1, in: []) == "agent:p-1", "empty scope keeps selection")

require(HerdrNavigation.normalizedSelection("agent:p-1", in: targets) == "agent:p-1", "normalization keeps live selection")
require(HerdrNavigation.normalizedSelection("agent:gone", in: targets) == nil, "normalization drops dead selection")
require(HerdrNavigation.scopedSelection("host:studio", in: localAgents) == "agent:p-1", "scope change snaps to first")
require(HerdrNavigation.scopedSelection(nil, in: []) == nil, "empty scope selection stays nil")
require(
    HerdrNavigation.selectionWhenChangingKind(
        from: "workspace:ws-2",
        to: .agents,
        location: .local,
        in: liveSnapshot
    ) == "agent:p-2",
    "workspace to agents preserves workspace context"
)
require(
    HerdrNavigation.selectionWhenChangingKind(
        from: "agent:p-1",
        to: .containers,
        location: .local,
        in: liveSnapshot
    ) == "workspace:ws-1",
    "agent to workspaces selects parent workspace"
)
require(
    HerdrNavigation.selectionWhenChangingKind(
        from: "host:studio",
        to: .agents,
        location: .tailnet,
        in: liveSnapshot
    ) == "remote:studio:r-1",
    "host to agents preserves host context"
)
require(
    HerdrNavigation.selectionWhenChangingKind(
        from: "remote:studio:r-1",
        to: .containers,
        location: .tailnet,
        in: liveSnapshot
    ) == "host:studio",
    "remote agent to hosts selects parent host"
)

// MARK: - HerdrCore lifecycle checks

let policy = RetryPolicy.sessionDiscovery
require(policy.delay(forAttempt: 1) == 1, "retry first delay")
require(policy.delay(forAttempt: 3) == 4, "retry exponential growth")
require(policy.delay(forAttempt: 20) == 30, "retry delay cap")
require(policy.delay(forAttempt: -5) == 1, "retry clamps invalid attempts")
require(policy.shouldRetry(attempt: 1000), "unbounded policy always retries")
require(!RetryPolicy(initialDelay: 1, multiplier: 2, maxDelay: 8, maxAttempts: 3).shouldRetry(attempt: 3), "bounded policy stops")

// MARK: - HerdrCore preferences checks

final class MemoryStore: HerdrPreferencesStore, @unchecked Sendable {
    var data: Data?
    func readData() throws -> Data? { data }
    func writeData(_ newData: Data) throws { data = newData }
}

let emptyStore = MemoryStore()
let defaults = HerdrPreferences.load(from: emptyStore)
require(defaults == HerdrPreferences.default(), "missing store yields defaults")
require(defaults.herdrPanelHotKey == HotKeySpec(keyCode: 4, modifiers: [.command]), "default hotkey is cmd+H")
require(defaults.herdrExecutable.hasSuffix("/.local/bin/herdr"), "default herdr path")

var customized = defaults
customized.terminalApp = "Kitty"
customized.herdrPanelHotKey = HotKeySpec(keyCode: 40, modifiers: [.command, .shift])
try? customized.save(to: emptyStore)
require(HerdrPreferences.load(from: emptyStore) == customized, "preferences round-trip")

let sparseStore = MemoryStore()
sparseStore.data = Data(#"{"terminalApp":"WezTerm","unknown_future_field":true}"#.utf8)
let sparse = HerdrPreferences.load(from: sparseStore)
require(sparse.terminalApp == "WezTerm", "partial file keeps provided value")
require(sparse.herdrPanelHotKey == .defaultHerdrToggle && sparse.tailnetDiscoveryEnabled, "partial file backfills defaults")
require(sparse.version == HerdrPreferences.currentVersion, "partial file gets current version")

let corruptStore = MemoryStore()
corruptStore.data = Data("{not json".utf8)
require(HerdrPreferences.load(from: corruptStore) == HerdrPreferences.default(), "corrupt file yields defaults")

// MARK: - Phase 2 preference field checks

let phase2Defaults = HerdrPreferences.default()
require(phase2Defaults.refreshInterval == 30, "default refresh cadence matches live behavior")
require(phase2Defaults.defaultLocation == .local && phase2Defaults.defaultTargetKind == .containers, "default panel scope matches live behavior")
require(phase2Defaults.hiddenHosts.isEmpty, "no hosts hidden by default")
require(phase2Defaults.terminalApp == HerdrTerminal.default.rawValue && phase2Defaults.terminalApp == "Ghostty", "default terminal is Ghostty")

require(HerdrPreferences.clampedRefreshInterval(1) == 5, "refresh clamps low")
require(HerdrPreferences.clampedRefreshInterval(100_000) == 3600, "refresh clamps high")
var clampCheck = phase2Defaults
clampCheck.refreshInterval = 2
require(clampCheck.refreshInterval == 5, "refresh setter clamps")

var phase2Prefs = phase2Defaults
phase2Prefs.refreshInterval = 120
phase2Prefs.defaultLocation = .tailnet
phase2Prefs.defaultTargetKind = .agents
phase2Prefs.hiddenHosts = ["studio", "pve1.lan"]
let phase2Store = MemoryStore()
try? phase2Prefs.save(to: phase2Store)
require(HerdrPreferences.load(from: phase2Store) == phase2Prefs, "phase 2 fields round-trip")

let phase2Sparse = MemoryStore()
phase2Sparse.data = Data(#"{"terminalApp":"kitty"}"#.utf8)
let sparsePhase2 = HerdrPreferences.load(from: phase2Sparse)
require(sparsePhase2.refreshInterval == 30 && sparsePhase2.defaultLocation == .local && sparsePhase2.hiddenHosts.isEmpty, "phase 1 file backfills phase 2 fields")

let futureEnumStore = MemoryStore()
futureEnumStore.data = Data(#"{"defaultLocation":"multiverse","defaultTargetKind":"agents","refreshInterval":60}"#.utf8)
let futureEnum = HerdrPreferences.load(from: futureEnumStore)
require(futureEnum.defaultLocation == .local, "unknown future enum degrades to default")
require(futureEnum.defaultTargetKind == .agents && futureEnum.refreshInterval == 60, "known fields survive unknown enum")

let badHostsStore = MemoryStore()
badHostsStore.data = Data(#"{"hiddenHosts":["ok-host","bad;host","$(pwn)","also.ok"]}"#.utf8)
require(HerdrPreferences.load(from: badHostsStore).hiddenHosts == ["ok-host", "also.ok"], "invalid hidden hosts are dropped on load")

let invalidHotKeyStore = MemoryStore()
invalidHotKeyStore.data = Data(#"{"herdrPanelHotKey":{"keyCode":4,"modifiers":[]}}"#.utf8)
require(
    HerdrPreferences.load(from: invalidHotKeyStore).herdrPanelHotKey == .defaultHerdrToggle,
    "invalid stored hotkey degrades to default"
)

// MARK: - Validation checks

require(HotKeySpec(keyCode: 4, modifiers: [.command]).isValid, "default hotkey validates")
require(!HotKeySpec(keyCode: 4, modifiers: []).isValid, "modifier-less hotkey rejected")
require(!HotKeySpec(keyCode: 999, modifiers: [.command]).isValid, "out-of-range key code rejected")

require(HerdrPreferences.isValidHostName("pve1.tail-net.ts.net"), "valid host accepted")
require(!HerdrPreferences.isValidHostName("host name"), "space in host rejected")
require(!HerdrPreferences.isValidHostName("host;rm -rf"), "metacharacters in host rejected")
require(!HerdrPreferences.isValidHostName(""), "empty host rejected")

require(HerdrTerminal(rawValue: "Ghostty") == .ghostty && HerdrTerminal.allCases.count == 4, "terminal catalog")

let diagnostics = HerdrDiagnostics.report(
    snapshot: liveSnapshot,
    preferences: phase2Defaults,
    appVersion: "1.2.3",
    operatingSystem: "macOS test"
)
require(diagnostics.contains("App version: 1.2.3"), "diagnostics includes version")
require(diagnostics.contains("Tailnet hosts: 1") && diagnostics.contains("Tailnet agents: 1"), "diagnostics includes counts")
require(!diagnostics.contains("studio"), "diagnostics redacts hostnames")
require(!diagnostics.contains(NSHomeDirectory()), "diagnostics redacts home directory")

var hiddenPrefs = phase2Defaults
hiddenPrefs.hiddenHosts = ["STUDIO"]
require(hiddenPrefs.isHostHidden("studio"), "hidden host match is case-insensitive")

// MARK: - Hidden-host discovery filtering

var hiddenHostPreferences = checkPreferences
hiddenHostPreferences.hiddenHosts = ["Studio"]
let hiddenSnapshot = HerdrSessionDiscovery(preferences: hiddenHostPreferences, runner: liveRunner).snapshot()
require(hiddenSnapshot.remoteHosts.isEmpty && hiddenSnapshot.localStatus == .ok, "hidden hosts are filtered from discovery")
require(HerdrSessionDiscovery(preferences: checkPreferences, runner: liveRunner).snapshot().remoteHosts.count == 1, "unhidden hosts still discovered")

// MARK: - Reliability: failure causes

require(
    HerdrContractError.emptyPayload(.workspaces).userDescription == "The herdr CLI didn't respond.",
    "empty payload maps to friendly cause"
)
require(
    HerdrContractError.malformed(.agents, detail: "x").userDescription.contains("contract v\(HerdrContract.localVersion)"),
    "malformed payload names the contract version"
)
require(
    deadSnapshot.localStatus == .unavailable(reason: "The herdr CLI didn't respond."),
    "discovery surfaces the friendly cause"
)

// MARK: - Reliability: discovery health reducer

let panelPolicy = RetryPolicy.panelRetry
var health = HerdrDiscoveryHealth()
require(health.state == .idle && health.retryDelay == nil, "health starts idle")

health = health.updating(with: liveSnapshot, policy: panelPolicy)
require(health.state == .connected && health.consecutiveFailures == 0 && health.retryDelay == nil, "success connects and resets")

health = health.updating(with: deadSnapshot, policy: panelPolicy)
require(health.state == .failed(attempt: 1, reason: "The herdr CLI didn't respond.") && health.retryDelay == 1, "first failure schedules 1s retry")
health = health.updating(with: deadSnapshot, policy: panelPolicy)
require(health.consecutiveFailures == 2 && health.retryDelay == 2, "second failure backs off")
for _ in 0..<3 { health = health.updating(with: deadSnapshot, policy: panelPolicy) }
require(health.consecutiveFailures == 5 && health.retryDelay == 16, "fifth failure hits the cap")
health = health.updating(with: deadSnapshot, policy: panelPolicy)
require(health.consecutiveFailures == 6 && health.retryDelay == nil, "policy exhaustion stops auto-retry")
health = health.updating(with: liveSnapshot, policy: panelPolicy)
require(health.state == .connected && health.consecutiveFailures == 0, "recovery resets the failure count")
require(HerdrDiscoveryHealth().updating(with: HerdrSnapshot(), policy: panelPolicy).state == .refreshing, "not-loaded snapshot reads as refreshing")

// MARK: - Reliability: panel issue classification

func issue(_ snapshot: HerdrSnapshot, _ location: HerdrLocation, _ kind: HerdrTargetKind, tailnet: Bool = true) -> HerdrPanelIssue? {
    HerdrPanelStatus.issue(snapshot: snapshot, location: location, kind: kind, tailnetDiscoveryEnabled: tailnet)
}

require(issue(HerdrSnapshot(), .local, .containers) == .loading, "local not-loaded is loading")
require(issue(liveSnapshot, .local, .containers) == nil, "local content has no issue")
require(issue(liveSnapshot, .local, .agents) == nil, "local agents present has no issue")
require(issue(deadSnapshot, .local, .containers) == .localUnavailable(reason: "The herdr CLI didn't respond."), "dead local CLI carries its cause")

let emptyLocalSnapshot = HerdrSnapshot(localStatus: .ok)
require(issue(emptyLocalSnapshot, .local, .containers) == .noLocalSessions, "zero workspaces is an explicit empty state")

let workspacesOnlySnapshot = HerdrSnapshot(workspaces: liveSnapshot.workspaces, localStatus: .ok)
require(issue(workspacesOnlySnapshot, .local, .containers) == nil, "workspaces without agents render as containers")
require(issue(workspacesOnlySnapshot, .local, .agents) == .noLocalAgents, "agents kind with zero agents is explicit, not blank")
let agentsOnlySnapshot = HerdrSnapshot(agents: liveSnapshot.agents, localStatus: .ok)
require(issue(agentsOnlySnapshot, .local, .agents) == nil, "agents list renders independently of workspace availability")
require(issue(agentsOnlySnapshot, .local, .containers) == .noLocalSessions, "empty workspace list stays explicit")

require(issue(liveSnapshot, .tailnet, .containers, tailnet: false) == .tailnetDisabled, "tailnet scope with discovery off says so")
require(issue(liveSnapshot, .tailnet, .containers) == nil, "tailnet hosts render")
require(issue(liveSnapshot, .tailnet, .agents) == nil, "tailnet agents render")
require(issue(emptyLocalSnapshot, .tailnet, .containers) == .noTailnetSessions, "no hosts after load is explicit")
require(issue(HerdrSnapshot(), .tailnet, .containers) == .loading, "no hosts before load is loading")

let agentlessHostSnapshot = HerdrSnapshot(remoteHosts: [RemoteHerdrHost(host: "studio", agents: [])], localStatus: .ok)
require(issue(agentlessHostSnapshot, .tailnet, .agents) == .noTailnetAgents, "hosts without agents make the agents list explicit")
require(issue(agentlessHostSnapshot, .tailnet, .containers) == nil, "hosts without agents still render as containers")

// MARK: - Onboarding: environment report and completion flag

let readyReport = HerdrEnvironmentReport.evaluate(preferences: checkPreferences) { _ in true }
require(readyReport.ready && readyReport.items.count == 3 && readyReport.missingRequired.isEmpty, "all tools present is ready")
require(readyReport.items[0].path == "/fake/herdr" && readyReport.items[0].required, "herdr CLI is the required item")

let missingHerdrReport = HerdrEnvironmentReport.evaluate(preferences: checkPreferences) { $0 != "/fake/herdr" }
require(!missingHerdrReport.ready && missingHerdrReport.missingRequired.map(\.id) == ["herdr-cli"], "missing herdr CLI blocks readiness")

let helpersMissingReport = HerdrEnvironmentReport.evaluate(preferences: checkPreferences) { $0 == "/fake/herdr" }
require(helpersMissingReport.ready && helpersMissingReport.items.filter { !$0.available }.count == 2, "missing optional helpers keep readiness")

require(!HerdrPreferences.default().onboardingCompleted, "onboarding starts incomplete")
var onboardedPrefs = HerdrPreferences.default()
onboardedPrefs.onboardingCompleted = true
let onboardingStore = MemoryStore()
try? onboardedPrefs.save(to: onboardingStore)
require(HerdrPreferences.load(from: onboardingStore).onboardingCompleted, "onboarding completion round-trips")
let preOnboardingStore = MemoryStore()
preOnboardingStore.data = Data(#"{"terminalApp":"Ghostty"}"#.utf8)
require(!HerdrPreferences.load(from: preOnboardingStore).onboardingCompleted, "pre-onboarding files backfill incomplete")

print("HerdrCore checks passed")
