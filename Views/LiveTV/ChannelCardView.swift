import SwiftUI

struct ChannelCardView: View {
    let channel: Channel
    let logoURL: URL?
    let currentProgram: Program?
    let isFavorite: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                // Channel logo / number
                HStack {
                    if let url = logoURL {
                        CachedAsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            channelNumberView
                        }
                        .frame(width: 80, height: 50)
                    } else {
                        channelNumberView
                    }

                    Spacer()

                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundStyle(isFavorite ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)

                    if let num = channel.channelNumber {
                        Text(formatChannelNumber(num))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Channel name
                Text(channel.name)
                    .font(.headline)
                    .lineLimit(1)

                // Current program
                if let program = currentProgram {
                    Text(program.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if let start = program.startDate, let end = program.endDate {
                        ProgressView(value: progressValue(start: start, end: end))
                            .tint(.blue)
                    }
                } else {
                    Text("No program data")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding()
            .frame(width: 280, height: 180)
            .background(isFocused ? Color.blue.opacity(0.3) : Color(.systemGray).opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
        .focused($isFocused)
    }

    private var channelNumberView: some View {
        Text(formatChannelNumber(channel.channelNumber ?? 0))
            .font(.title2)
            .fontWeight(.bold)
            .frame(width: 80, height: 50)
            .background(Color.blue.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func formatChannelNumber(_ num: Double) -> String {
        if num == num.rounded() {
            return String(Int(num))
        }
        return String(format: "%.1f", num)
    }

    private func progressValue(start: Date, end: Date) -> Double {
        let now = Date()
        let total = end.timeIntervalSince(start)
        let elapsed = now.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(max(elapsed / total, 0), 1)
    }
}
