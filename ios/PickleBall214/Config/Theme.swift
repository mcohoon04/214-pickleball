import SwiftUI

enum Theme {
    static let background = Color.black
    static let surface = Color(white: 0.12)
    static let surfaceLight = Color(white: 0.18)
    static let accent = Color(red: 0.478, green: 0.757, blue: 0.263) // #7AC143
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.6)
    static let textOnAccent = Color.black
    static let destructive = Color.red
    static let disabled = Color(white: 0.3)

    static let cornerRadius: CGFloat = 12
    static let padding: CGFloat = 16
}
