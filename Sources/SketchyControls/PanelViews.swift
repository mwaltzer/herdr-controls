import AppKit
import HerdrCore
import SketchyControlsCore
import SwiftUI

struct PanelRootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PanelChrome(title: model.panel.title, showsAllControls: model.panel != .controlCenter && model.panel != .session && model.panel != .herdr) {
            Group {
                switch model.panel {
                case .controlCenter: ControlCenterView(model: model)
                case .audio: AudioView(model: model)
                case .network: NetworkView(model: model)
                case .power: PowerView(model: model)
                case .focusDisplay: FocusDisplayView(model: model)
                case .calendar: AgendaView(model: model)
                case .performance: PerformanceView(model: model)
                case .herdr: HerdrView(model: model)
                case .session: SessionView(model: model)
                }
            }
        } allControls: {
            model.open(.controlCenter)
        }
        .preferredColorScheme(.dark)
        .frame(width: model.panel == .controlCenter ? 440 : model.panel == .herdr ? 400 : 360)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct PanelChrome<Content: View>: View {
    let title: String
    let showsAllControls: Bool
    @ViewBuilder let content: Content
    let allControls: () -> Void

    init(title: String, showsAllControls: Bool, @ViewBuilder content: () -> Content, allControls: @escaping () -> Void) {
        self.title = title
        self.showsAllControls = showsAllControls
        self.content = content()
        self.allControls = allControls
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if title == PanelKind.herdr.title {
                HerdrBrandTitle()
            } else {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SpaceTheme.text)
            }

            content

            if showsAllControls {
                Divider().overlay(SpaceTheme.text.opacity(0.08))
                Button("All Controls", systemImage: "slider.horizontal.3", action: allControls)
                    .buttonStyle(QuietButtonStyle())
            }
        }
        .padding(18)
        .background(VisualEffect(material: .popover, blendingMode: .behindWindow))
        .background(SpaceTheme.base.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SpaceTheme.text.opacity(0.10), lineWidth: 1)
        }
    }
}

private struct HerdrBrandTitle: View {
    private let logo: NSImage? = {
        guard let url = Bundle.main.url(forResource: "herdr-mask", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        HStack(spacing: 9) {
            Group {
                if let logo {
                    Image(nsImage: logo)
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(SpaceTheme.text)
                        .padding(2)
                }
            }
            .frame(width: 32, height: 32)
            .background(SpaceTheme.mantle)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(SpaceTheme.text.opacity(0.14), lineWidth: 1)
            }

            Text("herdr")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .tracking(-0.7)
                .foregroundStyle(SpaceTheme.text)

            Spacer()

            HerdrSettingsButton {
                SettingsWindowController.shared.show()
            }
            .frame(width: 32, height: 32)
        }
    }
}

private struct HerdrSettingsButton: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let image = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: "Herdr settings"
        ) ?? NSImage()
        let button = HerdrSettingsNSButton(
            image: image,
            target: context.coordinator,
            action: #selector(Coordinator.invoke)
        )
        button.controlSize = .regular
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        button.contentTintColor = NSColor(
            calibratedRed: 166 / 255,
            green: 173 / 255,
            blue: 200 / 255,
            alpha: 1
        )
        button.toolTip = "Herdr Settings"
        button.setAccessibilityLabel("Herdr settings")
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func invoke() {
            action()
        }
    }
}

private final class HerdrSettingsNSButton: NSButton {
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 1
        updateAppearance(hovered: false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        updateAppearance(hovered: true)
    }

    override func mouseExited(with event: NSEvent) {
        updateAppearance(hovered: false)
    }

    private func updateAppearance(hovered: Bool) {
        layer?.backgroundColor = hovered
            ? NSColor(calibratedRed: 49 / 255, green: 50 / 255, blue: 68 / 255, alpha: 0.72).cgColor
            : NSColor.clear.cgColor
        layer?.borderColor = NSColor(
            calibratedRed: 205 / 255,
            green: 214 / 255,
            blue: 244 / 255,
            alpha: hovered ? 0.18 : 0.10
        ).cgColor
        contentTintColor = NSColor(
            calibratedRed: hovered ? 205 / 255 : 166 / 255,
            green: hovered ? 214 / 255 : 173 / 255,
            blue: hovered ? 244 / 255 : 200 / 255,
            alpha: 1
        )
    }
}

