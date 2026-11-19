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
