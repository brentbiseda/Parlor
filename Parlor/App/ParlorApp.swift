import SwiftUI

@main
struct ParlorApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.competitions)
                .environmentObject(model.stats)
                .environmentObject(model.profiles)
                .environmentObject(model.leaderboards)
                .environmentObject(model.savedGames)
                .onOpenURL { model.handle(url: $0) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Asynchronous play: park the live table when the app backgrounds.
            if phase == .background { model.saveSnapshotForBackground() }
        }
    }
}
