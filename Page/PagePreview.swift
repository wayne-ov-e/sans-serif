import SwiftUI

/// A list's page as it looks at rest, shown beside the current page while it turns.
/// It is laid out like `TaskLines`, so the real page can take its place unseen.
struct PagePreview: View {
    let list: TaskList

    @Environment(\.pageMetrics) private var metrics

    /// More than the tallest window shows at the smallest type.
    static let linesShown = 40

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.taskGap) {
            // Only what a screen can show. These pages stand off the edge of the
            // paper at all times, one for every other list, so a long list must
            // not cost its whole length there.
            ForEach(list.liveTasks.prefix(Self.linesShown)) { task in
                // With its small word if it repeats and its loop if it is
                // circled: they are there as the page comes in, not added once
                // it has landed (Wayne, Nov 20, 2026).
                TaskLine.words(of: task, metrics: metrics)
                    .typeStyle(.task)
                    .foregroundStyle(.ink)
                    .lineLimit(TaskLine.lineLimit)
                    .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
                        if task.isCircled {
                            GeometryReader { proxy in
                                CircleMark(lines: StrikeLine.measure(layouts, in: proxy), seed: task.id.loopSeed, progress: 1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fadesUnderListNames()
            }
        }
    }
}
