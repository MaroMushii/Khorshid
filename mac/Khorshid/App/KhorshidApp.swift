import SwiftUI

@main
struct KhorshidApp: App {

    @State private var store = ChannelStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .onAppear { store.start() }
        }
    }
}
