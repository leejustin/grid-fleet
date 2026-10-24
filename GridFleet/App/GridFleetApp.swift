import FoldKit
import SwiftData
import SwiftUI

@main
struct GridFleetApp: App {
    @State private var settings = AppSettings()
    @State private var store = StoreService()
    @State private var gameCenter = GameCenterService()
    @State private var router = AppRouter()
    private let container = Persistence.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .foldAware()
                .environment(settings)
                .environment(store)
                .environment(gameCenter)
                .environment(router)
                .modelContainer(container)
                .task {
                    Diagnostics.shared.start()
                    // UI tests run without Game Center, whose sign-in sheet would cover the app.
                    if !UserDefaults.standard.bool(forKey: "GFUITest") { gameCenter.authenticate() }
                    await store.start()
                }
                .onOpenURL { router.handle($0) }
        }
    }
}
