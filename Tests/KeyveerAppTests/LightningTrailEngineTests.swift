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
    let arc = try! XCTUnwrap(bolt.arc)
    XCTAssertEqual(arc.stroke.points.first, bolt.trunk.points.first)
    XCTAssertEqual(arc.stroke.points.last, bolt.trunk.points.last)
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

  func testPrimaryBendOffsetsArePositionIndependentAndWithinGlobalRange() {
    for seed in 0..<200 {
      var engine = LightningTrailEngine(seed: UInt64(seed))
      engine.updateBendOffsetConfiguration(
        spacingMin: 30, spacingMax: 30,
        distanceMin: 6, distanceMax: 24, directionMinDegrees: 0, directionMaxDegrees: 360)
      engine.move(to: CGPoint(x: 0, y: 0), at: 0)
      engine.move(to: CGPoint(x: 200, y: 0), at: 0.1)

      let points = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first?.trunk.points)
      for index in 1..<(points.count - 1) {
        let expectedCenter = CGPoint(x: CGFloat(index) * 30, y: 0)
        let offset = euclideanDistance(points[index], expectedCenter)
        XCTAssertGreaterThanOrEqual(offset, 6)
        XCTAssertLessThanOrEqual(offset, 24)
      }
    }
  }

  func testPrimaryBendOffsetsUseRandomTwoDimensionalDirections() {
    var foundTangentialOffset = false

    for seed in 0..<200 {
      var engine = LightningTrailEngine(seed: UInt64(seed))
      engine.updateBendOffsetConfiguration(
        spacingMin: 30, spacingMax: 30,
        distanceMin: 6, distanceMax: 24, directionMinDegrees: 0, directionMaxDegrees: 360)
      engine.move(to: CGPoint(x: 0, y: 0), at: 0)
      engine.move(to: CGPoint(x: 200, y: 0), at: 0.1)

      let points = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first?.trunk.points)
      XCTAssertEqual(points.count, 8)
      for index in 1..<(points.count - 1) {
        let expectedCenterX = CGFloat(index) * 30
        if abs(points[index].x - expectedCenterX) > 0.5 {
          foundTangentialOffset = true
          break
        }
      }
      if foundTangentialOffset { break }
    }

    XCTAssertTrue(foundTangentialOffset)
  }

  func testConfiguredBendDistanceAndDirectionApplyToNewBolts() {
    var engine = LightningTrailEngine(seed: 42)
    engine.updateBendOffsetConfiguration(
      spacingMin: 30, spacingMax: 30,
      distanceMin: 10, distanceMax: 10, directionMinDegrees: 0, directionMaxDegrees: 0)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 200, y: 0), at: 0.1)

    let points = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first?.trunk.points)
    for index in 1..<(points.count - 1) {
      XCTAssertEqual(points[index].x, CGFloat(index) * 30 + 10, accuracy: 0.001)
      XCTAssertEqual(points[index].y, 0, accuracy: 0.001)
    }
  }

  func testConfiguredBendDirectionFollowsThePathHeading() {
    var engine = LightningTrailEngine(seed: 42)
    engine.updateBendOffsetConfiguration(
      spacingMin: 30, spacingMax: 30,
      distanceMin: 10, distanceMax: 10, directionMinDegrees: 0, directionMaxDegrees: 0)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 0, y: 200), at: 0.1)

    let points = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first?.trunk.points)
    for index in 1..<(points.count - 1) {
      XCTAssertEqual(points[index].x, 0, accuracy: 0.001)
      XCTAssertEqual(points[index].y, CGFloat(index) * 30 + 10, accuracy: 0.001)
    }
  }

  func testSignedBendDirectionSupportsASymmetricForwardCone() {
    var engine = LightningTrailEngine(seed: 42)
    engine.updateBendOffsetConfiguration(
      spacingMin: 30, spacingMax: 30,
      distanceMin: 10, distanceMax: 10, directionMinDegrees: -45, directionMaxDegrees: -45)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 200, y: 0), at: 0.1)

    let points = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first?.trunk.points)
    let component: CGFloat = 7.0710678118654755
    for index in 1..<(points.count - 1) {
      XCTAssertEqual(points[index].x, CGFloat(index) * 30 + component, accuracy: 0.001)
      XCTAssertEqual(points[index].y, -component, accuracy: 0.001)
    }
  }

  func testConfiguredBendSpacingControlsMajorBendDensity() {
    var engine = LightningTrailEngine(seed: 42)
    engine.updateBendOffsetConfiguration(
      spacingMin: 56, spacingMax: 56,
      distanceMin: 0, distanceMax: 0, directionMinDegrees: 0, directionMaxDegrees: 0)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 200, y: 0), at: 0.1)

    let points = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first?.trunk.points)
    XCTAssertEqual(points, [
      CGPoint(x: 0, y: 0), CGPoint(x: 56, y: 0), CGPoint(x: 112, y: 0),
      CGPoint(x: 168, y: 0), CGPoint(x: 200, y: 0),
    ])
  }

  func testChangingBendConfigurationDoesNotRewriteAnExistingBolt() {
    var engine = LightningTrailEngine(seed: 42)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 100, y: 0), at: 0.1)
    let initial = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first)

    engine.updateBendOffsetConfiguration(
      spacingMin: 30, spacingMax: 30,
      distanceMin: 24, distanceMax: 24, directionMinDegrees: 180, directionMaxDegrees: 180)
    engine.move(to: CGPoint(x: 130, y: 0), at: 0.2)
    let extended = try! XCTUnwrap(engine.frame(at: 0.2).bolts.first)

    XCTAssertEqual(
      Array(extended.trunk.points.prefix(initial.trunk.points.count - 1)),
      Array(initial.trunk.points.dropLast()))
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

  func testTrunkDoesNotInsertAdditionalInterBendOffsets() {
    var engine = LightningTrailEngine(seed: 42)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 200, y: 0), at: 0.1)

    let points = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first?.trunk.points)
    XCTAssertEqual(points.count, 8)
  }

  func testCompanionArcsAreThinAndAnchoredToTheTrunk() {
    var found = false
    for seed in 0..<200 {
      var engine = LightningTrailEngine(seed: UInt64(seed))
      engine.move(to: CGPoint(x: 0, y: 0), at: 0)
      engine.move(to: CGPoint(x: 400, y: 0), at: 0.1)
      guard let bolt = engine.frame(at: 0.1).bolts.first, let arc = bolt.arc else { continue }

      found = true
      XCTAssertEqual(arc.stroke.points.first, bolt.trunk.points.first)
      XCTAssertEqual(arc.stroke.points.last, bolt.trunk.points.last)
      XCTAssertEqual(arc.stroke.points.count, bolt.trunk.points.count)
      XCTAssertGreaterThanOrEqual(arc.widthScale, 0.25)
      XCTAssertLessThanOrEqual(arc.widthScale, 0.45)
      XCTAssertGreaterThanOrEqual(arc.opacity, 0.35)
      XCTAssertLessThanOrEqual(arc.opacity, 0.60)
      XCTAssertTrue(
        arc.stroke.points.dropFirst().dropLast().contains {
          distanceToPolyline($0, bolt.trunk.points) > 0.5
        })
      break
    }
    XCTAssertTrue(found)
  }

  func testCompanionArcsAreDeterministicAndFrozenAsTheBoltGrows() {
    var first = LightningTrailEngine(seed: 42)
    var second = LightningTrailEngine(seed: 42)
    for engineIndex in 0..<2 {
      if engineIndex == 0 {
        first.move(to: CGPoint(x: 0, y: 0), at: 0)
        first.move(to: CGPoint(x: 240, y: 0), at: 0.1)
      } else {
        second.move(to: CGPoint(x: 0, y: 0), at: 0)
        second.move(to: CGPoint(x: 240, y: 0), at: 0.1)
      }
    }
    let initial = try! XCTUnwrap(first.frame(at: 0.1).bolts.first)
    let sameSeed = try! XCTUnwrap(second.frame(at: 0.1).bolts.first)
    XCTAssertEqual(initial.arc, sameSeed.arc)

    first.move(to: CGPoint(x: 420, y: 30), at: 0.2)
    let extended = try! XCTUnwrap(first.frame(at: 0.2).bolts.first)
    let initialArc = try! XCTUnwrap(initial.arc)
    let extendedArc = try! XCTUnwrap(extended.arc)
    // The old head becomes an interior point when the route grows; every earlier
    // arc bend remains frozen and the new head is appended independently.
    XCTAssertEqual(
      Array(extendedArc.stroke.points.prefix(initialArc.stroke.points.count - 1)),
      Array(initialArc.stroke.points.dropLast()))
  }

  func testReducedMotionDoesNotGenerateCompanionArcs() {
    var engine = LightningTrailEngine(seed: 42)
    engine.setReduceMotion(true)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 240, y: 0), at: 0.1)

    let bolt = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first)
    XCTAssertNil(bolt.arc)
  }

  func testCompanionArcsDissipateInPlaceWithTheTrunk() {
    var engine = LightningTrailEngine(seed: 42)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 240, y: 0), at: 0.1)
    let initial = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first)
    guard let initialArc = initial.arc else {
      XCTFail("expected a companion arc")
      return
    }

    let stopped = try! XCTUnwrap(engine.frame(at: 0.35).bolts.first)
    let stoppedArc = try! XCTUnwrap(stopped.arc)
    XCTAssertEqual(stoppedArc.stroke, initialArc.stroke)
    XCTAssertTrue(zip(stoppedArc.segments, initialArc.segments).contains { $0.widthScale < $1.widthScale })
    XCTAssertTrue(engine.frame(at: 0.65).isEmpty)
  }

  func testEachBoltUsesOneContinuousLongCompanionArc() {
    var engine = LightningTrailEngine(seed: 99)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 1_600, y: 0), at: 0.1)

    let bolt = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first)
    let arc = try! XCTUnwrap(bolt.arc)
    let length = zip(arc.stroke.points, arc.stroke.points.dropFirst())
      .map { euclideanDistance($0, $1) }.reduce(0, +)
    XCTAssertGreaterThan(length, 1_600 * 0.50)
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

  func testExplicitStopStartsDissipationImmediately() {
    var engine = LightningTrailEngine(seed: 13)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 80, y: 0), at: 0.1)
    let active = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first)

    engine.stop(at: 0.11)
    let stopped = try! XCTUnwrap(engine.frame(at: 0.35).bolts.first)

    XCTAssertEqual(stopped.trunk, active.trunk)
    XCTAssertTrue(zip(stopped.segments, active.segments).contains { $0.widthScale < $1.widthScale })
  }

  func testMovesAfterExplicitStopAreIgnoredUntilMovementResumes() {
    var engine = LightningTrailEngine(seed: 14)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 80, y: 0), at: 0.1)
    engine.stop(at: 0.11)

    engine.move(to: CGPoint(x: 200, y: 0), at: 0.2)
    XCTAssertEqual(engine.frame(at: 0.2).bolts.first?.trunk.points.last, CGPoint(x: 80, y: 0))

    engine.resumeMovement()
    engine.move(to: CGPoint(x: 220, y: 0), at: 0.3)
    XCTAssertEqual(engine.frame(at: 0.3).bolts.count, 2)
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
    XCTAssertTrue(ratios.contains { $0 < 1 })
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

  private func euclideanDistance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
    hypot(lhs.x - rhs.x, lhs.y - rhs.y)
  }

  private func distanceToPolyline(_ point: CGPoint, _ points: [CGPoint]) -> CGFloat {
    zip(points, points.dropFirst()).map { start, end in
      let vector = subtract(end, start)
      let lengthSquared = vector.x * vector.x + vector.y * vector.y
      guard lengthSquared > 0 else { return euclideanDistance(point, start) }
      let projection = max(
        0, min(1, ((point.x - start.x) * vector.x + (point.y - start.y) * vector.y) / lengthSquared))
      let closest = CGPoint(x: start.x + vector.x * projection, y: start.y + vector.y * projection)
      return euclideanDistance(point, closest)
    }.min() ?? .greatestFiniteMagnitude
  }

  private func polylineLength(_ points: [CGPoint]) -> CGFloat {
    zip(points, points.dropFirst()).map { euclideanDistance($0, $1) }.reduce(0, +)
  }

  private func subtract(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
    CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
  }
}
