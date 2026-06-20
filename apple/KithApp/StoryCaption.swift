import SwiftUI

/// A caption style for stories — some color the text, some put a colored highlight
/// behind it (Instagram-style). The chosen style is encoded into the story body so the
/// viewer renders it exactly as the author saw it (no engine change needed).
struct StoryCaptionStyle: Identifiable {
    let id: Int
    let textColor: Color
    let bgColor: Color?      // nil = plain colored text; otherwise a highlight behind the text
    let font: Font
    var swatchLabel: String { "Aa" }
}

enum StoryCaptions {
    static let styles: [StoryCaptionStyle] = [
        .init(id: 0, textColor: .white,           bgColor: nil,                 font: .title3.weight(.semibold)),
        .init(id: 1, textColor: .black,           bgColor: .white,              font: .title3.weight(.bold)),
        .init(id: 2, textColor: .white,           bgColor: KithTheme.pink,      font: .title3.weight(.bold)),
        .init(id: 3, textColor: KithTheme.amber,  bgColor: nil,                 font: .system(.title2, design: .serif).weight(.bold)),
        .init(id: 4, textColor: .white,           bgColor: .black.opacity(0.5), font: .system(.title3, design: .rounded).weight(.semibold)),
        .init(id: 5, textColor: KithTheme.violet, bgColor: .white,              font: .system(.title2, design: .monospaced).weight(.bold)),
        .init(id: 6, textColor: .white,           bgColor: KithTheme.violet,    font: .system(.title2, design: .rounded).weight(.heavy)),
    ]

    static func style(_ id: Int) -> StoryCaptionStyle { styles.first { $0.id == id } ?? styles[0] }

    /// Encode style id + caption into the story body (viewer decodes it). Uses a control
    /// char so the marker never shows if the text is rendered raw somewhere.
    static func encode(_ caption: String, styleId: Int) -> String {
        let t = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "" : "\u{1}\(styleId)\u{1}\(t)"
    }
    /// Decode a story body into (clean caption text, style).
    static func decode(_ body: String) -> (text: String, style: StoryCaptionStyle) {
        if body.hasPrefix("\u{1}") {
            let parts = body.dropFirst().split(separator: "\u{1}", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2, let id = Int(parts[0]) { return (String(parts[1]), style(id)) }
        }
        return (body, styles[0])
    }
}

/// Renders a caption with its style (colored text, or text on a colored highlight).
struct StyledCaption: View {
    let text: String
    let style: StoryCaptionStyle
    var body: some View {
        Text(text)
            .font(style.font)
            .foregroundStyle(style.textColor)
            .multilineTextAlignment(.center)
            .padding(.horizontal, style.bgColor == nil ? 0 : 12)
            .padding(.vertical, style.bgColor == nil ? 0 : 6)
            .background {
                if let bg = style.bgColor {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(bg)
                }
            }
            .shadow(color: style.bgColor == nil ? .black.opacity(0.45) : .clear, radius: 6)
    }
}

/// A horizontal row of style swatches for the composer.
struct CaptionStyleRow: View {
    @Binding var selectedId: Int
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(StoryCaptions.styles) { s in
                    Button { selectedId = s.id } label: {
                        Text(s.swatchLabel)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(s.textColor)
                            .frame(width: 38, height: 38)
                            .background {
                                Circle().fill(s.bgColor ?? Color.white.opacity(0.18))
                            }
                            .overlay(Circle().strokeBorder(.white, lineWidth: selectedId == s.id ? 2.5 : 0))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
