import CoreGraphics
import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import SansSerif

/// The pen: strokes kept as numbers, drawn as shapes, and the loop round a
/// task, with the input a person would never give on purpose.
@Suite("The pen at the edges")
struct PenEdgeTests {
    private let line = StrikeLine(minX: 20, maxX: 220, midY: 40, xHeight: 11.5, halfWidth: 1.1)

    // MARK: Strokes as they are kept

    @Test func strokesThatCannotBeReadAreNoStrokes() {
        #expect(Stroke.decode(nil).isEmpty)
        #expect(Stroke.decode(Data()).isEmpty)
        #expect(Stroke.decode(Data("not json".utf8)).isEmpty)
        #expect(Stroke.decode(Data("{\"seed\":1}".utf8)).isEmpty)
        #expect(Stroke.decode(Data("[]".utf8)).isEmpty)
        #expect(Stroke.decode(Data("[{\"seed\":1}]".utf8)).isEmpty, "a stroke with parts missing is not half read")
    }

    @Test func anyNumberOfStrokesGoesToStorageAndBack() {
        for count in [0, 1, 3, 50] {
            let strokes = Stroke.generated(lines: count, seed: 99)
            #expect(Stroke.decode(Stroke.encode(strokes)) == strokes)
        }
        #expect(Stroke.generated(lines: -4, seed: 1).isEmpty)
        #expect(Set(Stroke.generated(lines: 6, seed: 1).map(\.seed)).count == 6, "each line is its own pass of the pen")
    }

    @Test func theSeedsOfLaterLinesWrapRoundWithoutStopping() {
        #expect(Stroke.lineSeed(.max, line: 0) == .max)
        _ = Stroke.lineSeed(.max, line: 5)
        _ = Stroke.lineSeed(.max - 3, line: 1_000_000)
        #expect(Stroke.lineSeed(7, line: 2) != Stroke.lineSeed(7, line: 3))
        #expect(Stroke.generated(lines: 3, seed: .max).count == 3)
    }

    @Test func theSeededNumbersAreTheSameOnEveryDevice() {
        // The first numbers SplitMix64 gives for a seed of 0. If these change,
        // every struck task is redrawn with a different line.
        var random = SplitMix64(seed: 0)
        let first = random.next()
        let second = random.next()
        #expect(first == 0xE220_A839_7B1D_CDAF)
        #expect(second == 0x6E78_9E6A_A1B9_65F4)
        var again = SplitMix64(seed: 0)
        var other = SplitMix64(seed: 1)
        let repeated = again.next()
        let different = other.next()
        #expect(repeated == first)
        #expect(different != first)
    }

    @Test func anIdentityAlwaysHashesTheSameAndTwoHashApart() throws {
        let id = try #require(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        let same = try #require(UUID(uuidString: "e621e1f8-c36c-495a-93fc-0c247a3e6e5f"))
        #expect(id.hashValueStable == same.hashValueStable)
        #expect(id.loopSeed == same.loopSeed)
        #expect(id.loopSeed != id.hashValueStable, "the loop is not drawn from the strike's seed")
        let hashes = Set((0..<500).map { _ in UUID().hashValueStable })
        #expect(hashes.count == 500)
    }

    // MARK: Strokes as they are drawn

    @Test(arguments: [
        (-1.0, 0.7), (0.0, 0.7), (0.05, 0.71), (0.25, 1.15), (0.5, 1.7), (1.0, 1.8), (40.0, 1.8),
    ])
    func aPencilsPressureGivesAWeightWithinItsRange(pressure: Double, weight: Double) {
        #expect(abs(Stroke.weight(forPressure: pressure) - weight) < 1e-9)
    }

