import SwiftUI

private let mirrorBase = "https://raw.githubusercontent.com/MaroMushii/Khorshid/refs/heads/export"

struct FeedPostRow: View {

    let post: FeedPost
    let channelPhotoPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            PostBodyView(html: post.bodyHtml, plainText: post.plainText)
            PostMediaView(media: post.media)
            footer
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            avatar
            VStack(alignment: .leading, spacing: 1) {
                Text(post.channelTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let postedAt = post.postedAt {
                    Text(postedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let path = channelPhotoPath, let url = URL(string: mirrorBase + "/" + path) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(.circle)
            } placeholder: {
                Circle().fill(.quaternary).frame(width: 28, height: 28)
            }
        } else {
            Circle().fill(.quaternary).frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "newspaper")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if post.voteCount > 0 || !post.confirmations.isEmpty {
            HStack(spacing: 12) {
                if post.voteCount > 0 {
                    Label("\(post.voteCount)", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ConfirmationsBadge(confirmations: post.confirmations)
                Spacer()
            }
        }
    }
}
