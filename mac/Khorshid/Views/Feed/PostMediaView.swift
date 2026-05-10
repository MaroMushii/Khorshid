import SwiftUI

private let mirrorBase = "https://raw.githubusercontent.com/MaroMushii/Khorshid/refs/heads/export"

struct PostMediaView: View {

    let media: [PostMedia]

    var body: some View {
        if media.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(media.prefix(4).enumerated()), id: \.offset) { _, item in
                        if let path = item.thumbnailPath ?? item.assetPath,
                           let url = URL(string: mirrorBase + "/" + path) {
                            let thumbHeight: CGFloat = 120
                            let thumbWidth: CGFloat = item.aspectRatio.map { thumbHeight * $0 } ?? thumbHeight

                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: thumbWidth, height: thumbHeight)
                                    .clipShape(.rect(cornerRadius: 8))
                                    .overlay {
                                        if item.kind == .video {
                                            Image(systemName: "play.circle.fill")
                                                .font(.title)
                                                .foregroundStyle(.white)
                                        }
                                    }
                            } placeholder: {
                                Rectangle()
                                    .fill(.quaternary)
                                    .frame(width: thumbWidth, height: thumbHeight)
                                    .clipShape(.rect(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
        }
    }
}
