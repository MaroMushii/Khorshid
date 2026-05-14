import SwiftUI

@main
struct KhorshidApp: App {

    @State private var channelStore = ChannelStore()
    @State private var feedStore = FeedStore()
    @State private var identityStore = IdentityStore()
    @State private var patPool = PATPool()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(channelStore)
                .environment(feedStore)
                .environment(identityStore)
                .environment(patPool)
                .onAppear {
                    channelStore.start()
                    feedStore.start()
                    identityStore.start()
                    patPool.start()
                }
        }
        .defaultSize(width: 900, height: 600)
    }
}
