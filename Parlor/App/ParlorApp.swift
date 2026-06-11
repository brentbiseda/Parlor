import SwiftUI

@main
struct ParlorApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onOpenURL { model.handle(url: $0) }
        }
    }
}
