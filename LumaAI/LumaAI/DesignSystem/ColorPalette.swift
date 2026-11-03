import SwiftUI

public extension Color {
    // Canvas & Surfaces
    static let lumaCanvas = Color(red: 248/255, green: 248/255, blue: 252/255) // #F8F8FC (Orbix Studio Canvas)
    static let lumaSurface = Color.white
    static let lumaSurfaceElevated = Color(red: 244/255, green: 244/255, blue: 250/255)

    // Text & Content
    static let lumaPrimaryText = Color(red: 25/255, green: 25/255, blue: 29/255) // #19191D
    static let lumaSecondaryText = Color(red: 119/255, green: 119/255, blue: 131/255) // #777783
    static let lumaTertiaryText = Color(red: 168/255, green: 168/255, blue: 178/255)

    // Borders & Dividers
    static let lumaBorder = Color(red: 234/255, green: 234/255, blue: 246/255) // #EAEAFA
    static let lumaBorderSubtle = Color(red: 242/255, green: 242/255, blue: 250/255)

    // Orbix Studio Design Tokens
    static let orbixBackground = Color(red: 248/255, green: 248/255, blue: 252/255) // #F8F8FC
    static let orbixLavender = Color(red: 217/255, green: 217/255, blue: 245/255)   // #D9D9F5
    static let orbixLavenderSoft = Color(red: 236/255, green: 236/255, blue: 251/255)
    static let orbixPurple = Color(red: 135/255, green: 101/255, blue: 245/255)     // #8765F5
    static let orbixPrimaryText = Color(red: 25/255, green: 25/255, blue: 29/255)   // #19191D
    static let orbixSecondaryText = Color(red: 119/255, green: 119/255, blue: 131/255) // #777783
    static let orbixCardBorder = Color(red: 234/255, green: 234/255, blue: 248/255)
    static let orbixBlackPill = Color(red: 22/255, green: 22/255, blue: 26/255)
    static let orbixChipBackground = Color(red: 244/255, green: 244/255, blue: 250/255)

    // Accents
    static let lumaAccent = Color(red: 37/255, green: 99/255, blue: 235/255) // #2563EB
    static let lumaAccentLight = Color(red: 239/255, green: 246/255, blue: 255/255) // #EFF6FF
    static let lumaYellowAccent = Color(red: 255/255, green: 196/255, blue: 61/255) // #FFC43D

    // Status
    static let lumaSuccess = Color(red: 22/255, green: 163/255, blue: 74/255)
    static let lumaError = Color(red: 220/255, green: 38/255, blue: 38/255)
    static let lumaWarning = Color(red: 217/255, green: 119/255, blue: 6/255)

    // Recommended Settings Palette (Harmonized with Orbix Studio)
    static let settingsBackground = Color(red: 248/255, green: 248/255, blue: 252/255) // #F8F8FC
    static let settingsCard = Color.white // #FFFFFF
    static let settingsPrimaryText = Color(red: 25/255, green: 25/255, blue: 29/255) // #19191D
    static let settingsSecondaryText = Color(red: 119/255, green: 119/255, blue: 131/255) // #777783
    static let settingsSectionLabel = Color(red: 119/255, green: 119/255, blue: 131/255) // #777783
    static let settingsDivider = Color(red: 234/255, green: 234/255, blue: 248/255) // #EAEAFA

    // Hex Initializer
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let r, g, b: UInt64
        switch clean.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (255, 196, 61)
        }
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }
}
