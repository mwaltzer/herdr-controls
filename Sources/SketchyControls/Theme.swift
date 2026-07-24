import SwiftUI

enum SpaceTheme {
    static let base = Color(hex: 0x1e1e2e)
    static let mantle = Color(hex: 0x181825)
    static let surface = Color(hex: 0x313244)
    static let overlay = Color(hex: 0x6c7086)
    static let text = Color(hex: 0xcdd6f4)
    static let subtext = Color(hex: 0xa6adc8)
    static let mauve = Color(hex: 0xcba6f7)
    static let peach = Color(hex: 0xfab387)
    static let green = Color(hex: 0xa6e3a1)
    static let yellow = Color(hex: 0xf9e2af)
    static let red = Color(hex: 0xf38ba8)
    static let blue = Color(hex: 0x89b4fa)
    static let sapphire = Color(hex: 0x74c7ec)
    static let teal = Color(hex: 0x94e2d5)
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