struct ControlCenterView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 1) {
            NavigationRow(icon: "speaker.wave.2.fill", color: SpaceTheme.teal, title: "Sound", detail: "\(Int(model.audio.volume))%") { model.open(.audio) }
            NavigationRow(icon: "wifi", color: SpaceTheme.sapphire, title: "Wi-Fi", detail: model.network.ssid) { model.open(.network) }
            NavigationRow(icon: model.power.charging ? "bolt.fill" : "battery.75percent", color: SpaceTheme.green, title: "Power", detail: "\(model.power.percent)%") { model.open(.power) }
            NavigationRow(icon: "moon.fill", color: SpaceTheme.mauve, title: "Focus & Display", detail: "System controls") { model.open(.focusDisplay) }
            NavigationRow(icon: "calendar", color: SpaceTheme.peach, title: "Agenda", detail: "Upcoming events") { model.open(.calendar) }
            NavigationRow(icon: "gauge.with.dots.needle.67percent", color: SpaceTheme.yellow, title: "Performance", detail: "CPU and memory") { model.open(.performance) }
            NavigationRow(icon: "rectangle.3.group.bubble.left.fill", color: SpaceTheme.blue, title: "Herdr", detail: "Agents and workspaces") { model.open(.herdr) }
            NavigationRow(icon: "gearshape.fill", color: SpaceTheme.overlay, title: "Settings", detail: "Shortcuts and sessions") {
                model.dismiss()
                SettingsWindowController.shared.show()
            }
            if model.isWork {
                StatusRow(title: "Futurex VPN", value: model.vpn.label, color: model.vpn.healthy ? SpaceTheme.green : SpaceTheme.yellow)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct AudioView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: model.audio.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(model.audio.muted ? SpaceTheme.overlay : SpaceTheme.teal)
                    .frame(width: 18)
                Slider(value: Binding(
                    get: { model.audio.volume },
                    set: { value in
                        model.audio.volume = value
                        AudioService.setVolume(value)
                    }
                ), in: 0...100)
                .tint(SpaceTheme.teal)
                Text("\(Int(model.audio.volume))")
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(SpaceTheme.subtext)
                    .frame(width: 30, alignment: .trailing)
            }

            Button(model.audio.muted ? "Unmute" : "Mute", systemImage: model.audio.muted ? "speaker.wave.2" : "speaker.slash") {
                model.audio.muted.toggle()
                AudioService.setMuted(model.audio.muted)
            }
            .buttonStyle(QuietButtonStyle())

            if !model.audio.outputs.isEmpty {
                SectionLabel("Output")
                VStack(spacing: 1) {
                    ForEach(model.audio.outputs) { device in
                        SelectionRow(title: device.name, selected: device.id == model.audio.defaultOutputID) {
                            AudioService.setDefaultOutput(device.id)
                            model.refresh(.audio)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

struct NetworkView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: model.network.connected ? "wifi" : "wifi.slash")
                    .foregroundStyle(model.network.connected ? SpaceTheme.sapphire : SpaceTheme.overlay)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.network.ssid).font(.system(size: 14, weight: .medium)).foregroundStyle(SpaceTheme.text).lineLimit(1)
                    Text(model.network.address.isEmpty ? "No IP address" : model.network.address).font(.system(size: 12)).foregroundStyle(SpaceTheme.subtext)
                }
                Spacer()
                Toggle("Wi-Fi", isOn: Binding(
                    get: { model.network.powered },
                    set: { value in
                        model.network.powered = value
                        NetworkService.setPower(value)
                        model.refresh(.network)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(SpaceTheme.sapphire)
            }
            Button("Network Settings", systemImage: "gearshape") {
                model.openURL("x-apple.systempreferences:com.apple.wifi-settings-extension")
            }
            .buttonStyle(QuietButtonStyle())
        }
    }
}

struct PowerView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(model.power.percent)%")
                    .font(.system(size: 36, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(SpaceTheme.text)
                Spacer()
                Label(model.power.source, systemImage: model.power.charging ? "bolt.fill" : "battery.75percent")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(model.power.charging ? SpaceTheme.green : SpaceTheme.subtext)
            }
            if !model.power.detail.isEmpty {
                Text(model.power.detail).font(.system(size: 13)).foregroundStyle(SpaceTheme.subtext).frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Battery Settings", systemImage: "gearshape") {
                model.openURL("x-apple.systempreferences:com.apple.preference.battery")
            }
            .buttonStyle(QuietButtonStyle())
        }
    }
}