    @Test func aDragHoweverWildGivesALineInsideTheBrief() {
        let wild: [(Double, Double, Double)] = [
            (.infinity, .infinity, .infinity), (-.infinity, -.infinity, -.infinity),
            (1e9, -1e9, 0), (0, 0, -5000), (-3, 40, 1e12),
        ]
        for (lift, slope, speed) in wild {
            let stroke = Stroke.drawn(seed: 4, lift: lift, slope: slope, speed: speed)
            #expect((-Stroke.liftLimit...Stroke.liftLimit).contains(stroke.lift))
            #expect((-Stroke.riseLimit...Stroke.riseLimit).contains(stroke.rise))
            #expect(Stroke.weightRange.contains(stroke.weight))
        }
        #expect(Stroke.drawn(seed: 4, lift: 0, slope: 0, speed: -5000).weight == Stroke.weightRange.upperBound)
        #expect(Stroke.drawn(seed: 4, lift: 0, slope: 0, speed: 1e12).weight == Stroke.weightRange.lowerBound)
    }

    @Test func aLinePartDrawnIsShorterAndProgressOutsideZeroToOneIsHeldThere() {
        let stroke = Stroke.generated(seed: 11)
        let whole = StrikePath.path(stroke, on: line).boundingRect
        let half = StrikePath.path(stroke, on: line, progress: 0.5).boundingRect
        let none = StrikePath.path(stroke, on: line, progress: 0).boundingRect
        #expect(half.width < whole.width)
        #expect(half.width > whole.width * 0.4)
        #expect(none.width < 6)
        #expect(StrikePath.path(stroke, on: line, progress: 7).boundingRect == whole)
        #expect(StrikePath.path(stroke, on: line, progress: -2).boundingRect == none)
        #expect(abs(half.minX - whole.minX) < 1, "a line grows from where the pen landed")
    }

    @Test func aLineOverNoTextOrTinyTextStillDrawsAndStaysFinite() {
        let stroke = Stroke.generated(seed: 3)
        for odd in [
            StrikeLine(minX: 50, maxX: 50, midY: 20, xHeight: 11, halfWidth: 1),
            StrikeLine(minX: 50, maxX: 40, midY: 20, xHeight: 11, halfWidth: 1),
            StrikeLine(minX: 0, maxX: 3000, midY: 0, xHeight: 0, halfWidth: 0),
            StrikeLine(minX: -400, maxX: -100, midY: -30, xHeight: 4, halfWidth: 0.2),
        ] {
            let bounds = StrikePath.path(stroke, on: odd).boundingRect
            #expect(bounds.width.isFinite && bounds.height.isFinite)
            #expect(!bounds.isNull)
        }
    }

    @Test func everyGeneratedLineStaysCloseToTheMiddleOfTheWords() {
        for seed in 0..<300 {
            let stroke = Stroke.generated(seed: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15)
            let bounds = StrikePath.path(stroke, on: line).boundingRect
            #expect(bounds.minY > line.midY - line.xHeight, "seed \(seed) climbs out of the lowercase")
            #expect(bounds.maxY < line.midY + line.xHeight, "seed \(seed) falls out of the lowercase")
            #expect(bounds.minX < line.minX && bounds.maxX > line.maxX)
        }
    }

    @Test func aMovedLineIsTheSameLineSomewhereElse() {
        let moved = line.offsetBy(dx: 30, dy: -12)
        #expect(moved.minX == 50 && moved.maxX == 250 && moved.midY == 28)
        #expect(moved.xHeight == line.xHeight && moved.halfWidth == line.halfWidth)
        let stroke = Stroke.generated(seed: 8)
        let here = StrikePath.path(stroke, on: line).boundingRect
        let there = StrikePath.path(stroke, on: moved).boundingRect
        #expect(abs(there.width - here.width) < 0.01)
        #expect(abs(there.minX - here.minX - 30) < 0.01)
        #expect(abs(there.minY - here.minY + 12) < 0.01)
    }

    // MARK: Strokes of a task

