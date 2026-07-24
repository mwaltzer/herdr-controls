import Foundation

/// Versioned wire contracts for Herdr session discovery.
///
/// `localVersion` covers the JSON envelopes printed by `herdr workspace list`
/// and `herdr agent list`. `tailnetVersion` covers the aggregated host array
/// produced by the `herdr-tailnet-sessions` helper. Bump a version whenever a
/// decoder stops accepting a previously valid payload, and keep decoders
/// tolerant of unknown fields so newer producers keep working.
public enum HerdrContract {
    public static let localVersion = 1
    public static let tailnetVersion = 1
}

public struct HerdrWorkspace: Identifiable, Decodable, Equatable, Sendable {
    public let workspaceID: String
    public let label: String
    public let number: Int
    public let agentStatus: String
    public let focused: Bool

    public var id: String { workspaceID }

    enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace_id"
        case label, number
        case agentStatus = "agent_status"
        case focused
    }

    public init(workspaceID: String, label: String, number: Int, agentStatus: String, focused: Bool) {
        self.workspaceID = workspaceID
        self.label = label
        self.number = number
        self.agentStatus = agentStatus
        self.focused = focused
    }
}

public struct HerdrAgent: Identifiable, Decodable, Equatable, Sendable {
    public let agent: String
    public let agentStatus: String
    public let paneID: String
    public let workspaceID: String
    public let terminalTitleStripped: String
    public let focused: Bool

    public var id: String { paneID }

    enum CodingKeys: String, CodingKey {
        case agent
        case agentStatus = "agent_status"
        case paneID = "pane_id"
        case workspaceID = "workspace_id"
        case terminalTitleStripped = "terminal_title_stripped"
        case focused
    }

    public init(
        agent: String,
        agentStatus: String,
        paneID: String,
        workspaceID: String,
        terminalTitleStripped: String,
        focused: Bool
    ) {
        self.agent = agent
        self.agentStatus = agentStatus
        self.paneID = paneID
        self.workspaceID = workspaceID
        self.terminalTitleStripped = terminalTitleStripped
        self.focused = focused
    }
}

public struct RemoteHerdrHost: Identifiable, Decodable, Equatable, Sendable {
    public let host: String
    public let agents: [HerdrAgent]

    public var id: String { host }

    public init(host: String, agents: [HerdrAgent]) {
        self.host = host
        self.agents = agents
    }
}

public enum HerdrContractPayload: String, Sendable {
    case workspaces
    case agents
    case tailnetHosts
}

public enum HerdrContractError: Error, Equatable, Sendable {
    case emptyPayload(HerdrContractPayload)
    case malformed(HerdrContractPayload, detail: String)

    /// Short, user-facing cause for the Herdr panel and diagnostics. An empty
    /// payload means the producer never answered (missing binary, dead
    /// daemon); a malformed one means it answered in a shape this app's
    /// contract version doesn't accept.
    public var userDescription: String {
        switch self {
        case .emptyPayload(.workspaces), .emptyPayload(.agents):
            "The herdr CLI didn't respond."
        case .emptyPayload(.tailnetHosts):
            "The tailnet session helper didn't respond."
        case .malformed(.workspaces, _), .malformed(.agents, _):
            "Unexpected herdr CLI output (contract v\(HerdrContract.localVersion) mismatch)."
        case .malformed(.tailnetHosts, _):
            "Unexpected tailnet helper output (contract v\(HerdrContract.tailnetVersion) mismatch)."
        }
    }
}

/// Decoders for the local `herdr` CLI envelopes (`{"result": {...}}`).
public enum HerdrLocalContract {
    private struct WorkspaceEnvelope: Decodable {
        struct Result: Decodable { let workspaces: [HerdrWorkspace] }
        let result: Result
    }

    private struct AgentEnvelope: Decodable {
        struct Result: Decodable { let agents: [HerdrAgent] }
        let result: Result
    }

    public static func decodeWorkspaces(_ data: Data) throws -> [HerdrWorkspace] {
        guard !data.isEmpty else { throw HerdrContractError.emptyPayload(.workspaces) }
        do {
            return try JSONDecoder().decode(WorkspaceEnvelope.self, from: data).result.workspaces
        } catch {
            throw HerdrContractError.malformed(.workspaces, detail: String(describing: error))
        }
    }

    public static func decodeAgents(_ data: Data) throws -> [HerdrAgent] {
        guard !data.isEmpty else { throw HerdrContractError.emptyPayload(.agents) }
        do {
            return try JSONDecoder().decode(AgentEnvelope.self, from: data).result.agents
        } catch {
            throw HerdrContractError.malformed(.agents, detail: String(describing: error))
        }
    }
}

/// Decoder for the `herdr-tailnet-sessions` aggregated host array.
public enum HerdrTailnetContract {
    public static func decodeHosts(_ data: Data) throws -> [RemoteHerdrHost] {
        guard !data.isEmpty else { throw HerdrContractError.emptyPayload(.tailnetHosts) }
        do {
            return try JSONDecoder().decode([RemoteHerdrHost].self, from: data)
        } catch {
            throw HerdrContractError.malformed(.tailnetHosts, detail: String(describing: error))
        }
    }
}