struct FocusDisplayView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 1) {
            NavigationRow(icon: "moon.fill", color: SpaceTheme.mauve, title: "Focus", detail: "Manage modes") {
                model.openURL("x-apple.systempreferences:com.apple.Focus-Settings.extension")
            }
            NavigationRow(icon: "display", color: SpaceTheme.blue, title: "Displays", detail: "Brightness and arrangement") {
                model.openURL("x-apple.systempreferences:com.apple.Displays-Settings.extension")
            }
            Text("Alcove remains the glance layer for Focus and brightness changes.")
                .font(.system(size: 12))
                .foregroundStyle(SpaceTheme.subtext)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AgendaView: View {
    @ObservedObject var model: AppModel
    private let formatter: DateFormatter = {
        let value = DateFormatter()
        value.dateFormat = "EEE · h:mm a"
        return value
    }()

    var body: some View {
        VStack(spacing: 1) {
            if !model.calendarAuthorized {
                EmptyState(icon: "calendar.badge.exclamationmark", title: "Calendar access needed", detail: "Allow access in Privacy & Security to show your agenda.")
            } else if model.events.isEmpty {
                EmptyState(icon: "calendar", title: "Nothing upcoming", detail: "Your next two days are clear.")
            } else {
                ForEach(model.events) { event in
                    Button {
                        if let url = event.url { NSWorkspace.shared.open(url) } else { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Calendar.app"), configuration: .init()) }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(Color(nsColor: event.color)).frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.title).font(.system(size: 13, weight: .medium)).foregroundStyle(SpaceTheme.text).lineLimit(1)
                                Text(formatter.string(from: event.start)).font(.system(size: 12)).foregroundStyle(SpaceTheme.subtext)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(SpaceTheme.overlay)
                        }
                        .padding(10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(SpaceTheme.surface.opacity(0.38))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct PerformanceView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            MetricRow(label: "CPU", value: model.performance.cpu)
            Divider().overlay(SpaceTheme.text.opacity(0.08))
            MetricRow(label: "Memory", value: model.performance.memory)
            Divider().overlay(SpaceTheme.text.opacity(0.08))
            MetricRow(label: "Swap", value: model.performance.swap)
            Button("Open Activity Monitor", systemImage: "waveform.path.ecg") {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"), configuration: .init())
            }
            .buttonStyle(QuietButtonStyle())
            .padding(.top, 12)
        }
    }
}

struct HerdrView: View {
    @ObservedObject var model: AppModel

    private var localAgentCount: Int { model.herdr.agents.count }
    private var remoteAgentCount: Int { model.herdr.remoteHosts.reduce(0) { $0 + $1.agents.count } }
    private var visibleSelectionKeys: [String] {
        switch (model.herdrLocation, model.herdrTargetKind) {
        case (.local, .containers):
            model.herdr.workspaces.map { "workspace:\($0.id)" }
        case (.local, .agents):
            model.herdr.agents.map { "agent:\($0.id)" }
        case (.tailnet, .containers):
            model.herdr.remoteHosts.map { "host:\($0.host)" }
        case (.tailnet, .agents):
            model.herdr.remoteHosts.flatMap { host in
                host.agents.map { "remote:\(host.host):\($0.id)" }
            }
        }
    }

    private func scrollDestination(for key: String) -> (id: String, anchor: UnitPoint) {
        guard let index = visibleSelectionKeys.firstIndex(of: key) else { return (key, .center) }
        if index == 0 { return (key, .top) }

        if model.herdrLocation == .local,
           model.herdrTargetKind == .containers,
           let workspace = model.herdr.workspaces.first(where: { "workspace:\($0.id)" == key }),
           let lastAgent = model.herdr.agents.last(where: { $0.workspaceID == workspace.id }) {
            return ("agent:\(lastAgent.id)", .bottom)
        }

        if model.herdrLocation == .tailnet,
           model.herdrTargetKind == .containers,
           let host = model.herdr.remoteHosts.first(where: { "host:\($0.host)" == key }),
           let lastAgent = host.agents.last {
            return ("remote:\(host.host):\(lastAgent.id)", .bottom)
        }

        return (key, index == visibleSelectionKeys.count - 1 ? .bottom : .center)
    }

    var body: some View {
        VStack(spacing: 10) {
            HerdrNavigationPicker(
                model: model,
                workspaces: model.herdr.workspaces.count,
                agents: localAgentCount,
                hosts: model.herdr.remoteHosts.count,
                remoteAgents: remoteAgentCount
            )

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 14) {
                        if let issue = model.herdrIssue {
                            HerdrIssueView(model: model, issue: issue)
                        } else {
                            if model.herdrLocation == .local, !model.herdr.workspaces.isEmpty {
                                VStack(spacing: 2) {
                                    ForEach(model.herdr.workspaces) { workspace in
                                        let agents = model.herdr.agents.filter { $0.workspaceID == workspace.id }
                                        VStack(spacing: 0) {
                                            Button {
                                                HerdrService.focusWorkspace(workspace.id)
                                                model.refresh(.herdr)
                                            } label: {
                                                HStack(spacing: 10) {
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(workspace.label)
                                                            .font(.system(size: 13, weight: .medium))
                                                            .foregroundStyle(SpaceTheme.text)
                                                            .lineLimit(1)
                                                        Text(agents.isEmpty ? "No attached agents" : "\(agents.count) attached \(agents.count == 1 ? "agent" : "agents")")
                                                            .font(.system(size: 10))
                                                            .foregroundStyle(SpaceTheme.overlay)
                                                    }

                                                    Spacer(minLength: 8)
                                                    if workspace.focused {
                                                        HerdrMetaBadge("Current", color: SpaceTheme.sapphire)
                                                    }
                                                    HerdrStatusBadge(status: workspace.agentStatus)
                                                }
                                                .padding(.horizontal, 10)
                                                .frame(minHeight: 48)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(HerdrInteractiveButtonStyle())
                                            .focusable(false)
                                            .accessibilityLabel("Workspace \(workspace.label)")
                                            .accessibilityValue(
                                                "\(agents.count) attached \(agents.count == 1 ? "agent" : "agents"), \(workspace.agentStatus)\(workspace.focused ? ", current" : "")"
                                            )
                                            .accessibilityHint("Focuses this workspace")

                                            ForEach(agents) { agent in
                                                Button {
                                                    HerdrService.focusAgent(agent.id)
                                                    model.refresh(.herdr)
                                                } label: {
                                                    HerdrAgentRow(
                                                        title: agent.terminalTitleStripped,
                                                        agent: agent.agent,
                                                        status: agent.agentStatus,
                                                        focused: agent.focused,
                                                        remote: false,
                                                        selected: model.isHerdrSelected("agent:\(agent.id)")
                                                    )
                                                }
                                                .buttonStyle(HerdrInteractiveButtonStyle())
                                                .focusable(false)
                                                .herdrSelection(
                                                    model.isHerdrSelected("agent:\(agent.id)"),
                                                    cornerRadius: 6,
                                                    accentInset: 6
                                                )
                                                .padding(.horizontal, 4)
                                                .id("agent:\(agent.id)")
                                            }
                                        }
                                        .herdrSelection(
                                            model.isHerdrSelected("workspace:\(workspace.id)"),
                                            cornerRadius: 7,
                                            accentInset: 9
                                        )
                                        .padding(.horizontal, 4)
                                        .id("workspace:\(workspace.id)")
                                    }
                                }
                            }

                            if model.herdrLocation == .tailnet, !model.herdr.remoteHosts.isEmpty {
                                VStack(spacing: 2) {
                                    ForEach(model.herdr.remoteHosts) { remote in
                                        VStack(spacing: 0) {
                                            Button {
                                                guard let firstAgent = remote.agents.first else { return }
                                                HerdrService.openRemote(host: remote.host, paneID: firstAgent.id)
                                                model.dismiss()
                                            } label: {
                                              HStack(spacing: 10) {
                                                Image(systemName: "desktopcomputer")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundStyle(SpaceTheme.sapphire)
                                                    .frame(width: 20)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(remote.host)
                                                        .font(.system(size: 13, weight: .medium))
                                                        .foregroundStyle(SpaceTheme.text)
                                                        .lineLimit(1)
                                                    Text("\(remote.agents.count) available \(remote.agents.count == 1 ? "agent" : "agents")")
                                                        .font(.system(size: 10))
                                                        .foregroundStyle(SpaceTheme.overlay)
                                                }
                                                Spacer()
                                                HerdrMetaBadge("SSH", color: SpaceTheme.teal)
                                              }
                                              .padding(.horizontal, 10)
                                              .frame(minHeight: 48)
                                              .contentShape(Rectangle())
                                            }
                                            .buttonStyle(HerdrInteractiveButtonStyle())
                                            .focusable(false)
                                            .disabled(remote.agents.isEmpty)
                                            .accessibilityLabel("Tailnet host \(remote.host)")
                                            .accessibilityValue(
                                                "\(remote.agents.count) available \(remote.agents.count == 1 ? "agent" : "agents")"
                                            )
                                            .accessibilityHint(
                                                remote.agents.isEmpty ? "No agents are available" : "Opens the first available agent over SSH"
                                            )

                                            ForEach(remote.agents) { agent in
                                                Button {
                                                    HerdrService.openRemote(host: remote.host, paneID: agent.id)
                                                    model.dismiss()
                                                } label: {
                                                    HerdrAgentRow(
                                                        title: agent.terminalTitleStripped,
                                                        agent: agent.agent,
                                                        status: agent.agentStatus,
                                                        focused: false,
                                                        remote: true,
                                                        selected: model.isHerdrSelected("remote:\(remote.host):\(agent.id)")
                                                    )
                                                }
                                                .buttonStyle(HerdrInteractiveButtonStyle())
                                                .focusable(false)
                                                .herdrSelection(
                                                    model.isHerdrSelected("remote:\(remote.host):\(agent.id)"),
                                                    cornerRadius: 6,
                                                    accentInset: 6
                                                )
                                                .padding(.horizontal, 4)
                                                .id("remote:\(remote.host):\(agent.id)")
                                            }
                                        }
                                        .herdrSelection(
                                            model.isHerdrSelected("host:\(remote.host)"),
                                            cornerRadius: 7,
                                            accentInset: 9
                                        )
                                        .padding(.horizontal, 4)
                                        .id("host:\(remote.host)")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.trailing, 14)
                    .padding(.bottom, 10)
                }
                .frame(maxHeight: 514, alignment: .top)
                .scrollIndicators(.visible)
                .onChange(of: model.selectedHerdrKey) { _, key in
                    guard let key else { return }
                    let destination = scrollDestination(for: key)
                    proxy.scrollTo(destination.id, anchor: destination.anchor)
                }
            }

            HerdrKeyboardLegend()
        }
    }
}

private struct HerdrNavigationPicker: View {
    @ObservedObject var model: AppModel
    let workspaces: Int
    let agents: Int
    let hosts: Int
    let remoteAgents: Int

    private var tailscaleImage: NSImage? {
        guard let url = Bundle.main.url(forResource: "tailscale-icon", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 3) {
                locationButton(.local, label: "This Mac", count: workspaces)
                locationButton(.tailnet, label: "Tailnet", count: hosts)
            }
            .padding(4)
            .background(SpaceTheme.surface.opacity(0.24))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            HStack(spacing: 3) {
                kindButton(.containers, key: "H", label: model.herdrLocation == .local ? "Workspaces" : "Hosts", count: model.herdrLocation == .local ? workspaces : hosts)
                kindButton(.agents, key: "L", label: "Agents", count: model.herdrLocation == .local ? agents : remoteAgents)
            }
        }
    }

    private func locationButton(_ location: HerdrLocation, label: String, count: Int) -> some View {
        let selected = model.herdrLocation == location
        return Button {
            model.setHerdrLocation(location)
        } label: {
            HStack(spacing: 7) {
                if location == .local {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 13, weight: .medium))
                } else if let tailscaleImage {
                    Image(nsImage: tailscaleImage)
                        .resizable()
                        .renderingMode(.template)
                        .frame(width: 14, height: 14)
                }
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? SpaceTheme.text : SpaceTheme.subtext)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(selected ? SpaceTheme.text : SpaceTheme.overlay)
            }
            .foregroundStyle(selected ? SpaceTheme.sapphire : SpaceTheme.overlay)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(HerdrInteractiveButtonStyle())
        .focusable(false)
        .background(selected ? SpaceTheme.surface.opacity(0.72) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private func kindButton(_ kind: HerdrTargetKind, key: String, label: String, count: Int) -> some View {
        let selected = model.herdrTargetKind == kind
        return Button {
            model.setHerdrTargetKind(kind)
        } label: {
            HStack(spacing: 7) {
                Text(key)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(selected ? SpaceTheme.sapphire : SpaceTheme.overlay)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selected ? SpaceTheme.text : SpaceTheme.subtext)
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(selected ? SpaceTheme.text : SpaceTheme.overlay)
                Spacer()
            }
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity, minHeight: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(HerdrInteractiveButtonStyle())
        .focusable(false)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .overlay(alignment: .bottom) {
            Capsule()
                .fill(selected ? SpaceTheme.sapphire.opacity(0.75) : .clear)
                .frame(height: 2)
                .padding(.horizontal, 5)
        }
    }
}

private struct HerdrAgentRow: View {
    let title: String
    let agent: String
    let status: String
    let focused: Bool
    let remote: Bool
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: remote ? "arrow.up.right" : "arrow.turn.down.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(selected || remote ? SpaceTheme.sapphire : SpaceTheme.overlay)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(selected ? SpaceTheme.text : SpaceTheme.subtext)
                .lineLimit(1)
            Spacer(minLength: 8)
            if focused {
                Image(systemName: "viewfinder")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(SpaceTheme.sapphire)
            }
            Text(agent)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(SpaceTheme.overlay)
                .lineLimit(1)
            HerdrStatusBadge(status: status, compact: true)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(remote ? "Remote" : "Local") \(agent) agent, \(title)")
        .accessibilityValue("\(status.isEmpty ? "unknown" : status)\(focused ? ", focused" : "")")
    }
}

private struct HerdrInteractiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .onHover { hovering in
                (hovering ? NSCursor.pointingHand : NSCursor.arrow).set()
            }
    }
}

private struct HerdrSelectionModifier: ViewModifier {
    let selected: Bool
    let cornerRadius: CGFloat
    let accentInset: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(selected ? SpaceTheme.sapphire.opacity(0.13) : .clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                selected ? SpaceTheme.sapphire.opacity(0.58) : .clear,
                                lineWidth: 1
                            )
                    }
            }
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(selected ? SpaceTheme.sapphire : .clear)
                    .frame(width: 3)
                    .padding(.vertical, accentInset)
                    .padding(.leading, 2)
            }
    }
}