    @MainActor
    @Test func aTaskWrappedToMoreLinesThanItWasStruckOnGetsTheSameExtraLinesEveryTime() throws {
        let container = try PageStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let list = try #require(try context.addList(named: "life"))
        let task = try #require(context.addTask("A long task that wraps", to: list))
        let other = try #require(context.addTask("Another", to: list))
        let stored = Stroke.generated(lines: 1, seed: 21)
        context.strike(task, strokeData: Stroke.encode(stored))

        let three = task.strokes(forLines: 3)
        #expect(three.count == 3)
        #expect(three[0] == stored[0], "the line that was drawn is kept")
        #expect(task.strokes(forLines: 3) == three)
        #expect(Set(three.map(\.seed)).count == 3)
        #expect(task.strokes(forLines: 0).isEmpty)
        #expect(task.strokes(forLines: 1) == stored)

        // Struck with no pen line kept, as from a widget: made up from the task itself.
        context.strike(other)
        #expect(other.strokes.isEmpty)
        let made = other.strokes(forLines: 2)
        #expect(made == other.strokes(forLines: 2))
        #expect(made != task.strokes(forLines: 2))
    }

    // MARK: The loop round a task

    private func ring(turns: Double, radius: CGFloat = 40, flat: CGFloat = 0.5, from start: Double = 0) -> [CGPoint] {
        let steps = 48
        return (0...steps).map { step in
            let angle = start + turns * 2 * .pi * Double(step) / Double(steps)
            return CGPoint(x: 100 + radius * cos(angle), y: 100 + radius * flat * sin(angle))
        }
    }

    @Test func aLoopCountsWhicheverWayRoundAndWhereverItBegins() {
        #expect(TaskLine.closes(ring(turns: 1)))
        #expect(TaskLine.closes(ring(turns: -1)))
        #expect(TaskLine.closes(ring(turns: 1, from: 2.2)))
        #expect(TaskLine.closes(ring(turns: 1.3)), "going on past the start still counts")
        #expect(TaskLine.closes(ring(turns: 0.8, radius: 90)), "most of the way round a long task counts")
        #expect(TaskLine.closes(ring(turns: -0.8, radius: 90)))
    }

    @Test func whatIsNotALoopDoesNotCount() {
        #expect(!TaskLine.closes([]))
        #expect(!TaskLine.closes([CGPoint(x: 0, y: 0)]))
        #expect(!TaskLine.closes(ring(turns: 1).prefix(3).map { $0 }), "too few points to tell")
        #expect(!TaskLine.closes((0...20).map { CGPoint(x: CGFloat($0) * 10, y: 40) }), "a strike straight across")
        #expect(!TaskLine.closes((0...20).map { CGPoint(x: CGFloat($0) * 10, y: 40 + CGFloat($0 % 2) * 4) }), "a shaky strike")
        #expect(!TaskLine.closes(ring(turns: 1, radius: 12)), "too small to have gone round the words")
        #expect(!TaskLine.closes(ring(turns: 1, radius: 60, flat: 0.05)), "across and back along the same line")
        #expect(!TaskLine.closes(ring(turns: 0.5, radius: 90)), "half way round a long task")
        #expect(!TaskLine.closes((0...20).map { CGPoint(x: 40, y: CGFloat($0) * 10) }), "a scroll straight down")
        let same = [CGPoint](repeating: CGPoint(x: 5, y: 5), count: 30)
        #expect(!TaskLine.closes(same), "a finger held still")
    }

    @Test func theDrawnLoopGoesRoundTheWordsAndIsTheSameEachTime() {
        let words = CGRect(x: 30, y: 20, width: 180, height: 26)
        let loop = CircleLoop(words: words, seed: 5).path(in: .zero)
        let bounds = loop.boundingRect
        #expect(bounds.contains(words), "the loop is outside the words on every side")
        #expect(bounds.width < words.width + 80 && bounds.height < words.height + 50, "and not far outside")
        #expect(CircleLoop(words: words, seed: 5).path(in: .zero).boundingRect == bounds)
        #expect(CircleLoop(words: words, seed: 6).path(in: .zero).boundingRect != bounds)
        let dot = CircleLoop(words: .zero, seed: 5).path(in: .zero).boundingRect
        #expect(dot.width.isFinite && dot.width > 0)
    }

