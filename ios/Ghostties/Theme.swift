import SwiftUI
import UIKit

/// Ghostties design tokens for iOS, carried over from the Mac app's
/// `DESIGN.md` and `ChromeTheme`: the same two layers (chrome behind
/// everything, canvas for the card that holds content), ink, and the 4pt
/// spacing scale. A new colour is a reuse of one of these, never a new token.
enum Theme {
    static let chrome = Color(light: 0xF0E9E6, dark: 0x242424)
    static let canvas = Color(light: 0xFAF7F3, dark: 0x141413)
    /// Solid black in light, the Mac dark text in dark.
    static let ink = Color(light: 0x1A1A1A, dark: 0xF0EFED)
    /// Muted text. Clears 4.5:1 on chrome and canvas.
    static let inkSecondary = Color(light: 0x5E5E5E, dark: 0xA6A6A6)
    static let border = Color(light: 0xE5E5E3, dark: 0x2A2A2A)
    /// Ink at the Mac `.row` step: pressed rows and the user's own bubbles.
    static let rowFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.06) : UIColor(white: 0, alpha: 0.04)
    })
    /// The terminal card's shadow colour.
    static let shadow = Color(light: 0x0F0F0F, dark: 0xFFFFFF)

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    /// The terminal card's continuous corner.
    static let cardRadius: CGFloat = 12
}

/// Type follows the Mac app's centred-modal scale (15 / 13 / 11), as text
/// styles so Dynamic Type still scales it.
extension Font {
    static let ghostTitle = Font.title2.weight(.semibold)
    static let ghostBody = Font.subheadline
    static let ghostRowTitle = Font.subheadline.weight(.medium)
    static let ghostRowSubtitle = Font.footnote
    static let ghostCaption = Font.caption2.weight(.medium)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// The canvas card on the chrome: 12pt continuous corner, the Mac card's 6% shadow.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        content
            .clipShape(shape)
            .background {
                shape
                    .fill(Theme.canvas)
                    .shadow(color: Theme.shadow.opacity(0.06), radius: 8, x: 0, y: 2)
            }
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

/// "now", "4m", "3h", "2d": the compact age the Mac sidebar shows.
func age(_ date: Date?, now: Date = .now) -> String {
    guard let date else { return "" }
    let minutes = Int(now.timeIntervalSince(date) / 60)
    if minutes < 1 { return "now" }
    if minutes < 60 { return "\(minutes)m" }
    if minutes < 60 * 24 { return "\(minutes / 60)h" }
    return "\(minutes / 60 / 24)d"
}
