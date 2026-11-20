import AppIntents
import SwiftUI
import WidgetKit

// MARK: Choosing the list

/// A list, as the widget's settings offer it.
struct ListEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "List"
    static let defaultQuery = ListQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ListQuery: EntityQuery {
    private var all: [ListEntity] {
        SharedPage.shared.snapshot.lists.map { ListEntity(id: $0.id.uuidString, name: $0.name) }
    }

    func entities(for identifiers: [String]) async throws -> [ListEntity] {
        all.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ListEntity] { all }

    func defaultResult() async -> ListEntity? { all.first }
}

/// Editing a widget lets the user pick the list it shows.
struct SelectListIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "List"
    static let description = IntentDescription("The list this widget shows.")

    @Parameter(title: "List")
    var list: ListEntity?
}

// MARK: Timeline

struct ListEntry: TimelineEntry {
    let date: Date
    let list: PageSnapshot.List?
}

struct ListProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ListEntry {
        ListEntry(date: .now, list: .sample)
    }

    func snapshot(for configuration: SelectListIntent, in context: Context) async -> ListEntry {
        if context.isPreview { return ListEntry(date: .now, list: .sample) }
        let now = Date.now
        let page = SharedPage.shared.timeline(at: now)
        return ListEntry(date: now, list: list(for: configuration, in: page.snapshot)?.shown(at: now, leaving: page.leaving))
    }

    func timeline(for configuration: SelectListIntent, in context: Context) async -> Timeline<ListEntry> {
        let now = Date.now
        let page = SharedPage.shared.timeline(at: now)
        guard let list = list(for: configuration, in: page.snapshot) else {
            return Timeline(entries: [ListEntry(date: now, list: nil)], policy: .never)
        }
        // Struck lines show struck from now, whenever they were struck, and
        // leave a moment later. Counting from the strike itself did not work:
        // the system draws a widget again some seconds after a tap, and by
        // then the moment was over and the line was gone without being seen.
        let leaves = Set(list.lines.compactMap { page.leaving[$0.id] }.filter { $0 > now })
        // And once more at the start of each day a repeat comes back, so it
        // is there that morning without the app being opened.
        let moments = ([now] + leaves.union(list.arrivals(after: now)).sorted())
        let entries = moments.map { ListEntry(date: $0, list: list.arriving(at: $0).shown(at: $0, leaving: page.leaving)) }
        // The app and a tap on a task ask for a new timeline. Nothing else changes it.
        return Timeline(entries: entries, policy: .never)
    }

    private func list(for configuration: SelectListIntent, in snapshot: PageSnapshot) -> PageSnapshot.List? {
        snapshot.list(configuration.list.flatMap { UUID(uuidString: $0.id) })
    }
}

// MARK: The widget

struct ListWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ListWidget", intent: SelectListIntent.self, provider: ListProvider()) { entry in
            ListWidgetView(entry: entry)
                .containerBackground(Color.paper, for: .widget)
        }
        .configurationDisplayName("List")
        .description("The next tasks of a list. Tap one to strike it.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular, .accessoryCircular, .accessoryInline,
        ])
    }
}

struct ListWidgetView: View {
    let entry: ListEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let list = entry.list {
            content(list).widgetURL(list.url)
        } else {
            // Before the app has been opened once there is nothing to show.
            Text("Open sans-serif")
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(.inkFaded)
        }
    }

    @ViewBuilder private func content(_ list: PageSnapshot.List) -> some View {
        switch family {
        case .accessoryInline:
            Text(list.next?.text ?? list.name).privacySensitive()
        case .accessoryCircular:
            // The number of tasks left, over the list's name.
            VStack(spacing: -2) {
                Text("\(list.left)").font(.system(size: 22, design: .serif))
                Text(list.name).font(.system(size: 10, design: .serif)).lineLimit(1)
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(list.left) left in \(list.name)")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                ForEach(list.lines(2)) { line in
                    WidgetTask(line: line, size: 15, ink: .primary, faded: .secondary)
                }
                if list.lines.isEmpty { name(list, size: 15) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .systemLarge:
            page(list, lines: 8, size: 20, gap: 10)
        case .systemMedium:
            page(list, lines: 3, size: 19, gap: 7)
        default:
            page(list, lines: 3, size: 17, gap: 6)
        }
    }

    /// As in the app: the tasks from the top, and the list's name at the bottom.
    private func page(_ list: PageSnapshot.List, lines: Int, size: CGFloat, gap: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: gap) {
            ForEach(list.lines(lines)) { line in
                WidgetTask(line: line, size: size)
            }
            Spacer(minLength: 0)
            name(list, size: 13)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func name(_ list: PageSnapshot.List, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(list.name).font(.system(size: size, design: .serif))
            Text("\(list.left)").font(.system(size: size * 0.7, design: .serif)).baselineOffset(size * 0.35)
        }
        .foregroundStyle(.inkFaded)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(list.name), \(list.left) left")
    }
}
