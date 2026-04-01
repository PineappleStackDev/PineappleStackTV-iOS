import SwiftUI

struct PlayerOverlayView: View {
    @ObservedObject var playerVM: PlayerViewModel
    @ObservedObject var channelsVM: ChannelsViewModel
    let onClose: () -> Void

    var body: some View {
        VStack {
            // Top bar: channel info
            HStack {
                if let channel = playerVM.currentChannel {
                    if let url = channelsVM.logoURLSync(for: channel) {
                        CachedAsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            EmptyView()
                        }
                        .frame(width: 60, height: 40)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            if let num = channel.channelNumber {
                                Text(formatChannelNumber(num))
                                    .font(.title3)
                                    .fontWeight(.bold)
                            }
                            Text(channel.name)
                                .font(.title3)
                        }

                        if let program = channelsVM.currentProgram(for: channel) {
                            Text(program.title)
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            if let sub = program.subTitle {
                                Text(sub)
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)
                            }

                            if let start = program.startDate, let end = program.endDate {
                                HStack {
                                    Text(DateFormatters.timeOnly.string(from: start))
                                    Text("-")
                                    Text(DateFormatters.timeOnly.string(from: end))

                                    Spacer()

                                    if let se = program.seasonEpisodeString {
                                        Text(se)
                                            .foregroundStyle(.secondary)
                                    }

                                    if program.isNew == true {
                                        Text("NEW")
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.blue)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()

                    Button("Back", action: onClose)
                        .buttonStyle(.plain)
                }
            }
            .padding(30)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.8), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Spacer()

            // Bottom hint
            HStack {
                Label("Up/Down: Change Channel", systemImage: "arrow.up.arrow.down")
                Spacer()
                Label("Menu: Close", systemImage: "xmark.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(20)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private func formatChannelNumber(_ num: Double) -> String {
        if num == num.rounded() {
            return String(Int(num))
        }
        return String(format: "%.1f", num)
    }
}
