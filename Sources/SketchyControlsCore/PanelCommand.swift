import Foundation

public enum PanelKind: String, Codable, CaseIterable, Sendable {
    case controlCenter = "control-center"
    case audio
    case network
    case power
    case focusDisplay = "focus-display"
    case calendar
    case performance
    case herdr
    case session

    public var title: String {
        switch self {
        case .controlCenter: "Control Center"
        case .audio: "Sound"
        case .network: "Network"
        case .power: "Power"
        case .focusDisplay: "Focus & Display"
        case .calendar: "Agenda"
        case .performance: "Performance"
        case .herdr: "Herdr"
        case .session: "Quick Actions"
        }
    }
}

public enum PanelAction: String, Codable, Sendable {
    case toggle
    case show
    case dismiss
    case status
}

public struct PanelCommand: Codable, Equatable, Sendable {
    public let action: PanelAction
    public let panel: PanelKind?
    public let source: String?
    public let mouseX: Double?
    public let mouseY: Double?

    public init(
        action: PanelAction,
        panel: PanelKind? = nil,
        source: String? = nil,
        mouseX: Double? = nil,
        mouseY: Double? = nil
    ) {
        self.action = action
        self.panel = panel
        self.source = source
        self.mouseX = mouseX
        self.mouseY = mouseY
    }

    public static func parse(arguments: [String], mouse: (Double, Double)? = nil) throws -> PanelCommand {
        guard let action = arguments.first.flatMap(PanelAction.init(rawValue:)) else {
            throw CommandError.usage
        }

        if action == .dismiss || action == .status {
            return PanelCommand(action: action, mouseX: mouse?.0, mouseY: mouse?.1)
        }

        guard arguments.count >= 2, let panel = PanelKind(rawValue: arguments[1]) else {
            throw CommandError.usage
        }

        var source: String?
        if let index = arguments.firstIndex(of: "--source"), arguments.indices.contains(index + 1) {
            source = arguments[index + 1]
        }
        let argumentMouse: (Double, Double)? = {
            guard
                let xIndex = arguments.firstIndex(of: "--mouse-x"),
                arguments.indices.contains(xIndex + 1),
                let x = Double(arguments[xIndex + 1]),
                let yIndex = arguments.firstIndex(of: "--mouse-y"),
                arguments.indices.contains(yIndex + 1),
                let y = Double(arguments[yIndex + 1])
            else { return nil }
            return (x, y)
        }()
        let resolvedMouse = mouse ?? argumentMouse

        return PanelCommand(
            action: action,
            panel: panel,
            source: source,
            mouseX: resolvedMouse?.0,
            mouseY: resolvedMouse?.1
        )
    }
}

public enum CommandError: Error, LocalizedError {
    case usage

    public var errorDescription: String? {
        "usage: sketchy-controls (toggle|show) PANEL [--source ITEM] [--mouse-x X --mouse-y Y] | dismiss | status"
    }
}

public enum IPCPath {
    public static var socket: String {
        let base = ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp"
        return URL(fileURLWithPath: base)
            .appendingPathComponent("sketchy-controls-\(getuid()).sock")
            .path
    }
}