    @MainActor
    @Test func theLoopTakesInEveryLineOfATask() throws {
        #expect(CircleMark.words([]) == nil)
        let first = StrikeLine(minX: 20, maxX: 200, midY: 30, xHeight: 12, halfWidth: 1)
        let second = StrikeLine(minX: 20, maxX: 90, midY: 62, xHeight: 12, halfWidth: 1)
        let one = try #require(CircleMark.words([first]))
        let two = try #require(CircleMark.words([first, second]))
        #expect(one.minX == 20 && one.maxX == 200)
        #expect(one.minY < first.midY && one.maxY > first.midY)
        #expect(two.maxY > second.midY && two.minY == one.minY)
        #expect(two.width == one.width, "as wide as the widest line")
        #expect(two.height > one.height)
    }

    // MARK: What a drag is felt as

    @Test func aDragIsFeltOncePerStretchInEitherDirection() {
        var ticks = DragTicks()
        #expect(ticks.count == 0)
        ticks.move(to: 0.01)
        #expect(ticks.count == 0, "still in the first stretch")
        ticks.land()
        #expect(ticks.count == 1)
        for fraction in stride(from: 0.0, through: 1.0, by: 0.01) { ticks.move(to: fraction) }
        #expect(ticks.count == 1 + DragTicks.perLine)
        for fraction in stride(from: 1.0, through: 0.0, by: -0.01) { ticks.move(to: fraction) }
        #expect(ticks.count == 1 + 2 * DragTicks.perLine, "and again on the way back")
        let before = ticks.count
        ticks.move(to: 0.02)
        ticks.move(to: 0.03)
        #expect(ticks.count == before, "a finger that hardly moves is not felt")
    }

    @Test func aFingerTremblingOnABoundaryIsFeltEachTimeItCrosses() {
        var ticks = DragTicks()
        ticks.land()
        let boundary = 1.0 / Double(DragTicks.perLine)
        for _ in 0..<3 {
            ticks.move(to: boundary + 0.001)
            ticks.move(to: boundary - 0.001)
        }
        #expect(ticks.count == 7)
        ticks.land()
        ticks.move(to: 0)
        #expect(ticks.count == 8, "landing again starts from the beginning of the line")
    }
}

/// The page's measurements for every width and shape of window, the edges of
/// a pull, and what a menu is open on.
@Suite("The page at the edges")
struct PageEdgeTests {
    #if os(iOS)
    @Test(arguments: [
        (320.0, UserInterfaceSizeClass.compact, UserInterfaceSizeClass.regular, "phone"),
        (402.0, .compact, .regular, "phone"),
        (499.9, .regular, .regular, "phone"),
        (500.0, .regular, .regular, "pad"),
        (500.0, .compact, .regular, "landscape"),
        (874.0, .compact, .compact, "landscape"),
        (956.0, .regular, .compact, "landscape"),
        (1366.0, .regular, .regular, "pad"),
        (0.0, .regular, .regular, "phone"),
    ])
    func everyWindowGetsMeasurementsFromItsWidthAndShape(
        window: (Double, UserInterfaceSizeClass, UserInterfaceSizeClass, String)
    ) {
        let metrics = PageMetrics.resolve(
            width: window.0, horizontalSizeClass: window.1, verticalSizeClass: window.2
        )
        let expected: PageMetrics = switch window.3 {
        case "pad": .pad
        case "landscape": .phoneLandscape
        default: .phone
        }
        #expect(metrics == expected)
    }

    @Test func aWindowThatDoesNotSayItsShapeIsStillLaidOut() {
        #expect(PageMetrics.resolve(width: 390, horizontalSizeClass: nil, verticalSizeClass: nil) == .phone)
        #expect(PageMetrics.resolve(width: 900, horizontalSizeClass: nil, verticalSizeClass: nil) == .phoneLandscape)
    }
    #endif

