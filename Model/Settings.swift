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
    /// The page stays on the Lock Screen as a Live Activity during working
    /// hours. The hours themselves are kept by `WorkHours`.
    static let workHours = BoolSetting(key: "workHours", defaultValue: true)

    /// The first page has been finished or skipped (brief: First run).
    static let guideDone = BoolSetting(key: "guideDone", defaultValue: false)
    /// The Gestures line in settings has asked for the first page again.
    static let guideReplay = BoolSetting(key: "guideReplay", defaultValue: false)
}

struct BoolSetting: Sendable {
    let key: String
    let defaultValue: Bool
}
