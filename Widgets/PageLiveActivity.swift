import ActivityKit
import SwiftUI
import WidgetKit

/// The list chosen for the live view, on the Lock Screen and in the Dynamic Island.
struct PageLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PageActivityAttributes.self) { context in
            LockScreenPage(list: context.state.list, isOver: context.isStale)
                .activityBackgroundTint(Color.paper)
                .activitySystemActionForegroundColor(Color.ink)
                .widgetURL(context.state.list.url)
        } dynamicIsland: { context in
            let list = context.state.list
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(list.name).font(.system(size: 15, design: .serif)).foregroundStyle(.white.opacity(0.6))
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(list.left)").font(.system(size: 15, design: .serif)).foregroundStyle(.white.opacity(0.6))
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(list.lines(PageActivityAttributes.lines)) { line in
                            WidgetTask(line: line, size: 18, ink: .white, faded: .white.opacity(0.5), inActivity: true)
                        }
                        if list.lines.isEmpty {
                            Text(PageSnapshot.emptyWords).font(.system(size: 18, design: .serif)).foregroundStyle(.white.opacity(0.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                Text(list.name).font(.system(size: 14, design: .serif)).lineLimit(1)
            } compactTrailing: {
                Text("\(list.left)").font(.system(size: 14, design: .serif))
            } minimal: {
                Text("\(list.left)").font(.system(size: 14, design: .serif))
            }
            .widgetURL(list.url)
        }
    }
}

/// The page as it lies on the Lock Screen: tasks from the top, the list's name below.
private struct LockScreenPage: View {
    let list: PageSnapshot.List
    /// Its eight hours are over and the app has not been opened since.
    let isOver: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(list.lines(PageActivityAttributes.lines)) { line in
                WidgetTask(line: line, size: 19, inActivity: true)
            }
            if list.lines.isEmpty {
                Text(PageSnapshot.emptyWords).font(.system(size: 19, design: .serif)).foregroundStyle(.inkFaded)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(list.name).font(.system(size: 13, design: .serif))
                Text("\(list.left)").font(.system(size: 9, design: .serif)).baselineOffset(5)
            }
            .foregroundStyle(.inkFaded)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .opacity(isOver ? 0.5 : 1)
    }
}