private extension View {
    func herdrSelection(
        _ selected: Bool,
        cornerRadius: CGFloat,
        accentInset: CGFloat
    ) -> some View {
        modifier(
            HerdrSelectionModifier(
                selected: selected,
                cornerRadius: cornerRadius,
                accentInset: accentInset
            )
        )
    }
}

private struct HerdrMetaBadge: View {
    let value: String
    let color: Color

    init(_ value: String, color: Color) {
        self.value = value
        self.color = color
    }

    var body: some View {
        Text(value)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
    }
}

private struct HerdrStatusBadge: View {
    let status: String
    var compact = false

    private var color: Color {
        switch status {
        case "working": SpaceTheme.yellow
        case "done": SpaceTheme.green
        case "idle": SpaceTheme.blue
        case "blocked": SpaceTheme.red
        default: SpaceTheme.overlay
        }
    }

    private var label: String {
        status.isEmpty ? "unknown" : status
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            if !compact {
                Text(label.capitalized)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(SpaceTheme.subtext)
            }
        }
        .padding(.horizontal, compact ? 2 : 0)
        .frame(height: 18)
        .accessibilityLabel(label)
    }
}

private struct HerdrKeyboardLegend: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                legend(keys: "J K", action: "Move")
                Spacer()
                legend(keys: "Tab", action: "Location")
                Spacer()
                legend(keys: "H L", action: "Type")
            }

            HStack {
                legend(keys: "↩", action: "Open")
                Spacer()
                legend(keys: "Esc", action: "Close")
            }
        }
        .padding(.horizontal, 2)
    }

    private func legend(keys: String, action: String) -> some View {
        HStack(spacing: 5) {
            Text(keys)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(SpaceTheme.subtext)
                .lineLimit(1)
                .padding(.horizontal, 5)
                .frame(height: 18)
                .background(SpaceTheme.surface.opacity(0.48), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(action)
                .font(.system(size: 9))
                .foregroundStyle(SpaceTheme.overlay)
                .lineLimit(1)
        }
        .fixedSize()
    }
}

