import SwiftUI

struct ConfirmationsBadge: View {

    let confirmations: [Confirmation]
    @State private var isExpanded = false

    var body: some View {
        if confirmations.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text("Confirmed by \(confirmations.count) other \(confirmations.count == 1 ? "channel" : "channels")")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(confirmations, id: \.permalink) { c in
                            Link(destination: URL(string: c.permalink) ?? URL(string: "https://github.com")!) {
                                Text("· \(c.channelTitle)")
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.leading, 16)
                }
            }
        }
    }
}
