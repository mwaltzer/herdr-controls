import AppKit
import QuartzCore
import SketchyControlsCore
import SwiftUI

final class ControlPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController {
    let model: AppModel
    private let panel: ControlPanel
    private let containerView: NSView
    private let contentHost: NSHostingView<PanelRootView>
    private let revealMask = CALayer()
    private var outsideMonitor: Any?
    private var keyMonitor: Any?
    private var lastKind: PanelKind?
    private var isDismissing = false
    private var collapsedOriginX: CGFloat = 0

    private let statusBarInset: CGFloat = 52
    private let openDuration: TimeInterval = 0.42
    private let closeDuration: TimeInterval = 0.24

    init(model: AppModel) {
        self.model = model
        containerView = NSView(frame: .zero)
        contentHost = NSHostingView(rootView: PanelRootView(model: model))
        panel = ControlPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        containerView.wantsLayer = true
        contentHost.wantsLayer = true
        contentHost.autoresizingMask = [.width, .height]
        containerView.addSubview(contentHost)
        revealMask.backgroundColor = NSColor.black.cgColor
        contentHost.layer?.mask = revealMask
        panel.contentView = containerView
        model.showPanel = { [weak self] kind in self?.show(kind: kind, point: nil, toggle: false) }
        model.dismissPanel = { [weak self] in self?.dismiss() }
        model.didRefresh = { [weak self] kind in
            guard let self, self.panel.isVisible, self.lastKind == kind else { return }
            self.resizeToFit()
        }
    }

    func handle(_ command: PanelCommand) {
        switch command.action {
        case .dismiss:
            dismiss()
        case .status:
            break
        case .show, .toggle:
            guard let kind = command.panel else { return }
            let point = command.mouseX.flatMap { x in command.mouseY.map { NSPoint(x: x, y: $0) } }
            show(kind: kind, point: point, toggle: command.action == .toggle)
        }
    }

    func show(kind: PanelKind, point: NSPoint?, toggle: Bool, topEdge: CGFloat? = nil) {
        if toggle && panel.isVisible && lastKind == kind {
            dismiss()
            return
        }

        if kind == .herdr {
            model.clearHerdrSelection()
        }
        model.panel = kind
        contentHost.layoutSubtreeIfNeeded()
        let fitting = contentHost.fittingSize
        let width: CGFloat = kind == .controlCenter ? 440 : kind == .herdr ? 400 : 360
        let height = min(max(fitting.height, 120), 720)
        let anchor = point ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(anchor, $0.frame, false) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let x = min(max(anchor.x - width / 2, visible.minX + 8), visible.maxX - width - 8)
        let panelTop = screen?.frame.maxY ?? visible.maxY
        let y = (topEdge ?? panelTop - statusBarInset) - height
        let finalFrame = NSRect(x: x, y: y, width: width, height: height)
        isDismissing = false
        panel.alphaValue = 1
        panel.setFrame(finalFrame, display: true)
        contentHost.frame = containerView.bounds
        prepareMorph(anchorX: anchor.x, panelFrame: finalFrame)
        panel.orderFrontRegardless()
        panel.makeKey()
        animateMorphOpen()
        lastKind = kind
        installDismissMonitors()
        model.refresh(kind)
    }

    func showFromStatusBar(kind: PanelKind, offsetFromRight: CGFloat, toggle: Bool) {
        guard let screen = NSScreen.main else {
            show(kind: kind, point: nil, toggle: toggle)
            return
        }
        let visible = screen.visibleFrame
        let anchor = NSPoint(x: visible.maxX - offsetFromRight, y: visible.maxY)
        show(kind: kind, point: anchor, toggle: toggle)
    }

