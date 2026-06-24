#if DEBUG
import SwiftUI

/// Debug-only side-by-side of the LIVE editing caption preview vs the FINAL rendered StyledCaption,
/// so the highlight pill can be made to actually match. Launch with `HAVEN_CAPTION_HARNESS=1`.
struct CaptionHarness: View {
    @State private var text = "Geeze"
    @State private var spec: StoryCaptions.Spec = {
        var s = StoryCaptions.Spec()
        s.styleRaw = StoryCaptions.Style.highlight.rawValue
        s.color = 2   // a pink
        return s
    }()
    @FocusState private var focused: Bool

    private var highlightActive: Bool { StoryCaptions.bgColor(spec) != nil && !text.isEmpty }

    var body: some View {
        ZStack {
            Color(white: 0.55).ignoresSafeArea()
            VStack(spacing: 56) {
                Group {
                    Text("EDITING (live, in a Spacer/Spacer box like the composer)").font(.caption.bold()).foregroundStyle(.black)
                    // Mirror the composer's exact container so we test the real layout context.
                    VStack { Spacer(); editingPreview; Spacer() }.frame(height: 120)
                }
                Group {
                    Text("FINAL (StyledCaption, what viewers see)").font(.caption.bold()).foregroundStyle(.black)
                    StyledCaption(text: text, spec: spec)
                }
                TextField("type here", text: $text).focused($focused)
                    .padding(8).background(.white).cornerRadius(8).padding(.horizontal, 40)
            }
        }
    }

    /// Overlay approach: the REAL StyledCaption is the visible render; an invisible TextField on
    /// top captures input + shows the caret. Guarantees editing == final for every style.
    private var editingPreview: some View {
        ZStack {
            StyledCaption(text: text.isEmpty ? " " : text, spec: spec)
            TextField("", text: $text, axis: .vertical)
                .focused($focused)
                .multilineTextAlignment(.center)
                .font(StoryCaptions.font(spec))
                .foregroundStyle(.clear)   // glyphs invisible (StyledCaption shows them); caret stays
                .tint(.white)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}
#endif
