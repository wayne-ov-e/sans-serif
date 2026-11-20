import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The picture that goes with a shared list's link: what Messages, Mail and
/// the share sheet show beside it, and what the person invited sees before
/// they join. A square of the app's paper with the list's name written on it
/// and circled, the way the task that matters is circled on the page.
///
/// Only the name is on it. Whoever is given the link sees this before they
/// have joined, so nothing of what is written on the list is shown.
struct ShareCard: View {
    let name: String

    /// The card is drawn at this size, in points, and twice that in pixels.
    static let side: CGFloat = 400

    /// Paper between the name and the loop round it, and from the card's edge to the loop.
    private static let loopPad = CGSize(width: 34, height: 30)
    private static let edge: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Text(name)
                .font(.system(size: Self.nameSize(for: name), design: .serif))
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.4)
                .multilineTextAlignment(.leading)
                // Narrow enough that the loop round it stays on the card.
                .frame(width: Self.nameWidth(for: name), alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Self.loopPad.width)
                .padding(.vertical, Self.loopPad.height)
                .background { Loop().stroke(Color.ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)) }
            Text("a shared list")
                .font(.system(size: 22, design: .serif))
                .italic()
                .foregroundStyle(Color.inkFaded)
                .padding(.leading, Self.loopPad.width)
                .padding(.top, 18)
            Spacer(minLength: 0)
            Text("sans-serif")
                .font(.system(size: 20, design: .serif))
                .foregroundStyle(Color.inkFaded)
                .padding(.leading, Self.loopPad.width)
                .padding(.bottom, 36)
        }
        .padding(.leading, Self.edge)
        .frame(width: Self.side, height: Self.side, alignment: .leading)
        .background(Color.paper)
        // The same paper wherever the link is opened, light or dark.
        .environment(\.colorScheme, .light)
    }

    /// Short names are written large. Long ones are written smaller, and then
    /// on two lines.
    static func nameSize(for name: String) -> CGFloat {
        switch name.count {
        case ...6: 84
        case ...10: 64
        case ...16: 48
        default: 38
        }
    }

    /// As wide as the name is when written on one line, and no wider than
    /// leaves the loop on the card: the loop fits the name, short or long.
    static func nameWidth(for name: String) -> CGFloat {
        let size = nameSize(for: name)
        #if canImport(UIKit)
        let base = UIFont.systemFont(ofSize: size)
        let font = UIFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: size)
        #elseif canImport(AppKit)
        let base = NSFont.systemFont(ofSize: size)
        let font = NSFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: size) ?? base
        #endif
        let natural = (name as NSString).size(withAttributes: [.font: font]).width
        return min(max(natural.rounded(.up) + 2, 40), 250)
    }

    /// The card as a picture, for the link. Nothing if it cannot be drawn.
    @MainActor static func png(named name: String) -> Data? {
        let renderer = ImageRenderer(content: ShareCard(name: name))
        renderer.scale = 2
        renderer.isOpaque = true
        #if canImport(UIKit)
        return renderer.uiImage?.pngData()
        #elseif canImport(AppKit)
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
        #endif
    }

    /// The same picture for the share sheet's own heading.
    @MainActor static func image(named name: String) -> Image {
        let renderer = ImageRenderer(content: ShareCard(name: name))
        renderer.scale = 2
        renderer.isOpaque = true
        #if canImport(UIKit)
        if let image = renderer.uiImage { return Image(uiImage: image) }
        #elseif canImport(AppKit)
        if let image = renderer.nsImage { return Image(nsImage: image) }
        #endif
        return Image(systemName: "list.bullet")
    }
}

/// A loop drawn round the name by hand: not quite an ellipse, begun a little
/// to the left of the top and carried on a little past where it began.
private struct Loop: Shape {
    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        // Inside the room left round the name, with a little kept back for
        // the drift outward: the loop never runs off the card.
        let a = rect.width / 2 * 0.95
        let b = rect.height / 2 * 0.95
        var path = Path()
        let start = -110.0
        let sweep = 392.0
        let steps = 96
        for step in 0...steps {
            let turn = Double(step) / Double(steps)
            let angle = (start + sweep * turn) * .pi / 180
            // The hand drifts outward as it goes round, so the end passes outside the beginning.
            let drift = 1 + 0.05 * turn
            // And wobbles a little.
            let wobble = 1 + 0.018 * sin(angle * 3 + 0.6)
            let point = CGPoint(
                x: centre.x + cos(angle) * a * drift * wobble,
                y: centre.y + sin(angle) * b * drift * wobble
            )
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

#if DEBUG
#Preview {
    VStack {
        ShareCard(name: "life")
        ShareCard(name: "Groceries for the cabin")
    }
}
#endif
