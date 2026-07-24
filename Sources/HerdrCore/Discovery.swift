import Foundation

/// Abstracts process execution so discovery logic stays testable without a
/// live `herdr` install. Implementations must return captured stdout, or empty
/// `Data` when the executable is missing, fails to launch, or prints nothing.
public protocol HerdrCommandRunning: Sendable {
    func output(executable: String, arguments: [String]) -> Data
}

public enum HerdrLocalStatus: Equatable, Sendable {
    case notLoaded
    case ok
    case unavailable(reason: String)
}

public struct HerdrSnapshot: Equatable, Sendable {
    public var workspaces: [HerdrWorkspace]
    public var agents: [HerdrAgent]
    public var remoteHosts: [RemoteHerdrHost]
    public var localStatus: HerdrLocalStatus

    public init(
        workspaces: [HerdrWorkspace] = [],
        agents: [HerdrAgent] = [],
        remoteHosts: [RemoteHerdrHost] = [],
        localStatus: HerdrLocalStatus = .notLoaded
    ) {
        self.workspaces = workspaces
        self.agents = agents
        self.remoteHosts = remoteHosts
        self.localStatus = localStatus
    }

    /// The panel has something to show: the local CLI answered (even with zero
    /// sessions), or at least one tailnet host reported agents.
    public var available: Bool {
        if case .ok = localStatus { return true }
        return !remoteHosts.isEmpty
    }
}

public struct HerdrSessionDiscovery: Sendable {
    public let preferences: HerdrPreferences
    public let runner: any HerdrCommandRunning

    public init(preferences: HerdrPreferences, runner: any HerdrCommandRunning) {
        self.preferences = preferences
        self.runner = runner
    }

    /// Remote discovery failures degrade to an empty host list; local CLI
    /// failures degrade to a tailnet-only snapshot with the failure reason.
    public func snapshot() -> HerdrSnapshot {
        var remoteHosts: [RemoteHerdrHost] = []
        if preferences.tailnetDiscoveryEnabled {
            let remoteData = runner.output(executable: preferences.tailnetSessionsExecutable, arguments: [])
            remoteHosts = ((try? HerdrTailnetContract.decodeHosts(remoteData)) ?? [])
                .filter { !preferences.isHostHidden($0.host) }
        }

        do {
            let snapshotData = runner.output(executable: preferences.herdrExecutable, arguments: ["api", "snapshot"])
            if let native = try? HerdrLocalContract.decodeSnapshot(snapshotData) {
                return HerdrSnapshot(
                    workspaces: native.workspaces,
                    agents: native.agents,
                    remoteHosts: remoteHosts,
                    localStatus: .ok
                )
            }

            // Herdr < 0.7.5 fallback. Keeping this path makes upgrades
            // independent and avoids coupling the app to a single release.
            let workspaceData = runner.output(executable: preferences.herdrExecutable, arguments: ["workspace", "list"])
            let agentData = runner.output(executable: preferences.herdrExecutable, arguments: ["agent", "list"])
            return HerdrSnapshot(
                workspaces: try HerdrLocalContract.decodeWorkspaces(workspaceData),
                agents: try HerdrLocalContract.decodeAgents(agentData),
                remoteHosts: remoteHosts,
                localStatus: .ok
            )
        } catch {
            let reason = (error as? HerdrContractError)?.userDescription ?? String(describing: error)
            return HerdrSnapshot(remoteHosts: remoteHosts, localStatus: .unavailable(reason: reason))
        }
    }
}
