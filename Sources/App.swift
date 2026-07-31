import SwiftUI

@main
struct DupeFinderApp: App {
    @StateObject private var model = DupeModel()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(model)
                .frame(minWidth: 640, minHeight: 560)
        }
        .windowResizability(.contentMinSize)
    }
}
