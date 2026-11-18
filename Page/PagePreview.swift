import SwiftUI

/// A list's page as it looks at rest, shown beside the current page while it turns.
/// It is laid out like `TaskLines`, so the real page can take its place unseen.
struct PagePreview: View {
    let list: TaskList

    @Environment(\.pageMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.taskGap) {
            ForEach(list.liveTasks) { task in
                Text(task.text)
                    .typeStyle(.task)
                    .foregroundStyle(.ink)
                    .lineLimit(TaskLine.lineLimit)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fadesUnderListNames()
            }
        }
    }
}
