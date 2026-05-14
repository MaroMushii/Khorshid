import SwiftUI

@main
struct KhorshidApp: App {

    @State private var channelStore = ChannelStore()
    @State private var feedStore = FeedStore()
    @State private var identityStore = IdentityStore()
    @State private var patPool = PATPool()
    @State private var socialStore = SocialStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(channelStore)
                .environment(feedStore)
                .environment(identityStore)
                .environment(patPool)
                .environment(socialStore)
                .onAppear {
                    socialStore.configure(patPool: patPool, identityStore: identityStore)
                    channelStore.start()
                    feedStore.start()
                    identityStore.start()
                    patPool.start()
                }
        }
        .defaultSize(width: 900, height: 600)
    }
}
