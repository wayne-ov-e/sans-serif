import XCTest

/// The walks the other file leaves out, at the edges of the app: nothing
/// written, long words, the count beside a list name, every task struck, the
/// ends of the row of lists, an empty archive, and the last list of all.
@MainActor
final class EdgeWalkTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // An empty store and settings as on a first launch.
        app.launchArguments = ["-inMemoryStore"]
        app.launch()
    }

    /// Blank lines are not kept, long ones are, and the count beside the list
    /// name follows what is written and struck, and can be put away.
    func testBlankAndLongTasksAndTheCountBesideTheName() {
        skipTheFirstPage()
        XCTAssertEqual(app.buttons["life"].value as? String, "0 left", "an empty list has nothing left")

        // Only spaces: nothing is kept.
        point(0.5, 0.5).tap()
        type("   ")
        app.buttons["done"].tap()
        XCTAssertTrue(app.buttons["life"].waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertEqual(app.buttons["life"].value as? String, "0 left", "a blank line is not a task")

        // Return on an empty line puts the pen down without leaving a task.
        point(0.5, 0.5).tap()
        type("\n")
        if app.buttons["done"].waitForExistence(timeout: 1) { app.buttons["done"].tap() }
        XCTAssertTrue(app.buttons["life"].waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertEqual(app.buttons["life"].value as? String, "0 left")

        // A task longer than the page is wide, and a short one after it.
        let long = "Write to the printer about the proofs before the end of the week"
        point(0.5, 0.5).tap()
        type(long + "\n")
        Thread.sleep(forTimeInterval: 1)
        type("Cafe")
        app.buttons["done"].tap()
        XCTAssertTrue(app.buttons[long].waitForExistence(timeout: 3), "a long task is kept whole")
        XCTAssertTrue(app.buttons["Cafe"].waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertGreaterThan(
            app.buttons[long].frame.height, app.buttons["Cafe"].frame.height * 1.5, "and wraps to more than one line"
        )
        XCTAssertLessThanOrEqual(app.buttons[long].frame.maxX, app.frame.width, "inside the page")
        XCTAssertLessThan(app.buttons[long].frame.maxY, app.buttons["Cafe"].frame.minY, "the next task is below it")
        XCTAssertEqual(app.buttons["life"].value as? String, "2 left")
        XCTAssertEqual(app.buttons["work"].value as? String, "0 left", "another list's count is its own")

        // Struck, a task is no longer counted. With both struck the page is empty.
        drag(acrossLine: "Cafe")
        XCTAssertTrue(gone(app.buttons["Cafe"]), "a struck task leaves the page")
        XCTAssertEqual(app.buttons["life"].value as? String, "1 left")
        drag(acrossLine: long)
        XCTAssertTrue(gone(app.buttons[long]), "a struck task of several lines leaves the page too")
        XCTAssertEqual(app.buttons["life"].value as? String, "0 left")

        // Both are in the archive, under today.
        drag(from: (0.5, 0.7), to: (0.5, 0.45))
        wait(for: "Done today")
        wait(for: "Cafe")
        wait(for: long)
        XCTAssertFalse(first("Nothing so far.").exists)
        drag(from: (0.5, 0.45), to: (0.5, 0.7))
        XCTAssertTrue(gone(first("Done today")), "pulling down leaves the archive")

        // With counts put away, a list name says nothing about what is left.
        drag(from: (0.5, 0.4), to: (0.5, 0.65))
        wait(for: "Show counts")
        line("Show counts").tap()
        point(0.5, 0.85).tap()
        XCTAssertTrue(gone(first("Show counts")))
        XCTAssertEqual(app.buttons["life"].value as? String ?? "", "", "no count is read out")
        drag(from: (0.5, 0.4), to: (0.5, 0.65))
        wait(for: "Show counts")
        line("Show counts").tap()
        point(0.5, 0.85).tap()
        XCTAssertTrue(gone(first("Show counts")))
        XCTAssertEqual(app.buttons["life"].value as? String, "0 left", "and brought back, it is")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// The row of lists does not go round: a swipe past either end stays where
    /// it is. An empty archive says so. The last list cannot be deleted.
    func testTheEndsOfTheRowTheEmptyArchiveAndTheLastList() {
        skipTheFirstPage()
        point(0.5, 0.5).tap()
        type("Only in life")
        app.buttons["done"].tap()
        XCTAssertTrue(app.buttons["Only in life"].waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 1.2)

        // Along the bottom, one list at a time, and no further than the last.
        let names = app.buttons["life"].frame.midY / app.frame.height
        XCTAssertTrue(app.buttons["life"].isSelected)
        drag(from: (0.8, names), to: (0.2, names))
        XCTAssertTrue(selected("work"), "a swipe along the bottom turns to the next list")
        XCTAssertTrue(gone(app.buttons["Only in life"]))
        drag(from: (0.8, names), to: (0.2, names))
        XCTAssertTrue(selected("home"))
        drag(from: (0.8, names), to: (0.2, names))
        XCTAssertTrue(selected("home"), "past the last list there is nothing to turn to")
        XCTAssertFalse(app.buttons["life"].isSelected, "and the row does not go round to the first")

        // An empty list has an empty archive, and says so.
        drag(from: (0.5, 0.7), to: (0.5, 0.45))
        wait(for: "Nothing so far.")
        XCTAssertFalse(first("Done today").exists)
        drag(from: (0.5, 0.45), to: (0.5, 0.7))
        XCTAssertTrue(gone(first("Nothing so far.")))

        // Back the other way, and no further than the first.
        for expected in ["work", "life", "life"] {
            drag(from: (0.2, names), to: (0.8, names))
            XCTAssertTrue(selected(expected), "a swipe back turns to \(expected)")
        }
        XCTAssertTrue(app.buttons["Only in life"].waitForExistence(timeout: 3), "the first list still has its task")

        // Copy leaves the task where it is.
        app.buttons["Only in life"].coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout: 3), "the task menu offers a copy")
        app.buttons["Copy"].tap()
        XCTAssertTrue(gone(app.buttons["Copy"]), "the menu is put away")
        XCTAssertTrue(app.buttons["Only in life"].exists)

        // Delete the list that is open: the page turns to one that is left.
        app.buttons["life"].press(forDuration: 1)
        XCTAssertTrue(app.buttons["Delete list"].waitForExistence(timeout: 3))
        app.buttons["Delete list"].tap()
        XCTAssertTrue(app.buttons["Keep"].firstMatch.waitForExistence(timeout: 3))
        // Keep changes nothing.
        app.buttons["Keep"].firstMatch.tap()
        XCTAssertTrue(gone(app.buttons["Yes, delete"]))
        XCTAssertTrue(app.buttons["life"].exists)
        XCTAssertTrue(app.buttons["Only in life"].exists)

        app.buttons["life"].press(forDuration: 1)
        XCTAssertTrue(app.buttons["Delete list"].waitForExistence(timeout: 3))
        app.buttons["Delete list"].tap()
        XCTAssertTrue(app.buttons["Yes, delete"].waitForExistence(timeout: 3))
        app.buttons["Yes, delete"].tap()
        XCTAssertTrue(gone(app.buttons["life"]), "the open list is gone")
        XCTAssertTrue(gone(app.buttons["Only in life"]), "and its task with it")
        XCTAssertTrue(app.buttons["work"].waitForExistence(timeout: 3))
        XCTAssertTrue(selected("work") || selected("home"), "the page has turned to a list that is left")

        app.buttons["home"].press(forDuration: 1)
        XCTAssertTrue(app.buttons["Delete list"].waitForExistence(timeout: 3))
        app.buttons["Delete list"].tap()
        XCTAssertTrue(app.buttons["Yes, delete"].waitForExistence(timeout: 3))
        app.buttons["Yes, delete"].tap()
        XCTAssertTrue(gone(app.buttons["home"]))

        // One list left: it can be renamed, and not deleted.
        XCTAssertTrue(selected("work"))
        app.buttons["work"].press(forDuration: 1)
        XCTAssertTrue(app.buttons["Rename"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["New list"].exists)
        XCTAssertFalse(app.buttons["Delete list"].exists, "the last list cannot be deleted")
        point(0.5, 0.4).tap()
        XCTAssertTrue(gone(app.buttons["Rename"]))

        // With one list, a swipe along the bottom has nowhere to go, and the page still works.
        drag(from: (0.8, names), to: (0.2, names))
        drag(from: (0.2, names), to: (0.8, names))
        XCTAssertTrue(selected("work"))
        point(0.5, 0.5).tap()
        type("Still writing")
        app.buttons["done"].tap()
        XCTAssertTrue(app.buttons["Still writing"].waitForExistence(timeout: 3), "the last list takes tasks as before")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// The lines for sharing a list, with sample people in place of iCloud:
    /// the user's name is typed and kept, a link is made, and stopping asks first.
    func testTheShareLinesAndTheUsersOwnName() {
        app.terminate()
        app.launchArguments = ["-inMemoryStore", "-previewShare"]
        app.launch()
        skipTheFirstPage()

        app.buttons["life"].press(forDuration: 1)
        XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 3), "the list menu offers sharing")
        app.buttons["Share"].tap()
        wait(for: "Make a link")
        XCTAssertFalse(first("Share life").exists, "there is no heading")
        XCTAssertFalse(first("Show counts").exists, "these are not the settings")
        // The user's own line is there before there is a link, and is where
        // their name is typed. There is no line apart for it.
        XCTAssertFalse(first("you are").exists)
        XCTAssertEqual(line("Your name").value as? String, "Wayne Xu", "iCloud's name is there to begin with")
        line("Your name").tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        for _ in 0..<8 { app.typeText(XCUIKeyboardKey.delete.rawValue) }
        type("Wayne\n")
        wait(for: "Your name")
        XCTAssertEqual(line("Your name").value as? String, "Wayne", "the name is kept")
        Thread.sleep(forTimeInterval: 0.8)

        // A link is made, and the people on the list are named.
        line("Make a link").tap()
        wait(for: "Send link")
        wait(for: "Ada Lovelace")
        XCTAssertEqual(app.buttons["ben@example.com"].value as? String, "invited")
        XCTAssertTrue(gone(first("Make a link")))

        // After the link the same name stands on the user's own line, among the people.
        XCTAssertEqual(line("Your name").value as? String, "Wayne", "the name is kept")
        // Typed again and left blank, the name iCloud gives is used again.
        line("Your name").tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        for _ in 0..<5 { app.typeText(XCUIKeyboardKey.delete.rawValue) }
        // "done" above the keys, not the key of the same name on the keyboard.
        let dones = app.buttons.matching(identifier: "done").allElementsBoundByIndex
        dones.min { $0.frame.minY < $1.frame.minY }?.tap()
        wait(for: "Your name")
        XCTAssertEqual(line("Your name").value as? String, "Wayne Xu", "a blank name gives way to iCloud's")
        Thread.sleep(forTimeInterval: 0.8)

        line("Copy link").tap()
        wait(for: "Copied")

        // Taking a person off asks first. Keep changes nothing.
        app.buttons["ben@example.com"].tap()
        XCTAssertTrue(app.buttons["Yes, remove"].waitForExistence(timeout: 3), "a tap on a person asks first")
        app.buttons["Keep"].tap()
        XCTAssertTrue(gone(app.buttons["Yes, remove"]))
        XCTAssertTrue(app.buttons["ben@example.com"].exists, "Keep leaves them on the list")
        app.buttons["ben@example.com"].tap()
        XCTAssertTrue(app.buttons["Yes, remove"].waitForExistence(timeout: 3))
        app.buttons["Yes, remove"].tap()
        XCTAssertTrue(gone(app.buttons["ben@example.com"]), "and Yes takes them off")
        wait(for: "Ada Lovelace")

        // Stopping asks first, and Keep sharing changes nothing.
        line("Stop sharing").tap()
        wait(for: "Yes, stop sharing")
        line("Keep sharing").tap()
        XCTAssertTrue(gone(first("Yes, stop sharing")))
        wait(for: "Stop sharing")
        wait(for: "Ada Lovelace")

        // A tap on the page puts the lines away, and settings are settings again.
        point(0.5, 0.92).tap()
        XCTAssertTrue(gone(first("Send link")), "a tap on the page puts sharing away")
        drag(from: (0.5, 0.4), to: (0.5, 0.65))
        wait(for: "Show counts")
        XCTAssertFalse(first("Send link").exists, "pulling down brings settings, not sharing")
        point(0.5, 0.92).tap()
        XCTAssertTrue(gone(first("Show counts")))

        // The other person's side: a list shared with them is left, not deleted.
        app.buttons["home"].tap()
        Thread.sleep(forTimeInterval: 1)
        app.buttons["home"].press(forDuration: 1)
        XCTAssertTrue(app.buttons["Leave list"].waitForExistence(timeout: 3), "someone else's list is left")
        XCTAssertFalse(app.buttons["Delete list"].exists)
        app.buttons["Shared"].tap()
        wait(for: "Leave list")
        XCTAssertFalse(first("Stop sharing").exists, "only the owner stops sharing")
        XCTAssertFalse(first("Send link").exists)
        // They cannot take anyone off.
        line("Ada Lovelace").tap()
        XCTAssertFalse(app.buttons["Yes, remove"].exists)
        line("Leave list").tap()
        XCTAssertTrue(app.buttons["Yes, leave"].waitForExistence(timeout: 3), "leaving asks first")
        app.buttons["Stay"].tap()
        XCTAssertTrue(app.buttons["home"].waitForExistence(timeout: 3), "Stay keeps the list")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Several tasks picked out and deleted together. The app asks first,
    /// and a tap on the empty paper lets them all go.
    func testSeveralTasksArePickedAndDeletedTogether() {
        skipTheFirstPage()
        point(0.5, 0.5).tap()
        for task in ["One\n", "Two\n", "Three\n", "Four"] {
            type(task)
            Thread.sleep(forTimeInterval: 1)
        }
        app.buttons["done"].tap()
        XCTAssertTrue(app.buttons["Four"].waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.8)

        // Hold a task: Select picks it, and a tap on another picks that too.
        app.buttons["Two"].coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Select"].waitForExistence(timeout: 3), "the task menu offers picking several")
        app.buttons["Select"].tap()
        wait(for: "1 picked")
        XCTAssertEqual(app.buttons["Two"].value as? String, "Picked")
        XCTAssertEqual(app.buttons["One"].value as? String, "Not picked")
        XCTAssertFalse(app.buttons["life"].exists, "the list names make way")
        app.buttons["Four"].coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        wait(for: "2 picked")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "a tap picks, and does not edit")
        // A second tap lets one go again.
        app.buttons["Four"].coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        wait(for: "1 picked")
        app.buttons["Four"].coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        wait(for: "2 picked")

        // A drag across a task strikes nothing while tasks are picked.
        let y = app.buttons["One"].frame.midY / app.frame.height
        drag(from: (0.12, y), to: (0.9, y))
        XCTAssertTrue(app.buttons["One"].exists)
        XCTAssertEqual(app.buttons["One"].value as? String, "Not picked")

        // Delete asks first, and Keep changes nothing.
        app.buttons["Delete"].tap()
        wait(for: "Delete 2?")
        app.buttons["Keep"].tap()
        wait(for: "2 picked")
        for task in ["One", "Two", "Three", "Four"] { XCTAssertTrue(app.buttons[task].exists) }
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["Yes, delete"].waitForExistence(timeout: 3))
        app.buttons["Yes, delete"].tap()
        XCTAssertTrue(gone(app.buttons["Two"]), "the picked tasks are deleted")
        XCTAssertTrue(gone(app.buttons["Four"]))
        XCTAssertTrue(app.buttons["One"].exists)
        XCTAssertTrue(app.buttons["Three"].exists)
        XCTAssertTrue(app.buttons["life"].waitForExistence(timeout: 3), "the list names are back")
        XCTAssertEqual(app.buttons["life"].value as? String, "2 left")
        XCTAssertLessThan(app.buttons["One"].frame.minY, app.buttons["Three"].frame.minY, "the rest keep their order")

        // All picks every task. A tap on the empty paper lets them all go, and nothing is deleted.
        app.buttons["One"].coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Select"].waitForExistence(timeout: 3))
        app.buttons["Select"].tap()
        wait(for: "1 picked")
        app.buttons["All"].tap()
        wait(for: "2 picked")
        XCTAssertFalse(app.buttons["All"].exists, "with every task picked there is no more to pick")
        point(0.5, 0.6).tap()
        XCTAssertTrue(app.buttons["life"].waitForExistence(timeout: 3), "a tap on the paper lets them go")
        XCTAssertTrue(app.buttons["One"].exists)
        XCTAssertTrue(app.buttons["Three"].exists)
        XCTAssertNotEqual(app.buttons["One"].value as? String, "Picked")

        // With one task left on the page there is nothing to pick several of.
        drag(acrossLine: "Three")
        XCTAssertTrue(gone(app.buttons["Three"]))
        app.buttons["One"].coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Select"].exists)
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: Helpers

    private func skipTheFirstPage() {
        XCTAssertTrue(app.buttons["skip"].waitForExistence(timeout: 6))
        app.buttons["skip"].tap()
        XCTAssertTrue(app.buttons["life"].waitForExistence(timeout: 5), "skip leads to the first list")
    }

    /// Whether the list of this name becomes the one open, given a moment for the page to turn.
    private func selected(_ name: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true"), object: app.buttons[name]
        )
        return XCTWaiter().wait(for: [expectation], timeout: 4) == .completed
    }

    /// While tasks are written one after another, the line being written
    /// stays just above the keyboard and "done", however long the page grows.
    func testThePageFollowsTheLineBeingWritten() {
        skipTheFirstPage()
        point(0.5, 0.5).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the keyboard should be up")
        Thread.sleep(forTimeInterval: 0.6)
        for number in 1...18 {
            app.typeText("Task number \(number)\n")
            Thread.sleep(forTimeInterval: 0.7)
            guard number >= 6 else { continue }
            assertTheNewLineIsWellPlaced("after task \(number)")
        }
        // A line that grows as it is written, past the width of the page.
        app.typeText("A long line that goes on past the edge of the paper and on to the next row and further")
        Thread.sleep(forTimeInterval: 0.7)
        assertTheNewLineIsWellPlaced("while a long line is written")
        // Every line arrived whole: no letter typed while the page moved was lost.
        let missing = (1...18).filter { !line("Task number \($0)").exists }
        XCTAssertEqual(missing, [], "tasks whose words did not arrive whole")
    }

    private func assertTheNewLineIsWellPlaced(_ when: String, file: StaticString = #filePath, line number: UInt = #line) {
        let keyboardTop = app.keyboards.firstMatch.frame.minY
        let field = line("New task").frame
        XCTAssertLessThanOrEqual(field.maxY, keyboardTop + 1, "\(when): the line is above the keyboard", file: file, line: number)
        XCTAssertGreaterThan(field.maxY, keyboardTop - 150, "\(when): and not far above it", file: file, line: number)
        let done = app.buttons.matching(identifier: "done").allElementsBoundByIndex.map(\.frame).min { $0.minY < $1.minY }
        if let done {
            XCTAssertLessThanOrEqual(field.maxY, done.minY + 8, "\(when): the line is clear of \"done\"", file: file, line: number)
        }
    }

    private func first(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Types once the keyboard is up, one key at a time, as a person does.
    private func type(_ text: String) {
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the keyboard should be up")
        Thread.sleep(forTimeInterval: 0.4)
        for character in text {
            app.typeText(String(character))
        }
    }

    /// Of everything with the label the smallest is taken: that is the line itself.
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
        Thread.sleep(forTimeInterval: settle)
    }

    /// Drags from the left margin across the text of a line, as a strike does.
    private func drag(acrossLine label: String) {
        wait(for: label)
        let target = line(label)
        // Through the first line of the task: a long one wraps.
        let y = (target.frame.minY + min(target.frame.height / 2, 16)) / app.frame.height
        drag(from: (0.12, y), to: (0.9, y))
    }
}