    @Test func theListNamesKeepTheirDistanceFromTheBottomWhateverTheSafeArea() {
        for metrics in [PageMetrics.phone, .phoneLandscape, .pad, .mac] {
            #expect(metrics.bottomInset(safeArea: 0) == max(metrics.bottomEdgeDistance, metrics.minBottomInset))
            #expect(metrics.bottomInset(safeArea: 10_000) == metrics.minBottomInset)
            #expect(metrics.bottomInset(safeArea: -20) >= metrics.minBottomInset)
            #expect(metrics.minTouchHeight >= 44, "list names and menu words can be touched")
            #expect(metrics.sideMargin > 0 && metrics.taskSize > metrics.countSize)
        }
        #expect(PageMetrics.phone.bottomInset(safeArea: 34) == 14)
        #expect(PageMetrics.phone.columnCap == nil)
        #expect(PageMetrics.pad.columnCap == 600)
    }

    @Test func theWordsOfAMenuAreSmallerThanTheListNames() {
        for metrics in [PageMetrics.phone, .phoneLandscape, .pad, .mac] {
            #expect(TypeStyle.action.baseSize(in: metrics) < TypeStyle.listName.baseSize(in: metrics))
            #expect(TypeStyle.count.baseSize(in: metrics) < TypeStyle.action.baseSize(in: metrics))
            #expect(TypeStyle.task.baseSize(in: metrics) >= TypeStyle.listName.baseSize(in: metrics))
        }
        #expect(TypeStyle.monthLabel.isItalic)
        #expect(!TypeStyle.task.isItalic)
        #expect(SerifFont.lineHeight(size: 25) > 25)
        #expect((0.3...0.7).contains(SerifFont.xHeightRatio))
    }

    @Test func aMenuKnowsWhatItIsOpenOn() {
        let id = UUID()
        #expect(PageMenu.task(id, moving: false).taskID == id)
        #expect(PageMenu.task(id, moving: true).listID == nil)
        #expect(PageMenu.list(id, confirmingDelete: true).listID == id)
        #expect(PageMenu.list(id, confirmingDelete: false).taskID == nil)
        #expect(PageMenu.task(id, moving: false) != PageMenu.task(id, moving: true))
        #expect(PageMenu.task(id, moving: false) != PageMenu.list(id, confirmingDelete: false))
        #expect(MenuOption(title: "Delete", isDestructive: true) {}.id == "Delete")
    }

    // MARK: How far past an edge

    @Test func aLongPageIsPastItsEndOnlyBeyondItsLastLine() {
        let past = { (offset: CGFloat) in
            PullTracker.past(.bottom, offset: offset, topInset: 62, bottomInset: 34,
                             contentHeight: 2000, containerHeight: 812)
        }
        #expect(past(-62) == -1284, "at the top it is a long way short of the end")
        #expect(past(1222) == 0)
        #expect(past(1262) == 40)
        let top = { (offset: CGFloat) in
            PullTracker.past(.top, offset: offset, topInset: 62, bottomInset: 34,
                             contentHeight: 2000, containerHeight: 812)
        }
        #expect(top(-62) == 0)
        #expect(top(-112) == 50)
        #expect(top(300) == -362)
    }

