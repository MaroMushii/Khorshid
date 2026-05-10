import SwiftUI

private let mirrorBase = "https://raw.githubusercontent.com/MaroMushii/Khorshid/refs/heads/export"

struct ChannelRow: View {

    let channel: Channel

    var body: some View {
        HStack(spacing: 8) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.title)
                    .fontWeight(.medium)
                Text("\(channel.postCount) posts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var avatar: some View {
        if let photoPath = channel.photoPath,
           let url = URL(string: mirrorBase + "/" + photoPath) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(.circle)
            } placeholder: {
                Circle()
                    .fill(.quaternary)
                    .frame(width: 32, height: 32)
            }
        } else {
            Circle()
                .fill(.quaternary)
                .frame(width: 32, height: 32)
        }
    }
}
