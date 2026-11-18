import CoreGraphics
import Foundation
import Testing

@testable import SansSerif

struct StrikeTests {
    let line = StrikeLine(minX: 32, maxX: 232, midY: 100, xHeight: 12, halfWidth: 1.1)

    @Test func aSeedAlwaysGivesTheSameLine() {
        let a = Stroke.generated(seed: 42)
        let b = Stroke.generated(seed: 42)
        #expect(a == b)
        #expect(StrikePath.path(a, on: line).boundingRect == StrikePath.path(b, on: line).boundingRect)
    }

    @Test func noTwoSeedsLookTheSame() {
        let strokes = (0..<50).map { Stroke.generated(seed: $0) }
        #expect(Set(strokes).count == 50)
    }

    @Test func generatedStrokesStayInsideTheBrief() {
        for seed in 0..<500 as Range<UInt64> {
            let stroke = Stroke.generated(seed: seed)
            #expect(Stroke.overshoot.contains(stroke.leadIn))
            #expect(Stroke.overshoot.contains(stroke.leadOut))
            #expect(abs(stroke.rise) <= Stroke.riseLimit)
            #expect(abs(stroke.lift) <= Stroke.liftLimit)
            #expect(Stroke.weightRange.contains(stroke.weight))
        }
    }

    @Test func drawnStrokesAreClampedHoweverWildTheDrag() {
        let stroke = Stroke.drawn(seed: 1, lift: 9, slope: -40, speed: 90_000)
        #expect(stroke.lift == Stroke.liftLimit)
        #expect(stroke.rise == -Stroke.riseLimit)
        #expect(stroke.weight == Stroke.weightRange.lowerBound)
    }

    @Test func aFullLineOvershootsTheTextOnBothSidesAndStaysInTheLowercase() {
        for seed in 0..<100 as Range<UInt64> {
            let stroke = Stroke.generated(seed: seed)
            let bounds = StrikePath.path(stroke, on: line).boundingRect
            #expect(bounds.minX < line.minX - 3)
            #expect(bounds.maxX > line.maxX + 3)
            #expect(bounds.minY > line.midY - line.xHeight / 2)
            #expect(bounds.maxY < line.midY + line.xHeight / 2)
        }
    }

    @Test func aPartLineStopsWhereThePenIs() {
        let stroke = Stroke.generated(seed: 7)
        let half = StrikePath.path(stroke, on: line, progress: 0.5).boundingRect
        let middle = StrikePath.centre(stroke, on: line, at: 0.5).x
        #expect(abs(half.maxX - middle) < 3)
        #expect(StrikePath.path(stroke, on: line, progress: 0).isEmpty)
    }

    @Test func theLineTapersToAPointAndSwellsAfterLanding() {
        let stroke = Stroke.generated(seed: 3)
        #expect(StrikePath.halfWidth(stroke, on: line, at: 1) == 0)
        #expect(StrikePath.halfWidth(stroke, on: line, at: 0.08) > StrikePath.halfWidth(stroke, on: line, at: 0.55))
        #expect(StrikePath.halfWidth(stroke, on: line, at: 0) > 0)
    }

    @Test func strokesSurviveStorageOnePerLine() {
        let strokes = Stroke.generated(lines: 3, seed: 99)
        #expect(strokes.count == 3)
        #expect(Set(strokes).count == 3)
        #expect(Stroke.decode(Stroke.encode(strokes)) == strokes)
        #expect(Stroke.decode(nil).isEmpty)
        #expect(Stroke.decode(Data([1, 2, 3])).isEmpty)
    }
}
