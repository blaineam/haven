import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var store = AccountStore()
    @State private var report: SelfTestReport?
    @State private var copied = false

    private let linkDomain = "kith.link"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    qrCard

                    identityCard

                    selfTestCard

                    Button(role: .destructive) {
                        store.reset()
                        report = nil
                    } label: {
                        Label("Start over (new identity)", systemImage: "arrow.counterclockwise")
                    }
                    .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("Kith")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Your identity")
                .font(.title2.bold())
            Text("No email, no phone number, no PII — just a hybrid post-quantum keypair on this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var qrCard: some View {
        VStack(spacing: 12) {
            if let qr = QRCode.image(from: store.account.kithUri()) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(10)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            Text("Scan to reach me")
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(label: "Node id", value: String(store.account.nodeIdHex().prefix(24)) + "…")
            row(label: "Verify", value: store.account.verificationHex())
            Button {
                UIPasteboard.general.string = store.account.kithLink(domain: linkDomain)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Label(copied ? "Copied!" : "Copy reach-me link", systemImage: copied ? "checkmark" : "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var selfTestCard: some View {
        VStack(spacing: 14) {
            Button {
                report = selfTest()
            } label: {
                Label("Run on-device hybrid-PQ self-test", systemImage: "checkmark.shield")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if let r = report {
                VStack(spacing: 8) {
                    check("Identity generated", r.identityOk)
                    check("Hybrid KEM + AES-256-GCM (seal → open)", r.hybridKemOk)
                    check("Hybrid signature (Ed25519 + ML-DSA)", r.signatureOk)
                    check("Reach-me link round-trip", r.linkOk)
                    Divider()
                    Label(r.summary, systemImage: r.allOk ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(r.allOk ? .green : .red)
                        .multilineTextAlignment(.center)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func row(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospaced()).multilineTextAlignment(.trailing)
        }
    }

    private func check(_ title: String, _ ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
            Text(title).font(.subheadline)
            Spacer()
        }
    }
}
