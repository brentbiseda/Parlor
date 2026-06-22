import SwiftUI
import UIKit

/// App delegate that controls supported orientations dynamically.
/// BigScreen mode sets `mask = .all` so the TV display can go landscape;
/// everything else stays portrait-only.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var mask: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.mask
    }
}

@main
struct ParlorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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
            if phase == .background { model.saveSnapshotForBackground() }
        }
    }
}