    @Test func anEmptyPageRestsAtBothEdgesAtOnce() {
        for edge in [PullEdge.top, .bottom, .awayFromTop] {
            #expect(PullTracker.past(edge, offset: -62, topInset: 62, bottomInset: 0,
                                     contentHeight: 0, containerHeight: 812) == 0)
            #expect(PullTracker.past(edge, offset: 0, topInset: 0, bottomInset: 0,
                                     contentHeight: 0, containerHeight: 0) == 0)
        }
    }

    @Test func aPullDownPastTheTopCountsOnceAndOnlyWhenDragged() {
        var pull = PullTracker(edge: .top)
        pull.began(past: 0, offset: -62)
        #expect(pull.changed(past: 39, offset: -101) == false)
        #expect(pull.pull.past == 39)
        #expect(pull.pull.shift == 39, "down is positive")
        #expect(pull.changed(past: 40, offset: -102) == true, "on the stroke of the distance")
        #expect(pull.changed(past: 90, offset: -152) == false)
        #expect(pull.released() == false)

        // The same sheet, bouncing past its top with no finger on it.
        var bounce = PullTracker(edge: .top)
        #expect(bounce.changed(past: 80, offset: -142) == false)
        #expect(bounce.released() == false)
    }

    @Test func aPullUpIsAShiftUpAndShortOfTheEdgeIsNoPullAtAll() {
        var pull = PullTracker(edge: .bottom)
        pull.began(past: -300, offset: 100)
        #expect(pull.pull.past == 0, "short of the edge, nothing is pulled")
        #expect(pull.pull.shift == 0)
        _ = pull.changed(past: 25, offset: 425)
        #expect(pull.pull.past == 25)
        #expect(pull.pull.shift == -25, "up is negative")
    }

    @Test func aFingerThatComesDownAndLiftsWithoutMovingDoesNothing() {
        for edge in [PullEdge.top, .bottom, .awayFromTop] {
            var pull = PullTracker(edge: edge)
            pull.began(past: 0, offset: -62)
            #expect(pull.released() == false)
            #expect(pull.released() == false, "and lifting twice is the same as once")
            #expect(pull.held() == nil)
            #expect(pull.letGo() == false)
        }
    }

    @Test func puttingSettingsAwayTakesLessOfADragThanOpeningTheArchive() {
        #expect(PullTracker(edge: .awayFromTop).distance < PullTracker(edge: .bottom).distance)
        #expect(PullTracker(edge: .awayFromTop).flickDistance < PullTracker(edge: .top).flickDistance)
        var away = PullTracker(edge: .awayFromTop)
        away.began(past: 0, offset: -62)
        #expect(away.changed(past: 20, offset: -42) == true)
        var twice = PullTracker(edge: .awayFromTop)
        twice.began(past: 0, offset: -62)
        _ = twice.changed(past: 30, offset: -32)
        // A second finger down starts a new drag, which may count again.
        twice.began(past: 0, offset: -62)
        #expect(twice.changed(past: 30, offset: -32) == true)
    }
}

/// Settings as they are kept on the device.
@Suite("Settings at the edges")
struct SettingsEdgeTests {
    private let all = [
        Setting.showCounts, Setting.iCloudSync, Setting.haptics, Setting.darkPaper,
        Setting.guideDone, Setting.guideReplay,
    ]

    @Test func nothingIsOffOnAFirstLaunchButTheFirstPageHasNotBeenSeen() {
        #expect(Setting.showCounts.defaultValue)
        #expect(Setting.iCloudSync.defaultValue)
        #expect(Setting.haptics.defaultValue)
        #expect(!Setting.guideDone.defaultValue)
        #expect(!Setting.guideReplay.defaultValue)
    }

    @Test func noSettingSharesAKeyWithAnotherOrWithTheLiveView() {
        let keys = all.map(\.key) + [LiveView.listKey]
        #expect(Set(keys).count == keys.count)
        #expect(keys.allSatisfy { !$0.isEmpty && !$0.contains(" ") })
    }

    @Test func aSettingIsReadAsItsDefaultUntilItIsSetAndThenAsSet() throws {
        let defaults = try #require(UserDefaults(suiteName: "settings-edge-\(UUID().uuidString)"))
        for setting in all {
            #expect(defaults.object(forKey: setting.key) == nil)
            let read = { defaults.object(forKey: setting.key) as? Bool ?? setting.defaultValue }
            #expect(read() == setting.defaultValue)
            defaults.set(!setting.defaultValue, forKey: setting.key)
            #expect(read() == !setting.defaultValue)
            defaults.set("yes", forKey: setting.key)
            #expect(read() == setting.defaultValue, "something that is not on or off is read as the default")
        }
    }
}
