import SwiftUI

import SwiftUI
import UIKit

public extension Color {
    /// Creates an adaptive dynamic color that responds immediately to system appearance changes (Light / Dark).
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }

    // MARK: - Canvas & Surfaces (Clean Dark Theme)
    // Light: Soft crisp canvas (#F8F8FC), pure white cards
    // Dark: Deep charcoal / near-black canvas (#121214), subtly lighter charcoal cards (#1C1C20)
    static let lumaCanvas = adaptive(
        light: Color(red: 248/255, green: 248/255, blue: 252/255), // #F8F8FC
        dark: Color(red: 18/255, green: 18/255, blue: 20/255)       // #121214 (deep charcoal)
    )

    static let lumaSurface = adaptive(
        light: Color.white,                                        // #FFFFFF
        dark: Color(red: 28/255, green: 28/255, blue: 32/255)      // #1C1C20 (subtly lighter charcoal)
    )

    static let lumaSurfaceElevated = adaptive(
        light: Color(red: 244/255, green: 244/255, blue: 250/255), // #F4F4FA
        dark: Color(red: 37/255, green: 37/255, blue: 42/255)       // #25252A (elevated charcoal)
    )

    // MARK: - Text & Content
    static let lumaPrimaryText = adaptive(
        light: Color(red: 25/255, green: 25/255, blue: 29/255),     // #19191D
        dark: Color(red: 245/255, green: 245/255, blue: 247/255)    // #F5F5F7 (clean white)
    )

    static let lumaSecondaryText = adaptive(
        light: Color(red: 119/255, green: 119/255, blue: 131/255), // #777783
        dark: Color(red: 158/255, green: 158/255, blue: 167/255)   // #9E9EA7 (muted grey)
    )

    static let lumaTertiaryText = adaptive(
        light: Color(red: 168/255, green: 168/255, blue: 178/255), // #A8A8B2
        dark: Color(red: 110/255, green: 110/255, blue: 119/255)   // #6E6E77
    )

    static let lumaInversePrimaryText = adaptive(
        light: Color.white,
        dark: Color(red: 18/255, green: 18/255, blue: 20/255)
    )

    // MARK: - Borders & Dividers
    static let lumaBorder = adaptive(
        light: Color(red: 234/255, green: 234/255, blue: 246/255), // #EAEAFA
        dark: Color(red: 46/255, green: 46/255, blue: 54/255)       // #2E2E36 (subtle dark grey)
    )

    static let lumaBorderSubtle = adaptive(
        light: Color(red: 242/255, green: 242/255, blue: 250/255), // #F2F2FA
        dark: Color(red: 36/255, green: 36/255, blue: 42/255)       // #24242A
    )

    // MARK: - Orbix Studio Design Tokens
    static let orbixBackground = lumaCanvas
    static let orbixPrimaryText = lumaPrimaryText
    static let orbixSecondaryText = lumaSecondaryText
    static let orbixCardBorder = lumaBorder
    static let orbixChipBackground = lumaSurfaceElevated

    static let orbixLavender = adaptive(
        light: Color(red: 217/255, green: 217/255, blue: 245/255), // #D9D9F5
        dark: Color(red: 36/255, green: 34/255, blue: 50/255)       // #242232 (muted deep dark indigo)
    )

    static let orbixLavenderSoft = adaptive(
        light: Color(red: 236/255, green: 236/255, blue: 251/255), // #ECECFB
        dark: Color(red: 27/255, green: 25/255, blue: 36/255)       // #1B1924
    )

    static let orbixPurple = adaptive(
        light: Color(red: 135/255, green: 101/255, blue: 245/255), // #8765F5
        dark: Color(red: 157/255, green: 126/255, blue: 250/255)   // #9D7EFA
    )

    static let orbixBlackPill = adaptive(
        light: Color(red: 22/255, green: 22/255, blue: 26/255),     // #16161A (black pill)
        dark: Color(red: 46/255, green: 46/255, blue: 54/255)       // #2E2E36 (elevated charcoal pill)
    )

    // MARK: - Accents & Signature Gold
    static let lumaAccent = adaptive(
        light: Color(red: 37/255, green: 99/255, blue: 235/255),   // #2563EB
        dark: Color(red: 59/255, green: 130/255, blue: 246/255)    // #3B82F6
    )

    static let lumaAccentLight = adaptive(
        light: Color(red: 239/255, green: 246/255, blue: 255/255), // #EFF6FF
        dark: Color(red: 30/255, green: 41/255, blue: 59/255)      // #1E293B
    )

    // Signature Luma Gold Accent (retained across both appearances for high contrast & brand identity)
    static let lumaGold = Color(red: 255/255, green: 196/255, blue: 61/255) // #FFC43D
    static let lumaYellowAccent = lumaGold

    // MARK: - Status
    static let lumaSuccess = adaptive(
        light: Color(red: 22/255, green: 163/255, blue: 74/255),
        dark: Color(red: 34/255, green: 197/255, blue: 94/255)
    )

    static let lumaError = adaptive(
        light: Color(red: 220/255, green: 38/255, blue: 38/255),
        dark: Color(red: 239/255, green: 68/255, blue: 68/255)
    )

    static let lumaWarning = adaptive(
        light: Color(red: 217/255, green: 119/255, blue: 6/255),
        dark: Color(red: 245/255, green: 158/255, blue: 11/255)
    )

    // MARK: - Settings Palette
    static let settingsBackground = lumaCanvas
    static let settingsCard = lumaSurface
    static let settingsPrimaryText = lumaPrimaryText
    static let settingsSecondaryText = lumaSecondaryText
    static let settingsSectionLabel = lumaSecondaryText
    static let settingsDivider = lumaBorder

    // MARK: - Hex Initializer
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
