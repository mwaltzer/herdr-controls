import Foundation

public enum HerdrLocation: String, Codable, Sendable {
    case local
    case tailnet
}

public enum HerdrTargetKind: String, Codable, Sendable {
    case containers
    case agents
}

public struct HerdrTarget: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case workspace(String)
        case agent(String)
        case remoteHost(host: String, firstPane: String)
        case remoteAgent(host: String, pane: String)
    }

    public let key: String
    public let action: Action

    public init(key: String, action: Action) {
        self.key = key
        self.action = action
    }
}

/// Pure keyboard-navigation model over a discovery snapshot. Target keys match
/// the row identifiers the UI renders (`workspace:`, `agent:`, `host:`,
/// `remote:` prefixes), so selection state survives refreshes.
public enum HerdrNavigation {
    /// Full ordered target list: each workspace followed by its agents, then
    /// each tailnet host followed by its remote agents. Hosts with no agents
    /// yield no host row (there is nothing to attach to).
    public static func targets(in snapshot: HerdrSnapshot) -> [HerdrTarget] {
        var targets: [HerdrTarget] = []
        for workspace in snapshot.workspaces {
            targets.append(HerdrTarget(key: "workspace:\(workspace.id)", action: .workspace(workspace.id)))
            targets += snapshot.agents
                .filter { $0.workspaceID == workspace.id }
                .map { HerdrTarget(key: "agent:\($0.id)", action: .agent($0.id)) }
        }
        for remote in snapshot.remoteHosts {
            if let firstAgent = remote.agents.first {
                targets.append(HerdrTarget(
                    key: "host:\(remote.host)",
                    action: .remoteHost(host: remote.host, firstPane: firstAgent.id)
                ))
            }
            targets += remote.agents.map {
                HerdrTarget(key: "remote:\(remote.host):\($0.id)", action: .remoteAgent(host: remote.host, pane: $0.id))
            }
        }
        return targets
    }

    public static func scopedTargets(
        in snapshot: HerdrSnapshot,
        location: HerdrLocation,
        kind: HerdrTargetKind
    ) -> [HerdrTarget] {
        targets(in: snapshot).filter { target in
            switch (location, kind, target.action) {
            case (.local, .containers, .workspace), (.local, .agents, .agent):
                true
            case (.tailnet, .containers, .remoteHost), (.tailnet, .agents, .remoteAgent):
                true
            default:
                false
            }
        }
    }

    /// Moves the selection by `delta` with wrap-around; entering an unselected
    /// list lands on the first (moving down) or last (moving up) target.
    public static func movedSelection(from current: String?, by delta: Int, in targets: [HerdrTarget]) -> String? {
        guard !targets.isEmpty else { return current }
        guard let index = targets.firstIndex(where: { $0.key == current }) else {
            return delta > 0 ? targets.first?.key : targets.last?.key
        }

        let next = index + delta
        if targets.indices.contains(next) {
            return targets[next].key
        }
        return delta > 0 ? targets.first?.key : targets.last?.key
    }

    /// After a refresh: drop a selection whose target disappeared.
    public static func normalizedSelection(_ current: String?, in targets: [HerdrTarget]) -> String? {
        guard let current else { return nil }
        return targets.contains(where: { $0.key == current }) ? current : nil
    }

    /// After a scope change: snap an out-of-scope selection to the first
    /// target in the new scope (or nil when the scope is empty).
    public static func scopedSelection(_ current: String?, in targets: [HerdrTarget]) -> String? {
        if targets.contains(where: { $0.key == current }) { return current }
        return targets.first?.key
    }

    /// Preserve the selected container/agent relationship while switching
    /// between the two list types. Falls back to the normal scoped selection
    /// when the selected container has no agent or its relationship vanished.
    public static func selectionWhenChangingKind(
        from current: String?,
        to kind: HerdrTargetKind,
        location: HerdrLocation,
        in snapshot: HerdrSnapshot
    ) -> String? {
        let scoped = scopedTargets(in: snapshot, location: location, kind: kind)
        guard
            let current,
            let selected = targets(in: snapshot).first(where: { $0.key == current })
        else {
            return scopedSelection(current, in: scoped)
        }

        let related: String?
        switch (location, kind, selected.action) {
        case let (.local, .agents, .workspace(workspaceID)):
            related = snapshot.agents.first(where: { $0.workspaceID == workspaceID })
                .map { "agent:\($0.id)" }
        case let (.local, .containers, .agent(agentID)):
            related = snapshot.agents.first(where: { $0.id == agentID })
                .map { "workspace:\($0.workspaceID)" }
        case let (.tailnet, .agents, .remoteHost(host, _)):
            related = snapshot.remoteHosts.first(where: { $0.host == host })?.agents.first
                .map { "remote:\(host):\($0.id)" }
        case let (.tailnet, .containers, .remoteAgent(host, _)):
            related = "host:\(host)"
        default:
            related = nil
        }

        if let related, scoped.contains(where: { $0.key == related }) {
            return related
        }
        return scopedSelection(current, in: scoped)
    }
}