struct SessionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 1) {
            SessionRow(icon: "wand.and.stars", title: "Rotate wallpaper", color: SpaceTheme.mauve) { run("\(NSHomeDirectory())/.local/bin/catppuccin-space-wallpaper", []) }
            SessionRow(icon: "lock.fill", title: "Lock Screen", color: SpaceTheme.blue) { model.openURL("raycast://extensions/raycast/system/lock-screen") }
            SessionRow(icon: "moon.zzz.fill", title: "Sleep", color: SpaceTheme.sapphire) { model.openURL("raycast://extensions/raycast/system/sleep") }
            SessionRow(icon: "arrow.clockwise", title: "Restart", color: SpaceTheme.yellow) { model.sessionConfirmation = .restart }
            SessionRow(icon: "power", title: "Shut Down", color: SpaceTheme.red) { model.sessionConfirmation = .shutdown }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .alert(model.sessionConfirmation?.title ?? "", isPresented: Binding(get: { model.sessionConfirmation != nil }, set: { if !$0 { model.sessionConfirmation = nil } })) {
            Button("Cancel", role: .cancel) { model.sessionConfirmation = nil }
            Button(model.sessionConfirmation?.title ?? "Confirm", role: .destructive) {
                if let confirmation = model.sessionConfirmation { model.openURL(confirmation.url) }
                model.sessionConfirmation = nil
            }
        } message: {
            Text("This affects all open applications and unsaved work.")
        }
    }
}

