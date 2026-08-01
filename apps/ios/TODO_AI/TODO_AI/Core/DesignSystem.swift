import CoreText
import SwiftUI

/// Linear "midnight" tokens — see docs/DESIGN.md. The only chromatic action
/// color is acid lime; one use per screen.
enum DS {
    // Surfaces
    static let void = Color(hex: 0x08090A)      // page canvas
    static let carbon = Color(hex: 0x0F1011)    // cards, tab bar
    static let obsidian = Color(hex: 0x161718)  // elevated (user bubbles)
    static let graphite = Color(hex: 0x23252A)  // hairline borders
    static let smoke = Color(hex: 0x383B3F)
    static let hairline = Color(hex: 0x1D1F21)  // the even-fainter divider the frames use

    // Text
    static let ash = Color(hex: 0x62666D)       // faint labels, inactive tabs
    static let fog = Color(hex: 0x8A8F98)       // muted body
    static let mist = Color(hex: 0xD0D6E0)      // body
    static let bone = Color(hex: 0xE5E5E6)      // selected pills, bright text
    static let paper = Color.white

    // Accents
    static let acidLime = Color(hex: 0xE4F222)
    static let coral = Color(hex: 0xEB5757)     // destructive (Sign out)

    // Refinement pass (design v4): quiet depth — gradients, never flat
    static let pageGradient = RadialGradient(
        colors: [Color(hex: 0x0C0D12), Color(hex: 0x08090A)],
        center: UnitPoint(x: 0.5, y: -0.05), startRadius: 0, endRadius: 700)
    static let cardGradient = LinearGradient(
        colors: [Color(hex: 0x121316), Color(hex: 0x0E0F10)],
        startPoint: .top, endPoint: .bottom)
    static let cardStroke = Color(hex: 0x26282C)
    static let bubbleGradient = LinearGradient(
        colors: [Color(hex: 0x1B1C1F), Color(hex: 0x151618)],
        startPoint: .top, endPoint: .bottom)
    static let bubbleStroke = Color(hex: 0x2A2C31)
    static let limeGradient = LinearGradient(
        colors: [Color(hex: 0xEFF65C), Color(hex: 0xE4F222)],
        startPoint: .top, endPoint: .bottom)

    // Category hues (match backend + Google colorIds)
    static let categoryColors: [String: Color] = [
        "deep_work": Color(hex: 0x6366F1),
        "health": Color(hex: 0x27A644),
        "meals": Color(hex: 0x02B8CC),
        "admin": Color(hex: 0x8B5CF6),
        "social": Color(hex: 0xEB5757),
    ]

    /// Names for the palette hues (design 3k).
    static let paletteNames: [UInt32: String] = [
        0x6366F1: "VIOLET", 0x27A644: "GREEN", 0x02B8CC: "TEAL",
        0x8B5CF6: "LAVENDER", 0xEB5757: "CORAL",
    ]
    static let palette: [UInt32] = [0x02B8CC, 0x27A644, 0x6366F1, 0x8B5CF6, 0xEB5757]

    static func categoryHex(_ name: String) -> UInt32 {
        if let data = UserDefaults.standard.data(forKey: "categoryColorOverrides"),
           let dict = try? JSONDecoder().decode([String: UInt32].self, from: data),
           let hex = dict[name] {
            return hex
        }
        return defaultHex[name] ?? 0x383B3F
    }

    static func setCategoryHex(_ name: String, _ hex: UInt32) {
        var dict = (UserDefaults.standard.data(forKey: "categoryColorOverrides")
            .flatMap { try? JSONDecoder().decode([String: UInt32].self, from: $0) }) ?? [:]
        dict[name] = hex
        UserDefaults.standard.set(try? JSONEncoder().encode(dict), forKey: "categoryColorOverrides")
    }

    private static let defaultHex: [String: UInt32] = [
        "deep_work": 0x6366F1, "health": 0x27A644, "meals": 0x02B8CC,
        "admin": 0x8B5CF6, "social": 0xEB5757,
    ]

    // ponytail: UserDefaults read per render; fine at this scale
    static func category(_ name: String?) -> Color {
        guard let name else { return smoke }
        if defaultHex[name] != nil { return Color(hex: categoryHex(name)) }
        if let data = UserDefaults.standard.data(forKey: "categoryColorOverrides"),
           let dict = try? JSONDecoder().decode([String: UInt32].self, from: data),
           let hex = dict[name] {
            return Color(hex: hex)
        }
        // custom categories get a stable hue from their name
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return Color(hex: palette[sum % palette.count])
    }

    // Type — Inter (variable) + JetBrains Mono, registered at runtime
    static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Inter", size: size).weight(weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("JetBrains Mono", size: size).weight(weight)
    }
}

enum Fonts {
    /// Runtime registration — avoids Info.plist surgery entirely.
    static func register() {
        for name in ["Inter", "JetBrainsMono-Regular", "JetBrainsMono-Medium"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
