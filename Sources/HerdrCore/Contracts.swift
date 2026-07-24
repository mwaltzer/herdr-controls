import Foundation

/// Versioned wire contracts for Herdr session discovery.
///
/// `localVersion` covers the JSON envelopes printed by `herdr workspace list`
/// and `herdr agent list`. `tailnetVersion` covers the aggregated host array
/// produced by the `herdr-tailnet-sessions` helper. Bump a version whenever a
/// decoder stops accepting a previously valid payload, and keep decoders
/// tolerant of unknown fields so newer producers keep working.
public enum HerdrContract {
    public static let localVersion = 2
    public static let tailnetVersion = 1
}

public struct HerdrVCSMetadata: Equatable, Sendable {
    public let provider: String
    public let reference: String?
    public let change: String?
    public let dirty: Bool

    public init(provider: String, reference: String?, change: String?, dirty: Bool) {
        self.provider = provider
        self.reference = reference
        self.change = change
        self.dirty = dirty
    }
}

public struct HerdrWorkspace: Identifiable, Decodable, Equatable, Sendable {
    public let workspaceID: String
    public let label: String
    public let number: Int
    public let agentStatus: String
    public let focused: Bool
    public let tokens: [String: String]

    public var id: String { workspaceID }
    public var vcs: HerdrVCSMetadata? {
        guard let provider = tokens["vcs_provider"], provider == "jj" || provider == "git" else {
            return nil
        }
        return HerdrVCSMetadata(
            provider: provider,
            reference: tokens["vcs_ref"],
            change: tokens["vcs_change"],
            dirty: tokens["vcs_dirty"] == "true"
        )
    }

    enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace_id"
        case label, number
        case agentStatus = "agent_status"
        case focused, tokens
    }

    public init(
        workspaceID: String,
        label: String,
        number: Int,
        agentStatus: String,
        focused: Bool,
        tokens: [String: String] = [:]
    ) {
        self.workspaceID = workspaceID
        self.label = label
        self.number = number
        self.agentStatus = agentStatus
        self.focused = focused
        self.tokens = tokens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspaceID = try container.decode(String.self, forKey: .workspaceID)
        label = try container.decode(String.self, forKey: .label)
        number = try container.decode(Int.self, forKey: .number)
        agentStatus = try container.decode(String.self, forKey: .agentStatus)
        focused = try container.decode(Bool.self, forKey: .focused)
        tokens = try container.decodeIfPresent([String: String].self, forKey: .tokens) ?? [:]
    }
}

public struct HerdrAgent: Identifiable, Decodable, Equatable, Sendable {
    public let agent: String
    public let agentStatus: String
    public let paneID: String
    public let workspaceID: String
    public let terminalTitleStripped: String
    public let focused: Bool
    public let cwd: String?
    public let stateChangeSequence: UInt64
    public let tokens: [String: String]

    public var id: String { paneID }

    enum CodingKeys: String, CodingKey {
        case agent
        case agentStatus = "agent_status"
        case paneID = "pane_id"
        case workspaceID = "workspace_id"
        case terminalTitleStripped = "terminal_title_stripped"
        case focused
        case cwd, tokens
        case stateChangeSequence = "state_change_seq"
    }

    public init(
        agent: String,
        agentStatus: String,
        paneID: String,
        workspaceID: String,
        terminalTitleStripped: String,
        focused: Bool,
        cwd: String? = nil,
        stateChangeSequence: UInt64 = 0,
        tokens: [String: String] = [:]
    ) {
        self.agent = agent
        self.agentStatus = agentStatus
        self.paneID = paneID
        self.workspaceID = workspaceID
        self.terminalTitleStripped = terminalTitleStripped
        self.focused = focused
        self.cwd = cwd
        self.stateChangeSequence = stateChangeSequence
        self.tokens = tokens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        agent = try container.decodeIfPresent(String.self, forKey: .agent) ?? "agent"
        agentStatus = try container.decode(String.self, forKey: .agentStatus)
        paneID = try container.decode(String.self, forKey: .paneID)
        workspaceID = try container.decode(String.self, forKey: .workspaceID)
        terminalTitleStripped = try container.decodeIfPresent(String.self, forKey: .terminalTitleStripped) ?? agent
        focused = try container.decode(Bool.self, forKey: .focused)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        stateChangeSequence = try container.decodeIfPresent(UInt64.self, forKey: .stateChangeSequence) ?? 0
        tokens = try container.decodeIfPresent([String: String].self, forKey: .tokens) ?? [:]
    }
}

public struct RemoteHerdrHost: Identifiable, Decodable, Equatable, Sendable {
    public let host: String
    public let agents: [HerdrAgent]
    public let dnsName: String?
    public let tailnetIP: String?
    public let operatingSystem: String?
    public let connectionStatus: String

    public var id: String { host }
    public var reachable: Bool { connectionStatus == "online" }

    enum CodingKeys: String, CodingKey {
        case host, agents
        case dnsName = "dns_name"
        case tailnetIP = "tailnet_ip"
        case operatingSystem = "os"
        case connectionStatus = "connection_status"
    }

    public init(
        host: String,
        agents: [HerdrAgent],
        dnsName: String? = nil,
        tailnetIP: String? = nil,
        operatingSystem: String? = nil,
        connectionStatus: String = "online"
    ) {
        self.host = host
        self.agents = agents
        self.dnsName = dnsName
        self.tailnetIP = tailnetIP
        self.operatingSystem = operatingSystem
        self.connectionStatus = connectionStatus
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decode(String.self, forKey: .host)
        agents = try container.decodeIfPresent([HerdrAgent].self, forKey: .agents) ?? []
        dnsName = try container.decodeIfPresent(String.self, forKey: .dnsName)
        tailnetIP = try container.decodeIfPresent(String.self, forKey: .tailnetIP)
        operatingSystem = try container.decodeIfPresent(String.self, forKey: .operatingSystem)
        connectionStatus = try container.decodeIfPresent(String.self, forKey: .connectionStatus) ?? "online"
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
    private struct SnapshotEnvelope: Decodable {
        struct Result: Decodable {
            struct Snapshot: Decodable {
                let workspaces: [HerdrWorkspace]
                let agents: [HerdrAgent]
            }
            let snapshot: Snapshot
        }
        let result: Result
    }
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

    public static func decodeSnapshot(_ data: Data) throws -> (workspaces: [HerdrWorkspace], agents: [HerdrAgent]) {
        guard !data.isEmpty else { throw HerdrContractError.emptyPayload(.workspaces) }
        do {
            let snapshot = try JSONDecoder().decode(SnapshotEnvelope.self, from: data).result.snapshot
            return (snapshot.workspaces, snapshot.agents)
        } catch {
            throw HerdrContractError.malformed(.workspaces, detail: String(describing: error))
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
