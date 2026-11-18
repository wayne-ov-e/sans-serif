import XCTest

/// Walks the app the way a new user does: the first page from its first line to
/// begin, then the things the first page taught, on the real page. It fails if
/// the app stops at any point, which is what build 5 did after the first page.
@MainActor
final class WalkthroughTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // An empty store and settings as on a first launch, so the first page shows.
        app.launchArguments = ["-inMemoryStore"]
        app.launch()
    }

    func testTheFirstPageAndThenThePage() {
        // Cross me off.
        drag(acrossLine: "Cross me off.")

        // Tap below and write your own.
        wait(for: "Tap below and write your own.")
        point(0.5, 0.6).tap()
        // The guide marks on the first page keep playing, so the app is never idle here.
        type("Buy milk", inOneBurst: true)
        app.buttons["done"].tap()
        wait(for: "Buy milk")

        // Hold a line for more.
        wait(for: "Hold a line for more.")
        line("Hold a line for more.").press(forDuration: 1)
        XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout: 3), "holding a line opens its menu")
        app.buttons["Copy"].tap()

        // Swipe along the bottom for the next list.
        wait(for: "Swipe along the bottom for the next list.")
        drag(from: (0.8, 0.92), to: (0.2, 0.92))

        // Pull up for what is done, and come back.
        wait(for: "Pull up for what is done.")
        drag(from: (0.5, 0.7), to: (0.5, 0.45))
        drag(from: (0.5, 0.45), to: (0.5, 0.7))

        // Pull down for settings, and put them away.
        wait(for: "Pull down for settings.")
        drag(from: (0.5, 0.5), to: (0.5, 0.75))
        wait(for: "Show counts")
        drag(from: (0.5, 0.7), to: (0.5, 0.58))

        // That is all.
        XCTAssertTrue(app.buttons["begin"].waitForExistence(timeout: 5), "every step done shows begin")
        app.buttons["begin"].tap()

        // The page: the lists, and the task written on the first page.
        XCTAssertTrue(app.buttons["life"].waitForExistence(timeout: 5), "begin leads to the first list")
        XCTAssertTrue(app.buttons["Buy milk"].exists, "the user's own task is carried over")
        XCTAssertEqual(app.state, .runningForeground)

        // Add a second task.
        point(0.5, 0.6).tap()
        type("Call the framer")
        app.buttons["done"].tap()
        XCTAssertTrue(app.buttons["Call the framer"].waitForExistence(timeout: 3))

        // Strike the first. It leaves the page after its hold.
        drag(acrossLine: "Buy milk")
        XCTAssertTrue(gone(app.buttons["Buy milk"]), "a struck task leaves the page")

        // It is in the archive, with the lines of the first page.
        drag(from: (0.5, 0.7), to: (0.5, 0.45))
        wait(for: "Buy milk")
        wait(for: "Cross me off.")
        drag(from: (0.5, 0.45), to: (0.5, 0.7))
        XCTAssertTrue(app.buttons["Call the framer"].waitForExistence(timeout: 3), "pulling down leaves the archive")

        // Turn to the next list from the bottom of the page, and back by its name.
        drag(from: (0.8, 0.92), to: (0.2, 0.92))
        XCTAssertTrue(gone(app.buttons["Call the framer"]), "the page turned to the next list")
        app.buttons["life"].tap()
        XCTAssertTrue(app.buttons["Call the framer"].waitForExistence(timeout: 3))

        // A swipe higher up the page does not turn it.
        drag(from: (0.8, 0.5), to: (0.2, 0.5))
        XCTAssertTrue(app.buttons["Call the framer"].exists, "only the bottom of the page turns it")

        // Settings: a tap turns a line off, and the Gestures line plays the first page again.
        drag(from: (0.5, 0.5), to: (0.5, 0.75))
        wait(for: "Haptics")
        line("Haptics").tap()
        line("Gestures").tap()
        wait(for: "Cross me off.")
        app.buttons["skip"].tap()
        XCTAssertTrue(app.buttons["life"].waitForExistence(timeout: 5), "skip leads back to the page")

        XCTAssertEqual(app.state, .runningForeground, "the app is still running at the end")
    }

    /// The way past the first page, and the things a held line and a held name can do.
    func testSkipThenWritingMenusAndSettings() {
        XCTAssertTrue(app.buttons["skip"].waitForExistence(timeout: 6))
        app.buttons["skip"].tap()
        XCTAssertTrue(app.buttons["life"].waitForExistence(timeout: 5), "skip leads to the first list")

        // Three tasks, one after another: Return keeps the pen down.
        point(0.5, 0.5).tap()
        for task in ["First\n", "Second\n", "Third"] {
            type(task)
            // A person pauses after Return. The pen is picked up again in that time.
            Thread.sleep(forTimeInterval: 0.4)
        }
        app.buttons["done"].tap()
        for task in ["First", "Second", "Third"] {
            XCTAssertTrue(app.buttons[task].waitForExistence(timeout: 3), "\(task) is on the page")
        }
        // "done" has made way for the list names again.
        XCTAssertTrue(app.buttons["life"].waitForExistence(timeout: 3))

        // A tap on a task edits it in place.
        // The keyboard is still going down and the list names coming back.
        Thread.sleep(forTimeInterval: 0.8)
        // On the words themselves: the paper beside a short task starts a new one.
        app.buttons["Second"].coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        type(" thing", inOneBurst: true)
        app.buttons["done"].tap()
        XCTAssertTrue(app.buttons["Second thing"].waitForExistence(timeout: 3), "an edit is kept")

        // Hold a task: its menu opens. Delete removes it.
        app.buttons["First"].coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3), "holding a task opens its menu")
        XCTAssertTrue(app.buttons["Move to"].exists)
        XCTAssertFalse(app.buttons["Edit"].exists, "Edit is not in the menu")
        app.buttons["Delete"].tap()
        XCTAssertTrue(gone(app.buttons["First"]), "Delete removes the task")

        // Move to: the task goes to the other list.
        app.buttons["Third"].coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Move to"].waitForExistence(timeout: 3))
        app.buttons["Move to"].tap()
        XCTAssertTrue(app.buttons["work"].firstMatch.waitForExistence(timeout: 3))
        // The menu's line for the list, not the list name at the bottom of the page.
        let targets = app.buttons.matching(identifier: "work").allElementsBoundByIndex
        targets.min { $0.frame.minY < $1.frame.minY }?.tap()
        XCTAssertTrue(gone(app.buttons["Third"]), "a moved task leaves this list")

        // Strike and undo: drag across, then back while it is still on the page.
        let y = app.buttons["Second thing"].frame.midY / app.frame.height
        drag(from: (0.12, y), to: (0.9, y), settle: 0.1)
        drag(from: (0.7, y), to: (0.1, y))
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertTrue(app.buttons["Second thing"].exists, "a strike undone stays on the page")

        // Hold a list name: Rename and Delete list. A tap on the page puts the menu away.
        app.buttons["home"].press(forDuration: 1)
        XCTAssertTrue(app.buttons["Rename"].waitForExistence(timeout: 3), "holding a list name opens its menu")
        XCTAssertTrue(app.buttons["Delete list"].exists)
        point(0.5, 0.4).tap()
        XCTAssertTrue(gone(app.buttons["Rename"]), "a tap on the page puts the menu away")

        // Settings come down, each line turns off and on with a tap, and a tap on the page puts them away.
        drag(from: (0.5, 0.5), to: (0.5, 0.75))
        for name in ["Show counts", "iCloud sync", "Haptics", "Dark paper"] {
            wait(for: name)
            line(name).tap()
            line(name).tap()
        }
        // Work hours: struck and back like the others, and each hour changes where it stands.
        wait(for: "Work hours")
        line("Work hours").tap()
        XCTAssertTrue(gone(first("Ends")), "struck, the hours are put away")
        line("Work hours").tap()
        wait(for: "Ends")
        let end = line("Ends").value as? String
        // A tap brings up the number keys, and one key is enough for most hours.
        line("Ends").tap()
        type("7")
        wait(for: "Ends")
        XCTAssertNotEqual(line("Ends").value as? String, end, "a typed number becomes the hour")
        XCTAssertEqual(line("Ends").value as? String, WorkHours7PM.name, "7 after a morning start is 7 in the evening")
        // AM and PM stand above the keys while an hour is typed.
        line("Starts").tap()
        XCTAssertTrue(app.buttons[Calendar.current.pmSymbol].waitForExistence(timeout: 3), "PM is above the keys")
        app.buttons[Calendar.current.amSymbol].tap()
        type("6")
        wait(for: "Starts")
        line("Ends").tap()
        XCTAssertTrue(app.buttons[Calendar.current.amSymbol].waitForExistence(timeout: 3))
        app.buttons[Calendar.current.amSymbol].tap()
        app.buttons["done"].tap()
        wait(for: "Ends")
        XCTAssertEqual(line("Ends").value as? String, WorkHours7AM.name, "AM moves 7 PM to 7 AM")

        let start = line("Starts").value as? String
        let word = line("Starts").coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        word.press(forDuration: 0.05, thenDragTo: word.withOffset(CGVector(dx: -60, dy: 0)))
        XCTAssertNotEqual(line("Starts").value as? String, start, "a drag across an hour runs through the hours")

        point(0.5, 0.85).tap()
        XCTAssertTrue(gone(first("Show counts")), "a tap on the page puts settings away")

        XCTAssertEqual(app.state, .runningForeground, "the app is still running at the end")
    }

    /// One drag does one thing. A long drag that puts settings away must not go
    /// on to open the archive, and the next drag down must bring settings back.
    func testADragThatClosesOneSheetDoesNotOpenAnother() {
        XCTAssertTrue(app.buttons["skip"].waitForExistence(timeout: 6))
        app.buttons["skip"].tap()
        XCTAssertTrue(app.buttons["life"].waitForExistence(timeout: 5))
        point(0.5, 0.5).tap()
        type("Stay here")
        app.buttons["done"].tap()
        XCTAssertTrue(app.buttons["Stay here"].waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.8)
        let month = Date.now.formatted(.dateTime.month(.wide).year())

        for round in 1...3 {
            // Settings down, then one long drag up: far more than it takes to put them away.
            drag(from: (0.5, 0.4), to: (0.5, 0.65))
            wait(for: "Show counts")
            drag(from: (0.5, 0.75), to: (0.5, 0.25))
            XCTAssertTrue(gone(first("Show counts")), "round \(round): the drag up puts settings away")
            XCTAssertFalse(first(month).exists, "round \(round): the same drag does not open the archive")
            XCTAssertTrue(app.buttons["Stay here"].exists, "round \(round): the page is showing")

            // A quick flick up to close them is one drag as well.
            drag(from: (0.5, 0.4), to: (0.5, 0.65))
            wait(for: "Show counts")
            point(0.5, 0.7).press(forDuration: 0.02, thenDragTo: point(0.5, 0.45), withVelocity: .fast, thenHoldForDuration: 0)
            Thread.sleep(forTimeInterval: 0.8)
            XCTAssertTrue(gone(first("Show counts")), "round \(round): a flick up puts settings away")
            XCTAssertFalse(first(month).exists, "round \(round): a flick does not open the archive")
        }

        // The archive and back, then straight down again: settings, not the archive.
        app.buttons["Stay here"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 0.3)
        if app.buttons["done"].exists { app.buttons["done"].tap() }
        Thread.sleep(forTimeInterval: 0.8)
        drag(from: (0.5, 0.7), to: (0.5, 0.45))
        drag(from: (0.5, 0.45), to: (0.5, 0.7))
        XCTAssertTrue(app.buttons["Stay here"].waitForExistence(timeout: 3), "back on the page from the archive")
        drag(from: (0.5, 0.4), to: (0.5, 0.65))
        wait(for: "Show counts")
        XCTAssertFalse(first(month).exists, "a pull down from the page shows settings, not the archive")

        XCTAssertEqual(app.state, .runningForeground)
    }

    /// A held line offers its menu and can still be carried by the same finger.
    /// List names tapped one after another each turn the page.
    func testAHeldLineIsCarriedAndNamesTurnQuickly() {
        XCTAssertTrue(app.buttons["skip"].waitForExistence(timeout: 6))
        app.buttons["skip"].tap()
        XCTAssertTrue(app.buttons["life"].waitForExistence(timeout: 5))
        point(0.5, 0.5).tap()
        for task in ["One\n", "Two"] {
            type(task)
            // The pen is picked up again after Return. Keys pressed before that are lost.
            Thread.sleep(forTimeInterval: 1)
        }
        app.buttons["done"].tap()
        XCTAssertTrue(app.buttons["Two"].waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertLessThan(app.buttons["One"].frame.minY, app.buttons["Two"].frame.minY)

        // Held long enough for the menu to open, then moved: the menu makes way
        // and the line goes where the finger takes it.
        let one = app.buttons["One"].coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
        let belowTwo = app.buttons["Two"].coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 2.2))
        one.press(forDuration: 1.2, thenDragTo: belowTwo, withVelocity: .slow, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertFalse(app.buttons["Delete"].exists, "carrying a held line puts its menu away")
        XCTAssertGreaterThan(app.buttons["One"].frame.minY, app.buttons["Two"].frame.minY, "the held line was carried below")

        // Held and let go without moving: the menu stays.
        app.buttons["One"].coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3), "a line held still keeps its menu")
        point(0.5, 0.6).tap()
        XCTAssertTrue(gone(app.buttons["Delete"]))

        // Names tapped one after another, without waiting for the page.
        for round in 1...3 {
            app.buttons["work"].tap()
            app.buttons["home"].tap()
            XCTAssertTrue(gone(app.buttons["One"]), "round \(round): the page has turned away from life")
            app.buttons["work"].tap()
            app.buttons["life"].tap()
            XCTAssertTrue(app.buttons["One"].waitForExistence(timeout: 3), "round \(round): and back to life")
        }
        // Hold a list name: New list. The name is written after the last, and the page turns to it.
        app.buttons["home"].press(forDuration: 1)
        XCTAssertTrue(app.buttons["New list"].waitForExistence(timeout: 3), "the list menu offers a new list")
        app.buttons["New list"].tap()
        type("trips\n")
        XCTAssertTrue(app.buttons["trips"].waitForExistence(timeout: 3), "the new list is among the names")
        XCTAssertTrue(gone(app.buttons["One"]), "the page has turned to the new list")
        XCTAssertTrue(app.buttons["trips"].isSelected, "the new list is the one open")
        // Left blank, no list is added.
        app.buttons["trips"].press(forDuration: 1)
        app.buttons["New list"].tap()
        type("\n")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label IN %@", ["life", "work", "home", "trips"])).count, 4)
        app.buttons["life"].tap()
        XCTAssertTrue(app.buttons["One"].waitForExistence(timeout: 3), "and the first list is still a tap away")
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: Helpers

    private enum WorkHours7AM {
        static var name: String {
            (Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now) ?? .now).formatted(.dateTime.hour())
        }
    }

    /// Seven in the evening, as this device writes hours.
    private enum WorkHours7PM {
        static var name: String {
            (Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: .now) ?? .now).formatted(.dateTime.hour())
        }
    }

    /// The first thing on the page that reads as `label`. Quick, for asking whether it is there.
    private func first(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Types once the keyboard is up. Keys pressed while it is still rising are lost.
    private func type(_ text: String, inOneBurst: Bool = false) {
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the keyboard should be up")
        Thread.sleep(forTimeInterval: 0.4)
        // One key at a time, as a person types. Sent as one burst, the last
        // key was sometimes lost and "Two" was kept as "Tw".
        // While a task is edited in place the app never reports its animations
        // as finished, and each call waits a minute for that. There, one call.
        guard !inOneBurst else {
            app.typeText(text)
            return
        }
        for character in text {
            app.typeText(String(character))
        }
    }

    /// Anything on the page that reads as `label`.
    /// A container can read as its only line, so of everything with the label
    /// the smallest is taken: that is the line itself.
    private func line(_ label: String) -> XCUIElement {
        let query = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label))
        let all = query.allElementsBoundByIndex
        return all.min { $0.frame.height < $1.frame.height } ?? query.firstMatch
    }

    private func wait(for label: String, file: StaticString = #filePath, line number: UInt = #line) {
        let query = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label))
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 6), "\"\(label)\" should be on the page",
                      file: file, line: number)
    }

    private func gone(_ element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: 6) == .completed
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    private func drag(from start: (CGFloat, CGFloat), to end: (CGFloat, CGFloat), settle: TimeInterval = 0.6) {
        point(start.0, start.1).press(
            forDuration: 0.05, thenDragTo: point(end.0, end.1), withVelocity: .default, thenHoldForDuration: 0.15
        )
        // Let the page settle before the next step.
        Thread.sleep(forTimeInterval: settle)
    }

    /// Drags from the left margin across the text of a line, as a strike does.
    private func drag(acrossLine label: String) {
        wait(for: label)
        let target = line(label)
        let y = target.frame.midY / app.frame.height
        drag(from: (0.12, y), to: (0.9, y))
    }
}