    func dismiss() {
        guard panel.isVisible, !isDismissing else { return }
        isDismissing = true
        removeDismissMonitors()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            revealMask.removeAllAnimations()
            panel.orderOut(nil)
            isDismissing = false
            return
        }
        let targetFrame = collapsedFrame(in: containerView.bounds)
        let visibleMask = revealMask.presentation() ?? revealMask
        revealMask.removeAllAnimations()
        addCloseAnimation(keyPath: "bounds", from: visibleMask.bounds, to: CGRect(origin: .zero, size: targetFrame.size))
        addCloseAnimation(keyPath: "position", from: visibleMask.position, to: CGPoint(x: targetFrame.midX, y: targetFrame.midY))
        addCloseAnimation(keyPath: "cornerRadius", from: visibleMask.cornerRadius, to: 15)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        revealMask.frame = targetFrame
        revealMask.cornerRadius = 15
        CATransaction.commit()
        Task { @MainActor [weak self] in
            let duration = self?.closeDuration ?? 0.24
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard let self else { return }
            self.panel.orderOut(nil)
            self.isDismissing = false
        }
    }

    private func installDismissMonitors() {
        removeDismissMonitors()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
                self.dismiss()
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.dismiss()
                return nil
            }
            if self?.lastKind == .herdr {
                if event.keyCode == 48 {
                    self?.model.toggleHerdrLocation()
                    return nil
                }
                switch event.charactersIgnoringModifiers {
                case "j": self?.model.moveHerdrSelection(1); return nil
                case "k": self?.model.moveHerdrSelection(-1); return nil
                case "h": self?.model.setHerdrTargetKind(.containers); return nil
                case "l": self?.model.setHerdrTargetKind(.agents); return nil
                case "\r": self?.model.activateHerdrSelection(); return nil
                default: break
                }
            }
            return event
        }
    }

    private func removeDismissMonitors() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        outsideMonitor = nil
        keyMonitor = nil
    }

    private func prepareMorph(anchorX: CGFloat, panelFrame: NSRect) {
        let localX = min(max(anchorX - panelFrame.minX, 43), panelFrame.width - 43)
        let startFrame = CGRect(x: localX - 43, y: 0, width: 86, height: 30)
        collapsedOriginX = startFrame.minX
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        revealMask.removeAllAnimations()
        revealMask.frame = startFrame
        revealMask.cornerRadius = 15
        revealMask.cornerCurve = .continuous
        CATransaction.commit()
    }

    private func animateMorphOpen() {
        let finalFrame = containerView.bounds
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            revealMask.frame = finalFrame
            revealMask.cornerRadius = 18
            CATransaction.commit()
            return
        }
        addSpring(keyPath: "bounds", from: revealMask.bounds, to: CGRect(origin: .zero, size: finalFrame.size))
        addSpring(keyPath: "position", from: revealMask.position, to: CGPoint(x: finalFrame.midX, y: finalFrame.midY))
        addSpring(keyPath: "cornerRadius", from: 15, to: 18)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        revealMask.frame = finalFrame
        revealMask.cornerRadius = 18
        CATransaction.commit()
    }

    private func addSpring(keyPath: String, from: Any, to: Any) {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.mass = 1
        animation.stiffness = 310
        animation.damping = 29
        animation.initialVelocity = 0
        animation.duration = openDuration
        revealMask.add(animation, forKey: "morph-open-\(keyPath)")
    }

    private func addCloseAnimation(keyPath: String, from: Any, to: Any) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = closeDuration
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.55, 0, 0.85, 0.35)
        revealMask.add(animation, forKey: "morph-close-\(keyPath)")
    }

    private func collapsedFrame(in bounds: CGRect) -> CGRect {
        let x = min(max(collapsedOriginX, 0), bounds.width - 86)
        return CGRect(x: x, y: 0, width: 86, height: 30)
    }

    private func resizeToFit() {
        contentHost.layoutSubtreeIfNeeded()
        let height = min(max(contentHost.fittingSize.height, 120), 720)
        let wasOpening = revealMask.animation(forKey: "morph-open-bounds") != nil
        let visibleMask = revealMask.presentation() ?? revealMask
        let visibleBounds = visibleMask.bounds
        let visiblePosition = visibleMask.position
        let visibleCornerRadius = visibleMask.cornerRadius
        var frame = panel.frame
        frame.origin.y = frame.maxY - height
        frame.size.height = height
        panel.setFrame(frame, display: true)
        contentHost.frame = containerView.bounds

        let finalFrame = containerView.bounds
        revealMask.removeAllAnimations()
        if wasOpening && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            addResizeSpring(keyPath: "bounds", from: visibleBounds, to: CGRect(origin: .zero, size: finalFrame.size))
            addResizeSpring(keyPath: "position", from: visiblePosition, to: CGPoint(x: finalFrame.midX, y: finalFrame.midY))
            addResizeSpring(keyPath: "cornerRadius", from: visibleCornerRadius, to: 18)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        revealMask.frame = finalFrame
        revealMask.cornerRadius = 18
        CATransaction.commit()
    }

    private func addResizeSpring(keyPath: String, from: Any, to: Any) {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.mass = 1
        animation.stiffness = 360
        animation.damping = 32
        animation.initialVelocity = 0
        animation.duration = 0.32
        revealMask.add(animation, forKey: "morph-open-\(keyPath)")
    }
}
