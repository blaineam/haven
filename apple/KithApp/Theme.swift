import SwiftUI

/// Kith's design system — the single source of brand color, depth, motion, and
/// tactile feel. Keeping it here makes the look consistent and portable to other
/// platforms' UIs.
enum KithTheme {
    static let violet = Color(red: 0.486, green: 0.227, blue: 0.929) // #7C3AED
    static let pink = Color(red: 0.925, green: 0.282, blue: 0.600)   // #EC4899
    static let amber = Color(red: 0.961, green: 0.620, blue: 0.043)  // #F59E0B

    /// The signature sunset gradient (matches the app icon).
    static let brand = LinearGradient(
        colors: [violet, pink, amber],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let brandHorizontal = LinearGradient(
        colors: [violet, pink, amber],
        startPoint: .leading, endPoint: .trailing
    )

    // Motion vocabulary — a small set of springs used everywhere for cohesion.
    static let bouncy = Animation.spring(response: 0.42, dampingFraction: 0.68)
    static let smooth = Animation.spring(response: 0.5, dampingFraction: 0.85)
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.7)
}

/// Soft branded backdrop: grouped-background base with two gentle brand glows.
struct KithBackground: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            RadialGradient(
                colors: [KithTheme.pink.opacity(0.22), .clear],
                center: UnitPoint(x: 0.85, y: -0.05), startRadius: 0, endRadius: 460
            )
            RadialGradient(
                colors: [KithTheme.violet.opacity(0.20), .clear],
                center: UnitPoint(x: 0.05, y: 0.18), startRadius: 0, endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

/// A floating, slightly-bordered card with soft depth.
struct KithCard: ViewModifier {
    var padding: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 8)
    }
}

extension View {
    func kithCard(padding: CGFloat = 18) -> some View { modifier(KithCard(padding: padding)) }
}

/// Tactile press feedback: gentle scale + dim on press.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(KithTheme.snappy, value: configuration.isPressed)
    }
}

/// A prominent brand-gradient pill button.
struct BrandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(KithTheme.brandHorizontal, in: Capsule())
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(color: KithTheme.pink.opacity(0.35), radius: 10, x: 0, y: 5)
            .animation(KithTheme.snappy, value: configuration.isPressed)
    }
}

/// Gradient title text helper.
struct BrandText: View {
    let text: String
    var font: Font = .largeTitle.bold()
    var body: some View {
        Text(text).font(font).foregroundStyle(KithTheme.brand)
    }
}
