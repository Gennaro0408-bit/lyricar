import SwiftUI
import WidgetKit
import ActivityKit

/// Live Activity dei testi: su CarPlay, schermata di blocco e Dynamic Island.
struct LyricsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricsActivityAttributes.self) { context in
            LyricsActivityView(state: context.state)
                .activityBackgroundTint(.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    LyricsActivityView(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "music.note").foregroundStyle(.green)
            } compactTrailing: {
                Text(context.state.current).lineLimit(1).frame(maxWidth: 80)
            } minimal: {
                Image(systemName: "music.note").foregroundStyle(.green)
            }
        }
        .supplementalActivityFamilies([.small]) // formato compatto usato da CarPlay e Apple Watch
    }
}

struct LyricsActivityView: View {
    @Environment(\.activityFamily) private var family
    let state: LyricsActivityAttributes.ContentState

    private var small: Bool { family == .small }

    var body: some View {
        VStack(alignment: .leading, spacing: small ? 4 : 6) {
            if !state.title.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: state.isPlaying ? "music.note" : "pause.fill")
                    Text("\(state.title) · \(state.artist)").lineLimit(1)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }

            if let message = state.message {
                Text(message)
                    .font(small ? .headline : .title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text(state.current)
                    .font(.system(size: small ? 20 : 24, weight: .bold, design: .rounded))
                    .lineLimit(small ? 2 : 3)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.opacity)
                if let next = state.next, !next.isEmpty {
                    Text(next)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(small ? 8 : 14)
    }
}
