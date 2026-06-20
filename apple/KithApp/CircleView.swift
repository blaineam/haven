import SwiftUI

/// Manage who's in your circle: see each person's real (signed) name + whether the
/// secure handshake has completed, remove people, or invite someone new. "Waiting"
/// means you don't yet hold their keys — usually because you haven't both added each
/// other, you're on different app versions, or one of you started a new identity.
struct CircleView: View {
    let account: Account
    @ObservedObject private var contacts = ContactsStore.shared
    @ObservedObject private var store = FeedStore.shared
    @State private var showInvite = false

    private var isDefault: Bool { store.activeCircleId == "default" }
    private var memberIds: Set<String> { Set(store.handshaked(in: store.activeCircleId)) }
    private var membersInCircle: [Contact] {
        isDefault ? contacts.contacts : contacts.contacts.filter { memberIds.contains($0.idHex) }
    }
    private var addable: [Contact] { contacts.contacts.filter { !memberIds.contains($0.idHex) } }

    var body: some View {
        ZStack {
            KithBackground()
            List {
                Section {
                    if membersInCircle.isEmpty {
                        Text(isDefault ? "No one yet. Tap + to invite someone."
                                       : "No one here yet — add from your contacts below.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(membersInCircle) { c in
                        row(c)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .leading) {
                                Button { store.forceSync() } label: {
                                    Label("Reconnect", systemImage: "arrow.clockwise")
                                }.tint(KithTheme.pink)
                            }
                    }
                    .onDelete { offsets in
                        guard isDefault else { return }   // removing from sub-circles: leave the circle instead
                        offsets.map { membersInCircle[$0] }.forEach(contacts.remove)
                    }
                } header: {
                    Text(isDefault ? "People in your circle" : "In \(store.activeCircleName)")
                } footer: {
                    Text("“Waiting” means the secure handshake hasn't completed — both of you must add each other, on the **same app version**. New identity? Re-scan each other's QR.")
                }

                if !isDefault {
                    Section("Add from your contacts") {
                        if addable.isEmpty {
                            Text("Everyone you know is already here.")
                                .font(.caption).foregroundStyle(.secondary).listRowBackground(Color.clear)
                        }
                        ForEach(addable) { c in
                            Button { store.addContactToActiveCircle(idHex: c.idHex) } label: {
                                HStack {
                                    Text(c.displayName).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill").foregroundStyle(KithTheme.pink)
                                }
                            }.listRowBackground(Color.clear)
                        }
                    }
                    Section {
                        Button(role: .destructive) { store.leaveActiveCircle() } label: {
                            Label("Leave this circle", systemImage: "rectangle.portrait.and.arrow.right")
                        }.listRowBackground(Color.clear)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(isDefault ? "Your circle" : store.activeCircleName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showInvite = true } label: { Image(systemName: "person.badge.plus") }
            }
        }
        .sheet(isPresented: $showInvite) { ConnectView(account: account, contacts: contacts) }
    }

    private func row(_ c: Contact) -> some View {
        let connected = store.isConnected(c.idHex)
        return HStack(spacing: 12) {
            Circle().fill(KithTheme.brand).frame(width: 38, height: 38)
                .overlay(Text(String(c.displayName.prefix(1))).font(.subheadline.bold()).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(c.displayName).font(.subheadline.weight(.medium))
                HStack(spacing: 5) {
                    Circle().fill(connected ? Color.green : Color.secondary).frame(width: 7, height: 7)
                    Text(connected ? "Connected" : "Waiting to connect")
                        .font(.caption2).foregroundStyle(connected ? .green : .secondary)
                }
            }
            Spacer()
            Text(String(c.idHex.prefix(6))).font(.caption2.monospaced()).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
