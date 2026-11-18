// Draws the app icon as quiet typography: the page's serif on paper, nothing loud.
// Run: swift docs/icon/icon.swift <lines|serif|letters|italic> <light|dark|tinted> out.png [size]
import AppKit
import CoreImage

let args = CommandLine.arguments
let concept = args.count > 1 ? args[1] : "letters"
let mode = args.count > 2 ? args[2] : "light"
let out = args.count > 3 ? args[3] : "icon.png"

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!
let g = NSGraphicsContext.current!.cgContext

func rgb(_ hex: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let dark = mode != "light"
// "dark-clear" is the dark icon as shipped: ink only, on a transparent ground.
let ink = dark ? rgb(mode == "tinted" ? 0xFFFFFF : 0xF4F1EA) : rgb(0x1C1B19)

// Paper, lit very softly from the top.
if mode == "tinted" || mode == "dark-clear" {
    // No ground of its own: the system puts its own behind the icon.
} else {
    let top = dark ? rgb(0x24231F) : rgb(0xF8F6F0)
    let bottom = dark ? rgb(0x171614) : rgb(0xEEEAE0)
    NSGradient(colors: [top, bottom])!.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)
}

func serif(_ points: CGFloat, _ weight: NSFont.Weight, italic: Bool = false) -> NSFont {
    let base = NSFont.systemFont(ofSize: points, weight: weight)
    var descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
    if italic { descriptor = descriptor.withSymbolicTraits(.italic) }
    return NSFont(descriptor: descriptor, size: points) ?? base
}

/// Draws text with its capitals centred on the icon, and returns its left edge, width and baseline.
@discardableResult
func centred(_ string: String, _ font: NSFont, color: NSColor, kern: CGFloat = 0, dy: CGFloat = 0) -> (CGFloat, CGFloat, CGFloat) {
    let text = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    let box = text.size()
    let left = (size - box.width + kern) / 2
    let lift = box.height + font.descender - font.ascender
    let baseline = (size - font.capHeight) / 2 + dy
    text.draw(at: NSPoint(x: left, y: baseline + font.descender - lift))
    return (left, box.width - kern, baseline)
}

func hairline(y: CGFloat, from x0: CGFloat, to x1: CGFloat, alpha: CGFloat, weight: CGFloat = 3) {
    ink.withAlphaComponent(alpha).setFill()
    NSRect(x: x0, y: y - weight / 2, width: x1 - x0, height: weight).fill()
}

switch concept {
case "lines":
    // A small page: two lines in the page's serif, set small with paper around
    // them. It says what it is: a stand-in until the app has a real icon.
    let font = serif(CGFloat(Double(args.count > 4 ? args[4] : "") ?? 84), .regular)
    let words = ["temporary", "logo"]
    let step = font.pointSize * 1.52
    let widest = words.map { NSAttributedString(string: $0, attributes: [.font: font]).size().width }.max() ?? 0
    // The block sits a little left of centre, as text on a page does, and is centred top to bottom.
    let left = (size - widest) / 2
    let blockHeight = font.xHeight + step * CGFloat(words.count - 1)
    let firstBaseline = (size + blockHeight) / 2 - font.xHeight
    for (index, word) in words.enumerated() {
        let text = NSAttributedString(string: word, attributes: [.font: font, .foregroundColor: ink, .kern: -font.pointSize * 0.01])
        let box = text.size()
        let lift = box.height + font.descender - font.ascender
        let baseline = firstBaseline - CGFloat(index) * step
        text.draw(at: NSPoint(x: left, y: baseline + font.descender - lift))
    }
case "letters":
    // "Aa" on its baseline and x-height, as a type specimen shows it. One fine
    // line runs through the lowercase: the only hint of what the app does.
    let font = serif(470, .regular)
    let (left, width, baseline) = centred("Aa", font, color: ink, kern: -6)
    hairline(y: baseline, from: 0, to: size, alpha: 0.14)
    hairline(y: baseline + font.capHeight, from: 0, to: size, alpha: 0.14)
    hairline(y: baseline + font.capHeight * 0.34, from: left - 46, to: left + width + 46, alpha: 0.9, weight: 7)
case "italic":
    // One letter, set large: the s of sans and of serif, in the italic.
    let font = serif(760, .regular, italic: true)
    centred("s", font, color: ink, dy: 96)
default:
    // A serif, close up: the foot of a letter, cropped by the edge of the icon.
    // Behind it the same letter recedes, blurred and faded the way the page
    // does in the app behind settings or a menu.
    let font = serif(1500, .medium)
    let baseline: CGFloat = 250
    func letter(dx: CGFloat, alpha: CGFloat) {
        let text = NSAttributedString(string: "I", attributes: [.font: font, .foregroundColor: ink.withAlphaComponent(alpha)])
        let box = text.size()
        text.draw(at: NSPoint(
            x: (size - box.width) / 2 + dx,
            y: baseline + font.descender - (box.height + font.descender - font.ascender)
        ))
    }
    /// Draws into a layer of its own, blurs it, and lays it on the icon.
    func receded(blur: CGFloat, _ draw: () -> Void) {
        let layer = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let main = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: layer)
        draw()
        NSGraphicsContext.current = main
        let input = CIImage(bitmapImageRep: layer)!
        let blurred = input.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blur])
            .cropped(to: input.extent)
        NSCIImageRep(ciImage: blurred).draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    }
    receded(blur: 34) { letter(dx: 300, alpha: 0.22) }
    receded(blur: 16) { letter(dx: 150, alpha: 0.42) }
    letter(dx: 0, alpha: 1)
    hairline(y: baseline, from: 0, to: size, alpha: 0.16)
}

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
