import SwiftUI

/// Scoped to the renewal hierarchy; never changes UIKit's global appearance.
@available(iOS 15.0, *)
enum RenewalTheme {
    static let canvas = Color(red: 1, green: 254 / 255, blue: 249 / 255)
    static let surface = Color.white
    static let chip = Color(red: 242 / 255, green: 241 / 255, blue: 226 / 255)
    static let mint = Color(red: 200 / 255, green: 244 / 255, blue: 194 / 255)
    static let action = Color(red: 37 / 255, green: 107 / 255, blue: 63 / 255)
    static let ink = Color(red: 51 / 255, green: 51 / 255, blue: 51 / 255)
    static let secondary = Color(red: 95 / 255, green: 100 / 255, blue: 89 / 255)
    static let line = Color(red: 224 / 255, green: 226 / 255, blue: 228 / 255)
    static let danger = Color(red: 184 / 255, green: 57 / 255, blue: 31 / 255)
    static let warning = Color(red: 1, green: 241 / 255, blue: 214 / 255)
    static let pageInset: CGFloat = 20
    static let cardRadius: CGFloat = 16
    static let amountFont = Font.custom("Binggrae-Bold", size: 44, relativeTo: .largeTitle)
}

@available(iOS 15.0, *)
struct RenewalPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .foregroundColor(isEnabled ? .white : RenewalTheme.secondary)
            .background(isEnabled ? RenewalTheme.action : RenewalTheme.line)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

@available(iOS 15.0, *)
extension View {
    func renewalCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RenewalTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: RenewalTheme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: RenewalTheme.cardRadius).stroke(RenewalTheme.line, lineWidth: 1))
    }

    func renewalInput() -> some View {
        padding(12)
            .frame(minHeight: 48)
            .background(RenewalTheme.chip)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
