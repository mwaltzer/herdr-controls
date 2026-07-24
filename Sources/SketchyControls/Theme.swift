import AppKit
import SwiftUI

enum SpaceTheme {
    private static let catppuccinMocha =
        ProcessInfo.processInfo.environment["HERDR_CONTROLS_THEME"]?.lowercased() == "catppuccin-mocha"

    static let preferredColorScheme: ColorScheme? = catppuccinMocha ? .dark : nil

    static let base = catppuccinMocha ? Color(hex: 0x1e1e2e) : Color(nsColor: .windowBackgroundColor)
    static let mantle = catppuccinMocha ? Color(hex: 0x181825) : Color(nsColor: .underPageBackgroundColor)
    static let surface = catppuccinMocha ? Color(hex: 0x313244) : Color(nsColor: .controlBackgroundColor)
    static let overlay = catppuccinMocha ? Color(hex: 0x6c7086) : Color(nsColor: .tertiaryLabelColor)
    static let text = catppuccinMocha ? Color(hex: 0xcdd6f4) : Color(nsColor: .labelColor)
    static let subtext = catppuccinMocha ? Color(hex: 0xa6adc8) : Color(nsColor: .secondaryLabelColor)
    static let mauve = catppuccinMocha ? Color(hex: 0xcba6f7) : Color(nsColor: .systemPurple)
    static let peach = catppuccinMocha ? Color(hex: 0xfab387) : Color(nsColor: .systemOrange)
    static let green = catppuccinMocha ? Color(hex: 0xa6e3a1) : Color(nsColor: .systemGreen)
    static let yellow = catppuccinMocha ? Color(hex: 0xf9e2af) : Color(nsColor: .systemYellow)
    static let red = catppuccinMocha ? Color(hex: 0xf38ba8) : Color(nsColor: .systemRed)
    static let blue = catppuccinMocha ? Color(hex: 0x89b4fa) : Color(nsColor: .systemBlue)
    static let sapphire = catppuccinMocha ? Color(hex: 0x74c7ec) : Color(nsColor: .systemCyan)
    static let teal = catppuccinMocha ? Color(hex: 0x94e2d5) : Color(nsColor: .systemTeal)

    static let panelTint = base.opacity(catppuccinMocha ? 0.96 : 0.42)
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}
