import SwiftUI

public extension Color {
    // Canvas & Surfaces
    static let lumaCanvas = Color(red: 250/255, green: 249/255, blue: 246/255) // #FAF9F6
    static let lumaSurface = Color.white
    static let lumaSurfaceElevated = Color(red: 245/255, green: 245/255, blue: 244/255) // #F5F5F4

    // Text & Content
    static let lumaPrimaryText = Color(red: 28/255, green: 25/255, blue: 23/255) // #1C1917
    static let lumaSecondaryText = Color(red: 120/255, green: 113/255, blue: 108/255) // #78716C
    static let lumaTertiaryText = Color(red: 168/255, green: 162/255, blue: 158/255) // #A8A29E

    // Borders & Dividers
    static let lumaBorder = Color(red: 231/255, green: 229/255, blue: 228/255) // #E7E5E4
    static let lumaBorderSubtle = Color(red: 245/255, green: 245/255, blue: 244/255)

    // Accents
    static let lumaAccent = Color(red: 37/255, green: 99/255, blue: 235/255) // #2563EB
    static let lumaAccentLight = Color(red: 239/255, green: 246/255, blue: 255/255) // #EFF6FF
    static let lumaYellowAccent = Color(red: 255/255, green: 196/255, blue: 61/255) // #FFC43D

    // Status
    static let lumaSuccess = Color(red: 22/255, green: 163/255, blue: 74/255)
    static let lumaError = Color(red: 220/255, green: 38/255, blue: 38/255)
    static let lumaWarning = Color(red: 217/255, green: 119/255, blue: 6/255)
}
