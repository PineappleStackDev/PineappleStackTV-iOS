import SwiftUI

struct RecordingRowView: View {
    let recording: Recording
    let channelName: String
    var onStop: (() -> Void)? = nil
    var onExtend: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 16) {
            // Status indicator
            statusIcon

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.programTitle)
                    .font(.headline)

                Text(channelName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let start = recording.startDate, let end = recording.endDate {
                    HStack {
                        Text(DateFormatters.dateTime.string(from: start))
                        Text("-")
                        Text(DateFormatters.timeOnly.string(from: end))
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Actions for in-progress recordings
            if recording.isInProgress {
                HStack(spacing: 12) {
                    if let onExtend {
                        Menu {
                            Button("+15 min") { onExtend(15) }
                            Button("+30 min") { onExtend(30) }
                            Button("+60 min") { onExtend(60) }
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                    }

                    if let onStop {
                        Button(action: onStop) {
                            Image(systemName: "stop.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            if recording.isCompleted {
                Image(systemName: "play.circle")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch recording.status {
        case "recording":
            Image(systemName: "record.circle.fill")
                .foregroundStyle(.red)
                .font(.title3)
        case "scheduled":
            Image(systemName: "clock.fill")
                .foregroundStyle(.orange)
                .font(.title3)
        case "completed":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
        case "failed", "interrupted":
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.title3)
        default:
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.gray)
                .font(.title3)
        }
    }
}
