import SwiftUI

@main
struct KithApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @StateObject private var store = AccountStore()
    @State private var tab: String = ProcessInfo.processInfo.environment["KITH_TAB"] ?? "identity"

    var body: some View {
        TabView(selection: $tab) {
            ContentView(store: store)
                .tag("identity")
                .tabItem { Label("Identity", systemImage: "qrcode") }
            FeedView(seed: store.account.secretSeed())
                .id(store.account.nodeIdHex())
                .tag("feed")
                .tabItem { Label("Feed", systemImage: "bubble.left.and.bubble.right.fill") }
        }
        .tint(KithTheme.pink)
    }
}