enum SessionAction: Equatable {
    case restart, shutdown
    var title: String { self == .restart ? "Restart this Mac?" : "Shut down this Mac?" }
    var url: String { self == .restart ? "raycast://extensions/raycast/system/restart" : "raycast://extensions/raycast/system/shut-down" }
}

struct NavigationRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(color).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(SpaceTheme.text)
                    Text(detail).font(.system(size: 11)).foregroundStyle(SpaceTheme.subtext).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(SpaceTheme.overlay)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(SpaceTheme.surface.opacity(0.38))
    }
}

struct SelectionRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 13)).foregroundStyle(SpaceTheme.text).lineLimit(1)
                Spacer()
                if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(SpaceTheme.teal) }
            }
            .padding(9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(SpaceTheme.surface.opacity(selected ? 0.62 : 0.36))
    }
}

struct MetricRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(SpaceTheme.subtext)
            Spacer()
            Text(value).font(.system(size: 13, weight: .medium, design: .monospaced)).monospacedDigit().foregroundStyle(SpaceTheme.text)
        }
        .padding(.vertical, 10)
    }
}

struct StatusRow: View {
    let title: String
    let value: String
    let color: Color
    var body: some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(SpaceTheme.text)
            Spacer()
            Circle().fill(color).frame(width: 7, height: 7)
            Text(value).font(.system(size: 12)).foregroundStyle(SpaceTheme.subtext)
        }
        .padding(10)
        .background(SpaceTheme.surface.opacity(0.38))
    }
}

