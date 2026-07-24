import AppKit
import Combine
import HerdrCore
import SketchyControlsCore

@MainActor
final class StatusItemController: NSObject {
    private let model: AppModel
    private let panelController: PanelController
    private let statusItem: NSStatusItem
    private var herdrObservation: AnyCancellable?

    init(model: AppModel, panelController: PanelController) {
        self.model = model
        self.panelController = panelController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureButton()
        herdrObservation = model.$herdr
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.update(snapshot)
            }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }

        let image = Bundle.main
            .url(forResource: "herdr-mask", withExtension: "svg")
            .flatMap(NSImage.init(contentsOf:))
            ?? NSImage(
                systemSymbolName: "rectangle.3.group.bubble.left.fill",
                accessibilityDescription: "Herdr"
            )
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)

        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = "Herdr"
        button.setAccessibilityLabel("Herdr")
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func update(_ snapshot: HerdrSnapshot) {
        guard let button = statusItem.button else { return }
        let localCount = snapshot.agents.count
        let remoteCount = snapshot.remoteHosts.reduce(0) { $0 + $1.agents.count }
        let total = localCount + remoteCount

        switch snapshot.localStatus {
        case .notLoaded:
            button.toolTip = "Herdr — loading sessions"
        case .ok:
            button.toolTip = "Herdr — \(total) \(total == 1 ? "session" : "sessions")"
        case .unavailable:
            button.toolTip = remoteCount > 0
                ? "Herdr — local unavailable, \(remoteCount) remote \(remoteCount == 1 ? "session" : "sessions")"
                : "Herdr — sessions unavailable"
        }
        button.setAccessibilityLabel(button.toolTip ?? "Herdr")
    }

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    func togglePanel() {
        guard let button = statusItem.button, let window = button.window else {
            panelController.show(kind: .herdr, point: nil, toggle: true)
            return
        }

        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        panelController.show(
            kind: .herdr,
            point: NSPoint(x: buttonFrame.midX, y: buttonFrame.minY),
            toggle: true,
            topEdge: buttonFrame.minY - 6
        )
    }

    func togglePanelFromHotKey() {
        guard
            let path = ProcessInfo.processInfo.environment["HERDR_PANEL_ANCHOR_EXECUTABLE"],
            FileManager.default.isExecutableFile(atPath: path)
        else {
            togglePanel()
            return
        }

        Task { [weak self] in
            let anchor = await Task.detached(priority: .userInitiated) {
                Self.configuredSketchyBarAnchor(path: path)
            }.value
            guard let self else { return }
            guard let anchor else {
                togglePanel()
                return
            }
            panelController.show(
                kind: .herdr,
                point: anchor,
                toggle: true,
                topEdge: anchor.y - 6
            )
        }
    }

    nonisolated private static func configuredSketchyBarAnchor(path: String) -> NSPoint? {
        guard let result = BoundedProcess.run(
            executable: path,
            arguments: [],
            timeout: 0.5,
            outputLimit: 1_024
        ), !result.timedOut, result.terminationStatus == 0,
           let value = String(data: result.output, encoding: .utf8)
        else { return nil }
        let coordinates = value.split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
        guard coordinates.count >= 2 else { return nil }
        return NSPoint(x: coordinates[0], y: coordinates[1])
    }

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Herdr Controls", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
