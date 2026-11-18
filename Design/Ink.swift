import SwiftUI

/// Colour tokens. Names match the variables in the Figma file and the brief.
/// Values live in Assets.xcassets so the launch screen and later
/// Dark paper / Increase Contrast variants can share them.
extension Color {
    /// Screen background. #F4F1EA
    static let paper = Color(.paper)
    /// Tasks, active list name, strikes. #1C1B19
    static let ink = Color(.ink)
    /// Struck tasks, inactive list names, archive text, month labels. #6F6A60
    static let inkFaded = Color(.inkFaded)
    /// Delete actions only. #8E2A1E
    static let inkRed = Color(.inkRed)
}

extension ShapeStyle where Self == Color {
    static var paper: Color { .paper }
    static var ink: Color { .ink }
    static var inkFaded: Color { .inkFaded }
    static var inkRed: Color { .inkRed }
}
