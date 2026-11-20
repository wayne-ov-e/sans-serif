import SwiftUI

/// A word at the bottom of the page that does one thing when tapped. "done"
/// stands where the list names were while the keyboard is up, and puts the pen down.
struct BottomWord: View {
    let word: String
    /// Ink for the thing to do next, faded italic for the way out.
    var isFaded = false
    let action: () -> Void

    @Environment(\.pageMetrics) private var metrics

    var body: some View {
        Button {
            // Felt as it is pressed (Wayne, Nov 20, 2026).
            Tap.word()
            action()
        } label: {
            Text(word)
                // A size below the list names: these are things to do, not places to go.
                .typeStyle(isFaded ? .monthLabel : .action)
                .foregroundStyle(isFaded ? .inkFaded : .ink)
                .frame(minWidth: metrics.minTouchHeight, minHeight: metrics.minTouchHeight, alignment: .leading)
                // The paper on either side belongs to the word, so it is easy to hit.
                .contentShape(Rectangle().inset(by: -metrics.listNameGap / 2))
        }
        .buttonStyle(.plain)
        .transition(.opacity)
    }
}
