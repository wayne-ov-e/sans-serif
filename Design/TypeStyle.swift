import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Text styles. Names match the text styles in the Figma file and the brief.
/// All text is New York through the system serif design; no font file is bundled.
enum TypeStyle {
    /// Tasks and settings lines.
    case task
    /// List names.
    case listName
    /// The words of a menu: what can be done with a held task or a held list
    /// name. A size below the list names, so they read as actions and not as
    /// more names (Wayne, Nov 18, 2026).
    case action
    /// Raised number after a list name.
    case count
    /// Archive month headings, italic.
    case monthLabel

    /// Line height as a multiple of the font size.
    static let lineHeightMultiple: CGFloat = 1.25

    func baseSize(in metrics: PageMetrics) -> CGFloat {
        switch self {
        case .task: metrics.taskSize
        case .listName: metrics.listNameSize
        case .action: metrics.listNameSize - 3
        case .count: metrics.countSize
        case .monthLabel: metrics.monthLabelSize
        }
    }

    var isItalic: Bool { self == .monthLabel }
}

extension View {
    /// Sets the font and the 125 percent line height for a type token.
    /// Sizes scale with the user's Dynamic Type setting.
    func typeStyle(_ style: TypeStyle) -> some View {
        modifier(TypeStyleModifier(style: style))
    }
}

private struct TypeStyleModifier: ViewModifier {
    let style: TypeStyle

    @Environment(\.pageMetrics) private var metrics

    // Dynamic Type multipliers, one per system text style the tokens map to.
    // Held as a percentage so the scaled value keeps its precision.
    @ScaledMetric(relativeTo: .title2) private var taskScale: CGFloat = 100
    @ScaledMetric(relativeTo: .title3) private var listNameScale: CGFloat = 100
    @ScaledMetric(relativeTo: .caption) private var countScale: CGFloat = 100
    @ScaledMetric(relativeTo: .callout) private var monthLabelScale: CGFloat = 100

    private var size: CGFloat {
        let scale: CGFloat = switch style {
        case .task: taskScale
        case .listName, .action: listNameScale
        case .count: countScale
        case .monthLabel: monthLabelScale
        }
        return (style.baseSize(in: metrics) * scale / 100).rounded()
    }

    func body(content: Content) -> some View {
        let size = size
        // SwiftUI has no line-height multiple before iOS 26, so add the
        // difference between 125 percent and the font's own line height.
        let extra = max(0, size * TypeStyle.lineHeightMultiple - SerifFont.lineHeight(size: size))
        content
            .font(.system(size: size, design: .serif))
            .italic(style.isItalic)
            .lineSpacing(extra)
            .padding(.vertical, extra / 2)
    }
}

enum SerifFont {
    /// Height of the lowercase letters as a fraction of ascent plus descent.
    static let xHeightRatio: CGFloat = {
        let size: CGFloat = 25
        #if canImport(UIKit)
        let base = UIFont.systemFont(ofSize: size)
        let descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        let font = UIFont(descriptor: descriptor, size: size)
        return font.xHeight / (font.ascender - font.descender)
        #elseif canImport(AppKit)
        let base = NSFont.systemFont(ofSize: size)
        let descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        let font = NSFont(descriptor: descriptor, size: size) ?? base
        return font.xHeight / (font.ascender - font.descender)
        #endif
    }()

    /// Natural line height of the system serif at a point size.
    static func lineHeight(size: CGFloat) -> CGFloat {
        #if canImport(UIKit)
        let base = UIFont.systemFont(ofSize: size)
        let descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: size).lineHeight
        #elseif canImport(AppKit)
        let base = NSFont.systemFont(ofSize: size)
        let descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        let font = NSFont(descriptor: descriptor, size: size) ?? base
        return font.ascender - font.descender + font.leading
        #endif
    }
}