struct SessionRow: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(color).frame(width: 18)
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(SpaceTheme.text)
                Spacer()
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(SpaceTheme.surface.opacity(0.38))
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(SpaceTheme.overlay)
            Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(SpaceTheme.text)
            Text(detail).font(.system(size: 12)).foregroundStyle(SpaceTheme.subtext).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

/// Cause-specific replacement for the old binary "No Herdr sessions" state:
/// says what is wrong in the current scope and offers the matching action —
/// retry with a live countdown when the local CLI is down, a Settings jump
/// when tailnet discovery is off, plain hints when scopes are merely empty.
struct HerdrIssueView: View {
    @ObservedObject var model: AppModel
    let issue: HerdrPanelIssue

    var body: some View {
        VStack(spacing: 10) {
            switch issue {
            case .loading:
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for sessions…")
                        .font(.system(size: 12))
                        .foregroundStyle(SpaceTheme.subtext)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            case let .localUnavailable(reason):
                EmptyState(icon: "exclamationmark.triangle", title: "Herdr isn't reachable", detail: reason)
                retryControls
            case .noLocalSessions:
                EmptyState(
                    icon: "rectangle.3.group.bubble.left",
                    title: "No local sessions",
                    detail: "Start a Herdr workspace on this Mac to see it here."
                )
            case .noLocalAgents:
                EmptyState(
                    icon: "person.crop.rectangle.stack",
                    title: "No agents on this Mac",
                    detail: "No agents are attached right now. Press H to browse workspaces."
                )
            case .noTailnetAgents:
                EmptyState(
                    icon: "person.crop.rectangle.stack",
                    title: "No tailnet agents",
                    detail: "Your tailnet hosts responded but have no agents attached. Press H to browse hosts."
                )
            case .tailnetDisabled:
                EmptyState(
                    icon: "antenna.radiowaves.left.and.right.slash",
                    title: "Tailnet discovery is off",
                    detail: "Turn it on to see Herdr sessions on your other machines."
                )
                Button("Open Settings…", systemImage: "gearshape") {
                    model.dismiss()
                    SettingsWindowController.shared.show()
                }
                .buttonStyle(QuietButtonStyle())
            case .noTailnetSessions:
                EmptyState(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "No tailnet sessions",
                    detail: "No online tailnet machine is running Herdr right now."
                )
                Button("Check Again", systemImage: "arrow.clockwise") {
                    model.retryHerdrNow()
                }
                .buttonStyle(QuietButtonStyle())
            }
        }
    }

