import SwiftUI

struct ProgramDetailView: View {
    let program: Program
    @ObservedObject var channelsVM: ChannelsViewModel
    @ObservedObject var guideVM: GuideViewModel
    @ObservedObject var recordingsVM: RecordingsViewModel
    let onWatch: (Channel) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recordingScheduled = false
    @State private var seriesScheduled = false

    private var matchingChannel: Channel? {
        // Find channel that maps to this program's tvg_id
        // Could be direct (channel.tvg_id == program.tvg_id)
        // or via epg_data_id remapping
        channelsVM.channels.first { channel in
            let progs = guideVM.programs(for: channel)
            return progs.contains { $0.id == program.id }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(program.title)
                .font(.title2)
                .fontWeight(.bold)

            HStack(spacing: 16) {
                if let se = program.seasonEpisodeString {
                    Text(se)
                        .foregroundStyle(.secondary)
                }

                if program.isNew == true {
                    Text("NEW")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                if program.isLive == true {
                    Text("LIVE")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            if let sub = program.subTitle {
                Text(sub)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if let start = program.startDate, let end = program.endDate {
                HStack {
                    Image(systemName: "clock")
                    Text(DateFormatters.dateTime.string(from: start))
                    Text("-")
                    Text(DateFormatters.timeOnly.string(from: end))
                }
                .foregroundStyle(.secondary)
            }

            if let channel = matchingChannel {
                HStack {
                    Image(systemName: "tv")
                    if let num = channel.channelNumber {
                        Text(num == num.rounded() ? String(Int(num)) : String(format: "%.1f", num))
                    }
                    Text(channel.name)
                }
                .foregroundStyle(.secondary)
            }

            if let desc = program.description, !desc.isEmpty {
                ScrollView {
                    Text(desc)
                        .font(.body)
                }
                .frame(maxHeight: 200)
            }

            Spacer()

            HStack(spacing: 20) {
                if let channel = matchingChannel {
                    if program.isCurrentlyAiring {
                        Button(action: {
                            onWatch(channel)
                        }) {
                            Label("Watch Now", systemImage: "play.fill")
                        }
                    }

                    Button(action: {
                        Task { await scheduleRecording(channel: channel) }
                    }) {
                        if recordingScheduled {
                            Label("Recording Scheduled", systemImage: "checkmark.circle.fill")
                        } else {
                            Label("Record", systemImage: "record.circle")
                        }
                    }
                    .disabled(recordingScheduled)

                    Button(action: {
                        Task { await scheduleSeriesRecording(channel: channel) }
                    }) {
                        if seriesScheduled {
                            Label("Series Set", systemImage: "checkmark.circle.fill")
                        } else {
                            Label("Record Series", systemImage: "arrow.clockwise.circle")
                        }
                    }
                    .disabled(seriesScheduled)
                }

                Button("Close") { dismiss() }
            }
        }
        .padding(40)
        .frame(maxWidth: 800)
    }

    private func scheduleRecording(channel: Channel) async {
        guard let start = program.startDate, let end = program.endDate else { return }

        let progInfo = RecordingProgram(
            title: program.title,
            description: program.description,
            season: program.season,
            episode: program.episode
        )

        await recordingsVM.scheduleRecording(
            channelId: channel.id,
            startTime: start,
            endTime: end,
            program: progInfo
        )

        recordingScheduled = true
    }

    private func scheduleSeriesRecording(channel: Channel) async {
        await recordingsVM.createSeriesRule(
            channelId: channel.id,
            name: program.title,
            program: program
        )
        seriesScheduled = true
    }
}
