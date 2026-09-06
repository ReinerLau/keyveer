import CoreGraphics
import KeyveerRuntime
import XCTest

@testable import KeyveerApp

final class LightningTrailEngineTests: XCTestCase {
  func testEightPointMovementStartsABoltFromTheExactOrigin() {
    var engine = LightningTrailEngine(seed: 1)

    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 8, y: 0), at: 0.1)

    let bolt = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first)
    XCTAssertEqual(bolt.trunk.points.first, CGPoint(x: 0, y: 0))
    XCTAssertEqual(bolt.trunk.points.last, CGPoint(x: 8, y: 0))
  }

  func testMovementBelowEightPointsDoesNotStartABolt() {
    var engine = LightningTrailEngine(seed: 1)

    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 7.9, y: 0), at: 0.1)

    XCTAssertTrue(engine.frame(at: 0.1).isEmpty)
  }

  func testContinuousMovementKeepsWholeBoltBeyondLegacyLimits() {
    var engine = LightningTrailEngine(seed: 2)

    for step in 0...100 {
      engine.move(
        to: CGPoint(x: CGFloat(step) * 8, y: 0),
        at: Double(step) * 0.05)
    }

    let bolt = try! XCTUnwrap(engine.frame(at: 5.0).bolts.first)
    XCTAssertEqual(bolt.trunk.points.first, CGPoint(x: 0, y: 0))
    XCTAssertEqual(bolt.trunk.points.last, CGPoint(x: 800, y: 0))
  }

  func testFirstVisibleBoltBackfillsTheWholeMovement() {
    var engine = LightningTrailEngine(seed: 2)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 270, y: 0), at: 0.3)

    let bolt = try! XCTUnwrap(engine.frame(at: 0.3).bolts.first)
    XCTAssertEqual(bolt.trunk.points.first!.x, 0, accuracy: 0.001)
    XCTAssertEqual(bolt.trunk.points.last!.x, 270, accuracy: 0.001)
  }

  func testBoltGeometryIsDeterministicAndFrozen() {
    var first = LightningTrailEngine(seed: 42)
    var second = LightningTrailEngine(seed: 42)
    for point in [CGPoint(x: 0, y: 0), CGPoint(x: 60, y: 0)] {
      let time = point.x == 0 ? 0 : 0.1
      first.move(to: point, at: time)
      second.move(to: point, at: time)
    }

    let initial = try! XCTUnwrap(first.frame(at: 0.1).bolts.first)
    let sameSeed = try! XCTUnwrap(second.frame(at: 0.1).bolts.first)
    let later = try! XCTUnwrap(first.frame(at: 0.2).bolts.first)

    XCTAssertEqual(initial.trunk, sameSeed.trunk)
    XCTAssertEqual(initial.trunk, later.trunk)
    XCTAssertTrue(initial.trunk.points.dropFirst().dropLast().contains { abs($0.y) > 0.1 })
  }

  func testContinuousMovementAppendsToTheSameFrozenTrunk() {
    var engine = LightningTrailEngine(seed: 42)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 80, y: 0), at: 0.05)
    let initial = try! XCTUnwrap(engine.frame(at: 0.05).bolts.first)

    engine.move(to: CGPoint(x: 160, y: 40), at: 0.10)
    let extended = try! XCTUnwrap(engine.frame(at: 0.10).bolts.first)

    XCTAssertEqual(extended.id, initial.id)
    let frozenInitial = initial.segments.filter { max($0.start.x, $0.end.x) <= 50 }
    XCTAssertEqual(Array(extended.segments.prefix(frozenInitial.count)), frozenInitial)
    XCTAssertEqual(extended.trunk.points.last, CGPoint(x: 160, y: 40))
  }

  func testBoltBendPositionsAreIrregularlySpaced() {
    var engine = LightningTrailEngine(seed: 42)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 200, y: 0), at: 0.1)

    let points = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first?.trunk.points)
    let gaps = zip(points, points.dropFirst()).map { $1.x - $0.x }

    XCTAssertGreaterThan(gaps.max()! - gaps.min()!, 2)
  }

  func testBendOffsetsUseTheSameDistributionAcrossTheWholeTrunk() {
    var edgeOffsets: [CGFloat] = []
    var middleOffsets: [CGFloat] = []
    for seed in 0..<200 {
      var engine = LightningTrailEngine(seed: UInt64(seed))
      engine.move(to: CGPoint(x: 0, y: 0), at: 0)
      engine.move(to: CGPoint(x: 200, y: 0), at: 0.1)

      let points = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first?.trunk.points)
      let primaryBendOffsets = points.enumerated().compactMap { index, point in
        index > 0 && index < points.count - 1 && index.isMultiple(of: 2)
          ? abs(point.y) : nil
      }
      edgeOffsets.append(contentsOf: [primaryBendOffsets.first!, primaryBendOffsets.last!])
      let middle = primaryBendOffsets.count / 2
      middleOffsets.append(
        contentsOf: [primaryBendOffsets[middle - 1], primaryBendOffsets[middle]])
    }

    let edgeAverage = edgeOffsets.reduce(0, +) / CGFloat(edgeOffsets.count)
    let middleAverage = middleOffsets.reduce(0, +) / CGFloat(middleOffsets.count)
    XCTAssertGreaterThan(edgeAverage / middleAverage, 0.75)
    XCTAssertLessThan(edgeAverage / middleAverage, 1.25)
  }

  func testTrunkSegmentsKeepPositionIndependentRandomWidthsWhenTheBoltGrows() {
    var engine = LightningTrailEngine(seed: 42)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 200, y: 0), at: 0.05)
    let initial = try! XCTUnwrap(engine.frame(at: 0.05).bolts.first)
    let initialSegments = initial.segments

    XCTAssertGreaterThan(initialSegments.count, 10)
    XCTAssertTrue(initialSegments.allSatisfy { (0.45...1.6).contains($0.widthScale) })
    XCTAssertGreaterThan(Set(initialSegments.map { Int($0.widthScale * 100) }).count, 3)

    engine.move(to: CGPoint(x: 260, y: 40), at: 0.10)
    let extended = try! XCTUnwrap(engine.frame(at: 0.10).bolts.first)
    let frozenInitial = initialSegments.filter { max($0.start.x, $0.end.x) <= 170 }
    XCTAssertEqual(Array(extended.segments.prefix(frozenInitial.count)), frozenInitial)
  }

  func testEachGapBetweenPrimaryBendsGetsASmallRandomOffset() {
    var engine = LightningTrailEngine(seed: 42)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 200, y: 0), at: 0.1)

    let points = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first?.trunk.points)

    XCTAssertGreaterThan(points.count, 19)
    for index in stride(from: 1, to: points.count - 1, by: 2) {
      let offset = perpendicularDistance(
        from: points[index], toLineFrom: points[index - 1], to: points[index + 1])
      XCTAssertGreaterThan(offset, 1)
      XCTAssertLessThanOrEqual(offset, 5)
    }
  }

  func testCurvedMovementHistoryBendsTheBoltAroundTheTurn() {
    var engine = LightningTrailEngine(seed: 42)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 0, y: 100), at: 0.1)
    engine.move(to: CGPoint(x: 100, y: 100), at: 0.2)
    engine.move(to: CGPoint(x: 100, y: 0), at: 0.3)

    let points = try! XCTUnwrap(engine.frame(at: 0.3).bolts.first?.trunk.points)
    XCTAssertGreaterThan(points.map(\.y).max()!, 50)
  }

  func testBoltDoesNotStartDissipatingUntilMovementHasStoppedForOneHundredMilliseconds() {
    var engine = LightningTrailEngine(seed: 3)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 80, y: 0), at: 0.1)
    let active = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first)

    XCTAssertEqual(engine.frame(at: 0.199).bolts.first?.segments, active.segments)
    XCTAssertEqual(engine.frame(at: 0.20).bolts.first?.segments, active.segments)
    XCTAssertTrue(
      zip(engine.frame(at: 0.30).bolts.first?.segments ?? [], active.segments)
        .contains { $0.widthScale < $1.widthScale })
    XCTAssertEqual(engine.frame(at: 0.30).bolts.first?.alpha, 1)
    XCTAssertTrue(engine.frame(at: 0.65).isEmpty)
  }

  func testContinuousMovementKeepsOnlyTheLatestBoltAtAnyRefreshRate() {
    let atSixty = activeBoltSnapshot(refreshRate: 60)
    let atOneTwenty = activeBoltSnapshot(refreshRate: 120)

    XCTAssertEqual(atSixty.id, atOneTwenty.id)
    XCTAssertEqual(atSixty.trunk, atOneTwenty.trunk)
    XCTAssertEqual(atSixty.segments, atOneTwenty.segments)
    XCTAssertEqual(atSixty.trunk.points.first, CGPoint(x: 0, y: 0))
    XCTAssertEqual(atSixty.trunk.points.last, CGPoint(x: 300, y: 0))
  }

  func testNewMovementCanGrowBesideOnlyTheLatestDissipatingBolt() {
    var engine = LightningTrailEngine(seed: 7)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 80, y: 0), at: 0.1)
    let first = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first)
    let firstID = first.id
    _ = engine.frame(at: 0.2)

    engine.move(to: CGPoint(x: 90, y: 0), at: 0.25)
    let overlapping = engine.frame(at: 0.25).bolts

    XCTAssertEqual(overlapping.count, 2)
    XCTAssertTrue(overlapping.contains { $0.id == firstID && $0.segments != first.segments })
    XCTAssertTrue(overlapping.contains { $0.id != firstID })

    let afterSecondStop = engine.frame(at: 0.36).bolts
    XCTAssertEqual(afterSecondStop.count, 1)
    XCTAssertNotEqual(afterSecondStop.first?.id, firstID)
  }

  func testStoppedBoltStaysAtItsOriginalGeometryAndBreaksWithoutFading() {
    var engine = LightningTrailEngine(seed: 8)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 80, y: 0), at: 0.1)
    let first = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first)

    let stopped = try! XCTUnwrap(engine.frame(at: 0.35).bolts.first)

    XCTAssertEqual(stopped.trunk, first.trunk)
    XCTAssertEqual(stopped.segments.count, first.segments.count)
    for (stoppedSegment, initialSegment) in zip(stopped.segments, first.segments) {
      XCTAssertEqual(stoppedSegment.start, initialSegment.start)
      XCTAssertEqual(stoppedSegment.end, initialSegment.end)
    }
    XCTAssertTrue(zip(stopped.segments, first.segments).contains { $0.widthScale < $1.widthScale })
    XCTAssertEqual(stopped.alpha, first.alpha)
  }

  func testStoppedBoltDissipatesAcrossTheWholeTrunkWithDifferentSegmentWidths() {
    var engine = LightningTrailEngine(seed: 10)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 80, y: 0), at: 0.1)

    let initial = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first)
    let later = try! XCTUnwrap(engine.frame(at: 0.45).bolts.first)

    XCTAssertEqual(initial.trunk, later.trunk)
    XCTAssertEqual(initial.alpha, later.alpha)
    let ratios = zip(later.segments, initial.segments).map { later, initial in
      initial.widthScale > 0 ? later.widthScale / initial.widthScale : 0
    }
    XCTAssertTrue(ratios.contains(0))
    XCTAssertTrue(ratios.contains { $0 > 0 })
    XCTAssertGreaterThan(Set(ratios.map { Int($0 * 100) }).count, 3)
  }

  func testStoppedBoltIsRemovedOnlyAfterItsLifetimeEnds() {
    var engine = LightningTrailEngine(seed: 9)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 80, y: 0), at: 0.1)
    let firstID = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first?.id)

    XCTAssertTrue(engine.frame(at: 0.64).bolts.contains { $0.id == firstID })
    XCTAssertFalse(engine.frame(at: 0.65).bolts.contains { $0.id == firstID })
  }

  func testMovementSpeedDoesNotChangeBrightnessOrSplitTheTrunk() {
    var normal = LightningTrailEngine(seed: 4)
    normal.move(to: CGPoint(x: 0, y: 0), at: 0)
    normal.move(to: CGPoint(x: 64, y: 0), at: 0.128)
    let normalBolt = try! XCTUnwrap(normal.frame(at: 0.128).bolts.first)

    var high = LightningTrailEngine(seed: 4)
    high.move(to: CGPoint(x: 0, y: 0), at: 0)
    high.move(to: CGPoint(x: 200, y: 0), at: 0.1)
    let highBolt = try! XCTUnwrap(high.frame(at: 0.1).bolts.first)

    XCTAssertEqual(normalBolt.trunk.points.first, CGPoint(x: 0, y: 0))
    XCTAssertEqual(normalBolt.trunk.points.last, CGPoint(x: 64, y: 0))
    XCTAssertEqual(highBolt.trunk.points.first, CGPoint(x: 0, y: 0))
    XCTAssertEqual(highBolt.trunk.points.last, CGPoint(x: 200, y: 0))
    XCTAssertEqual(normalBolt.glowScale, 1, accuracy: 0.001)
    XCTAssertEqual(highBolt.glowScale, 1, accuracy: 0.001)
  }

  func testReducedMotionUsesStraightBranchlessShortLivedBolts() {
    var engine = LightningTrailEngine(seed: 5)
    engine.setReduceMotion(true)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 20, y: 0), at: 0.1)

    let bolt = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first)
    XCTAssertEqual(
      bolt.trunk.points,
      [CGPoint(x: 0, y: 0), CGPoint(x: 18, y: 0), CGPoint(x: 20, y: 0)])
    let shrinking = try! XCTUnwrap(engine.frame(at: 0.25).bolts.first)
    XCTAssertEqual(shrinking.alpha, 1)
    for (later, initial) in zip(shrinking.segments, bolt.segments) {
      XCTAssertEqual(later.widthScale, initial.widthScale * 2.0 / 3.0, accuracy: 0.001)
    }
    XCTAssertTrue(engine.frame(at: 0.351).isEmpty)
  }

  func testClearAndAccessibilityModeChangeRemoveAllVisualState() {
    var engine = LightningTrailEngine(seed: 6)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 100, y: 0), at: 0.1)
    XCTAssertFalse(engine.frame(at: 0.1).isEmpty)

    engine.clear()
    XCTAssertTrue(engine.frame(at: 0.1).isEmpty)

    engine.move(to: CGPoint(x: 0, y: 0), at: 0.2)
    engine.move(to: CGPoint(x: 100, y: 0), at: 0.3)
    engine.setReduceMotion(true)
    XCTAssertTrue(engine.frame(at: 0.3).isEmpty)
  }

  private func activeBoltSnapshot(refreshRate: Double) -> RenderedLightningBolt {
    var engine = LightningTrailEngine(seed: 7)
    let frameDuration = 1 / refreshRate
    for frame in 0...Int(refreshRate) {
      let timestamp = Double(frame) * frameDuration
      engine.move(to: CGPoint(x: timestamp * 300, y: 0), at: timestamp)
    }
    return try! XCTUnwrap(engine.frame(at: 1).bolts.first)
  }

  private func perpendicularDistance(
    from point: CGPoint, toLineFrom start: CGPoint, to end: CGPoint
  ) -> CGFloat {
    let delta = CGPoint(x: end.x - start.x, y: end.y - start.y)
    let fromStart = CGPoint(x: point.x - start.x, y: point.y - start.y)
    return abs(delta.x * fromStart.y - delta.y * fromStart.x) / hypot(delta.x, delta.y)
  }
}
