import SwiftUI

@main
struct KhorshidApp: App {

    @State private var channelStore = ChannelStore()
    @State private var feedStore = FeedStore()
    @State private var identityStore = IdentityStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(channelStore)
                .environment(feedStore)
                .environment(identityStore)
                .onAppear {
                    channelStore.start()
                    feedStore.start()
                    identityStore.start()
                }
        }
        .defaultSize(width: 900, height: 600)
    }
}
