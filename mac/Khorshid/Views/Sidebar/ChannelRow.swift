import SwiftUI

struct ChannelRow: View {

    let channel: Channel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(channel.title)
                .fontWeight(.medium)
            Text("\(channel.postCount) posts")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
