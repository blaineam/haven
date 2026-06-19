import SwiftUI
import UIKit

struct ContentView: View {
    @ObservedObject var store: AccountStore
    @State private var report: SelfTestReport?
    @State private var runCount = 0
    @State private var copied = false
    @State private var appeared = false

    private let linkDomain = "kith.link"

    var body: some View {
        ZStack {
            KithBackground()
            ScrollView {
                VStack(spacing: 22) {
                    header.entrance(appeared, delay: 0.00)
                    qrCard.entrance(appeared, delay: 0.06)
                    identityCard.entrance(appeared, delay: 0.12)
                    selfTestCard.entrance(appeared, delay: 0.18)
                    resetButton.entrance(appeared, delay: 0.24)
                }
                .padding(20)
            }
        }
        .sensoryFeedback(.selection, trigger: copied)
        .sensoryFeedback(trigger: runCount) { _, _ in
            report?.allOk == true ? .success : .error
        }
        .onAppear { withAnimation(KithTheme.smooth) { appeared = true } }
    }

    private var header: some View {
        VStack(spacing: 6) {
            BrandText(text: "Kith")
            Text("No email, no phone, no PII — just a hybrid post-quantum keypair on this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var qrCard: some View {
        VStack(spacing: 14) {
            if let qr = QRCode.image(from: store.account.kithUri()) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 210, height: 210)
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: KithTheme.violet.opacity(0.25), radius: 16, y: 8)
            }
            Label("Scan to reach me", systemImage: "qrcode.viewfinder")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .kithCard()
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            infoRow("Node id", String(store.account.nodeIdHex().prefix(24)) + "…")
            infoRow("Verify", store.account.verificationHex())
            Button {
                UIPasteboard.general.string = store.account.kithLink(domain: linkDomain)
                withAnimation(KithTheme.bouncy) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    withAnimation(KithTheme.smooth) { copied = false }
                }
            } label: {
                Label(copied ? "Copied!" : "Copy reach-me link",
                      systemImage: copied ? "checkmark.circle.fill" : "link")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(BrandButtonStyle())
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kithCard()
    }

    private var selfTestCard: some View {
        VStack(spacing: 16) {
            Button {
                withAnimation(KithTheme.bouncy) {
                    report = selfTest()
                    runCount += 1
                }
            } label: {
                Label("Run on-device hybrid-PQ self-test", systemImage: "checkmark.shield.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KithTheme.pink)
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity)
                    .background(
                        Capsule().strokeBorder(KithTheme.brandHorizontal, lineWidth: 1.5)
                    )
            }
            .buttonStyle(PressableStyle())

            if let r = report {
                VStack(spacing: 10) {
                    checkRow("Identity generated", r.identityOk, 0)
                    checkRow("Hybrid KEM + AES-256-GCM (seal → open)", r.hybridKemOk, 1)
                    checkRow("Hybrid signature (Ed25519 + ML-DSA)", r.signatureOk, 2)
                    checkRow("Reach-me link round-trip", r.linkOk, 3)
                    Divider().padding(.vertical, 2)
                    Label(r.summary, systemImage: r.allOk ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(r.allOk ? .green : .red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .kithCard()
    }

    private var resetButton: some View {
        Button(role: .destructive) {
            withAnimation(KithTheme.smooth) {
                store.reset()
                report = nil
            }
        } label: {
            Label("Start over (new identity)", systemImage: "arrow.counterclockwise")
                .font(.footnote.weight(.medium))
        }
        .buttonStyle(PressableStyle())
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospaced()).multilineTextAlignment(.trailing)
        }
    }

    private func checkRow(_ title: String, _ ok: Bool, _ index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
                .imageScale(.large)
            Text(title).font(.subheadline)
            Spacer()
        }
        .opacity(report != nil ? 1 : 0)
        .offset(x: report != nil ? 0 : -16)
        .animation(KithTheme.bouncy.delay(Double(index) * 0.08), value: runCount)
    }
}

/// Staggered slide-up entrance for a section.
private struct Entrance: ViewModifier {
    let shown: Bool
    let delay: Double
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .animation(KithTheme.smooth.delay(delay), value: shown)
    }
}

private extension View {
    func entrance(_ shown: Bool, delay: Double) -> some View {
        modifier(Entrance(shown: shown, delay: delay))
    }
}