    private var retryControls: some View {
        VStack(spacing: 8) {
            if let nextRetry = model.nextHerdrRetry {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, Int(nextRetry.timeIntervalSince(context.date).rounded(.up)))
                    Text(remaining > 0 ? "Retrying in \(remaining)s…" : "Retrying…")
                        .font(.system(size: 11, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(SpaceTheme.overlay)
                        .accessibilityLabel("Automatic retry")
                        .accessibilityValue(remaining > 0 ? "In \(remaining) seconds" : "Starting")
                }
            } else if case .failed = model.herdrHealth.state {
                Text("Auto-retry paused — still checking every \(Int(HerdrService.preferences.refreshInterval))s.")
                    .font(.system(size: 11))
                    .foregroundStyle(SpaceTheme.overlay)
            }
            Button("Retry Now", systemImage: "arrow.clockwise") {
                model.retryHerdrNow()
            }
            .buttonStyle(QuietButtonStyle())
        }
    }
}

struct SectionLabel: View {
    let value: String
    init(_ value: String) { self.value = value }
    var body: some View { Text(value).font(.system(size: 11, weight: .medium)).foregroundStyle(SpaceTheme.subtext) }
}

private struct HerdrSectionLabel: View {
    let value: String
    let detail: String
    let systemImage: String?
    let asset: String?

    init(_ value: String, detail: String, systemImage: String) {
        self.value = value
        self.detail = detail
        self.systemImage = systemImage
        asset = nil
    }

    init(_ value: String, detail: String, asset: String) {
        self.value = value
        self.detail = detail
        systemImage = nil
        self.asset = asset
    }

    private var assetImage: NSImage? {
        guard let asset,
              let url = Bundle.main.url(forResource: asset, withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
            } else if let assetImage {
                Image(nsImage: assetImage)
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 12, height: 12)
            }
            Text(value)
                .font(.system(size: 11, weight: .medium))
            Spacer()
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(SpaceTheme.overlay)
        }
        .foregroundStyle(SpaceTheme.subtext)
    }
}

struct StatusDot: View {
    let status: String
    var color: Color {
        switch status { case "working": SpaceTheme.yellow; case "done": SpaceTheme.green; case "idle": SpaceTheme.blue; default: SpaceTheme.overlay }
    }
    var body: some View { Circle().fill(color).frame(width: 7, height: 7).accessibilityLabel(status) }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(SpaceTheme.text)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(SpaceTheme.surface.opacity(configuration.isPressed ? 0.72 : 0.48), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

@discardableResult
private func run(_ command: String, _ arguments: [String]) -> String { shell(command, arguments) }
