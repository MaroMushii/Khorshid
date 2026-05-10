import SwiftUI

struct PostRow: View {

    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PostBodyView(html: post.bodyHtml)
            PostMediaView(media: post.media)
            PostMetaView(post: post)
        }
        .padding(.vertical, 4)
    }
}

private struct PostMetaView: View {

    let post: Post

    var body: some View {
        HStack(spacing: 8) {
            if let postedAt = post.postedAt {
                Text(postedAt, style: .relative)
                    .foregroundStyle(.secondary)
            }
            if let views = post.viewsLabel {
                Text(views)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ForEach(post.reactions, id: \.emoji) { reaction in
                Text("\(reaction.emoji) \(reaction.count)")
            }
        }
        .font(.caption)
    }
}
