import AppIntents
import SwiftUI
import WidgetKit

/// One task in a widget or the Live Activity: a single line, cut if it is
/// too long. A tap strikes it, and a second tap before it leaves undoes that.
/// A widget cannot follow a finger, so the pen line is drawn for the user.
struct WidgetTask: View {
    let line: PageSnapshot.Line
    var size: CGFloat = 17
    var ink: Color = .ink
    var faded: Color = .inkFaded
    /// On the Lock Screen's small widgets a tap opens the list instead.
    var strikes = true

    var body: some View {
        if strikes {
            Button(intent: StrikeTaskIntent(task: line.id)) { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }

    private var label: some View {
        Text(line.text)
            .font(.system(size: size, design: .serif))
            .foregroundStyle(line.isLive ? ink : faded)
            .lineLimit(1)
            // Task text can be hidden on a locked device, if the user asks for that.
            .privacySensitive()
            .overlay {
                if !line.isLive { WidgetStrike(seed: line.id.seed, size: size, ink: ink) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityLabel(line.text)
            .accessibilityValue(line.isLive ? "" : "Struck")
    }
}

/// The same pen line as in the app, over one line of text.
struct WidgetStrike: View {
    let seed: UInt64
    let size: CGFloat
    var ink: Color = .ink

    var body: some View {
        GeometryReader { proxy in
            let xHeight = size * 0.46
            let line = StrikeLine(
                minX: 0, maxX: proxy.size.width,
                // The middle of the lowercase letters sits a little under the middle of the line.
                midY: proxy.size.height * 0.56, xHeight: xHeight,
                halfWidth: size * 1.2 * 0.036
            )
            StrikePath.path(Stroke.generated(seed: seed), on: line).fill(ink.opacity(0.9))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension UUID {
    /// A seed that is the same every time, so a line is always struck the same way.
    var seed: UInt64 {
        withUnsafeBytes(of: uuid) { bytes in
            bytes.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
        }
    }
}

extension PageSnapshot.List {
    /// Opens this list in the app.
    var url: URL? { URL(string: "sansserif://list/\(id.uuidString)") }

    /// The list without the lines struck before `date`: they have left for the archive.
    func leaving(struckBefore date: Date) -> PageSnapshot.List {
        var list = self
        list.lines.removeAll { line in
            guard let struck = line.struck else { return false }
            return struck < date
        }
        return list
    }

    static let sample = PageSnapshot.List(
        id: UUID(),
        name: "work",
        lines: ["Reply to the printer", "Book the room", "Send the draft", "Order paper"].map {
            PageSnapshot.Line(id: UUID(), text: $0)
        },
        left: 4
    )
}
