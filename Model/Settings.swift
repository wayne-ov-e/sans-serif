import Foundation

/// The four settings (brief: Decisions made). Stored per device in UserDefaults
/// and read with `@AppStorage`. Whether they follow the user across devices is
/// an open question in the brief.
enum Setting {
    /// The small raised number after each list name.
    static let showCounts = BoolSetting(key: "showCounts", defaultValue: true)
    static let iCloudSync = BoolSetting(key: "iCloudSync", defaultValue: true)
    static let haptics = BoolSetting(key: "haptics", defaultValue: true)
    static let darkPaper = BoolSetting(key: "darkPaper", defaultValue: true)

    /// The first page has been finished or skipped (brief: First run).
    static let guideDone = BoolSetting(key: "guideDone", defaultValue: false)
    /// The Gestures line in settings has asked for the first page again.
    static let guideReplay = BoolSetting(key: "guideReplay", defaultValue: false)
}

struct BoolSetting: Sendable {
    let key: String
    let defaultValue: Bool
}

/// Where the two small words at the foot of settings lead (App Store 5.1.1(i)
/// and 1.5): the privacy policy, and a way to reach the developer. Each word
/// shows only once it has somewhere to go.
enum AppLinks {
    /// The published privacy policy. Not set yet: Wayne has to give its address.
    static let privacy: URL? = nil
    /// A page or a mailto: address for writing to the developer. Not set yet.
    static let contact: URL? = nil

    /// The words to show, in order. `-previewLinks` shows both with stand-in
    /// addresses, to see them before the real ones are given.
    static var shown: [(word: String, url: URL)] {
        var privacy = privacy, contact = contact
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-previewLinks") {
            privacy = URL(string: "https://example.com/privacy")
            contact = URL(string: "https://example.com/contact")
        }
        #endif
        return [("Privacy", privacy), ("Contact", contact)].compactMap { pair in
            pair.1.map { (pair.0, $0) }
        }
    }
}
