import SwiftUI

@main
struct KhorshidApp: App {

    @State private var channelStore = ChannelStore()
    @State private var feedStore = FeedStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(channelStore)
                .environment(feedStore)
                .onAppear {
                    channelStore.start()
                    feedStore.start()
                }
        }
        .defaultSize(width: 900, height: 600)
    }
}
