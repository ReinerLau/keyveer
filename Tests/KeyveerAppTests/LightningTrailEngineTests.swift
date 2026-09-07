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
    XCTAssertLessThanOrEqual(bolt.arcs.count, 2)
  }

  func testMovementBelowEightPointsDoesNotStartABolt() {
    var engine = LightningTrailEngine(seed: 1)

    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 7.9, y: 0), at: 0.1)

    XCTAssertTrue(engine.frame(at: 0.1).isEmpty)
  }

  func testDisablingMainTrunkHidesTrunkAndCompanionArcs() {
    var engine = LightningTrailEngine(seed: 11)
    engine.updateBendOffsetConfiguration(
      spacingMin: 30, spacingMax: 30,
      distanceMin: 6, distanceMax: 24, directionMinDegrees: -90, directionMaxDegrees: 90,
      arcGapMin: 24, arcGapMax: 24)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 40, y: 0), at: 0.1)
    XCTAssertFalse(engine.frame(at: 0.1).isEmpty)

    engine.setMainTrunkEnabled(false)
    let slowFrame = engine.frame(at: 0.1)
    XCTAssertFalse(slowFrame.isEmpty)
    XCTAssertFalse(try! XCTUnwrap(slowFrame.bolts.first).trunkVisible)
    XCTAssertFalse(try! XCTUnwrap(slowFrame.bolts.first).arcs.isEmpty)
    XCTAssertTrue(try! XCTUnwrap(slowFrame.bolts.first).arcs.allSatisfy { !$0.visible })
    engine.move(to: CGPoint(x: 80, y: 0), at: 0.2)
    XCTAssertFalse(try! XCTUnwrap(engine.frame(at: 0.2).bolts.first).trunkVisible)
    XCTAssertTrue(
      try! XCTUnwrap(engine.frame(at: 0.2).bolts.first).arcs.allSatisfy { !$0.visible })

    engine.setMainTrunkEnabled(true)
    let resumedFrame = engine.frame(at: 0.2)
    XCTAssertTrue(resumedFrame.bolts.allSatisfy { bolt in
      !bolt.trunkVisible && bolt.arcs.allSatisfy { !$0.visible }
    })
  }

  func testStoppedTrailKeepsCompanionArcsHiddenWhenDefaultSpeedStops() {
    var engine = LightningTrailEngine(seed: 11)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 40, y: 0), at: 0.1)
    engine.setMainTrunkEnabled(false)
    engine.stop(at: 0.1)

    let stoppedFrame = engine.frame(at: 0.1)
    XCTAssertFalse(stoppedFrame.isEmpty)
    XCTAssertTrue(stoppedFrame.bolts.allSatisfy { bolt in
      !bolt.trunkVisible && bolt.arcs.allSatisfy { !$0.visible }
    })
  }

  func testEnablingTrailAfterHiddenMovementStartsAtTheCurrentPoint() {
    var engine = LightningTrailEngine(seed: 19)
    engine.setMainTrunkEnabled(false)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 80, y: 0), at: 0.1)

    engine.setMainTrunkEnabled(true)
    engine.move(to: CGPoint(x: 100, y: 0), at: 0.15)

    let bolt = try! XCTUnwrap(engine.frame(at: 0.15).bolts.last)
    XCTAssertEqual(bolt.trunk.points.first, CGPoint(x: 80, y: 0))
    XCTAssertEqual(bolt.trunk.points.last, CGPoint(x: 100, y: 0))
  }

  func testTrunkFlickerIsDeterministicAndLastsOneOrTwoDisplayFrames() {
    let frameDuration = 1.0 / 60.0
    let first = trunkVisibilitySequence(seed: 73, frameDuration: frameDuration)
    let sameSeed = trunkVisibilitySequence(seed: 73, frameDuration: frameDuration)

    XCTAssertEqual(first, sameSeed)
    XCTAssertTrue(first.contains(false))

    var hiddenRunLength = 0
    for visible in first {
      if visible {
        XCTAssertLessThanOrEqual(hiddenRunLength, 2)
        hiddenRunLength = 0
      } else {
        hiddenRunLength += 1
      }
    }
    XCTAssertLessThanOrEqual(hiddenRunLength, 2)
  }

  func testConfiguredTrunkFlickerUsesTheConfiguredIntervalAndFrameCount() {
    let frameDuration = 1.0 / 60.0
    var engine = LightningTrailEngine(seed: 73)
    engine.updateTrunkFlickerConfiguration(
      intervalMin: 0.01, intervalMax: 0.01, framesMin: 3, framesMax: 3)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 400, y: 0), at: 0)

    var hiddenRunLength = 0
    var foundHiddenRun = false
    for index in 0...120 {
      let timestamp = Double(index) * frameDuration
      engine.move(to: CGPoint(x: 400 + CGFloat(index), y: 0), at: timestamp)
      let visible = engine.frame(at: timestamp, frameDuration: frameDuration)
        .bolts.first?.trunkVisible ?? true
      if visible {
        if hiddenRunLength > 0 {
          XCTAssertEqual(hiddenRunLength, 3)
          foundHiddenRun = true
          break
        }
      } else {
        hiddenRunLength += 1
      }
    }

    XCTAssertTrue(foundHiddenRun)
  }

  func testHiddenTrunkDoesNotHideCompanionArcs() throws {
    let frameDuration = 1.0 / 60.0
    var engine = LightningTrailEngine(seed: 73)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 400, y: 0), at: 0)

    for index in 0...240 {
      let timestamp = Double(index) * frameDuration
      engine.move(to: CGPoint(x: 400 + CGFloat(index), y: 0), at: timestamp)
      let frame = engine.frame(at: timestamp, frameDuration: frameDuration)
      guard let bolt = frame.bolts.first, !bolt.trunkVisible else { continue }
      XCTAssertTrue(bolt.arcs.contains(where: \.visible))
      return
    }

    XCTFail("Expected a hidden trunk frame")
  }

  func testCompanionArcFlickerIsIndependentFromTheTrunkAndOtherArcs() throws {
    var foundDifferenceFromTrunk = false
    var foundDifferenceBetweenArcs = false

    for seed in 0..<100 {
      var engine = LightningTrailEngine(seed: UInt64(seed))
      engine.updateBendOffsetConfiguration(
        spacingMin: 30, spacingMax: 30,
        distanceMin: 6, distanceMax: 24, directionMinDegrees: -90, directionMaxDegrees: 90,
        arcLengthMin: 80, arcLengthMax: 180, arcGapMin: 24, arcGapMax: 24,
        arcHoldMin: 0.20, arcHoldMax: 0.50)
      engine.updateTrunkFlickerConfiguration(
        intervalMin: 0.01, intervalMax: 0.01, framesMin: 1, framesMax: 1)
      engine.move(to: CGPoint(x: 0, y: 0), at: 0)
      engine.move(to: CGPoint(x: 400, y: 0), at: 0.01)

      for index in 0...120 {
        let timestamp = 0.02 + Double(index) / 60
        engine.move(to: CGPoint(x: 400 + CGFloat(index), y: 0), at: timestamp)
        guard let bolt = engine.frame(at: timestamp, frameDuration: 1.0 / 60).bolts.first else {
          continue
        }
        let arcVisibility = bolt.arcs.map(\.visible)
        if bolt.trunkVisible != arcVisibility.first {
          foundDifferenceFromTrunk = true
        }
        if Set(arcVisibility).count > 1 {
          foundDifferenceBetweenArcs = true
        }
      }
      if foundDifferenceFromTrunk && foundDifferenceBetweenArcs { break }
    }

    XCTAssertTrue(foundDifferenceFromTrunk)
    XCTAssertTrue(foundDifferenceBetweenArcs)
  }

  func testCompanionArcFlickerContinuesDuringItsIndependentHold() throws {
    var engine = LightningTrailEngine(seed: 73)
    engine.updateBendOffsetConfiguration(
      spacingMin: 30, spacingMax: 30,
      distanceMin: 0, distanceMax: 0, directionMinDegrees: 0, directionMaxDegrees: 0,
      arcLengthMin: 200, arcLengthMax: 200,
      arcGapMin: 24, arcGapMax: 24,
      arcHoldMin: 1, arcHoldMax: 1)
    engine.updateTrunkFlickerConfiguration(
      intervalMin: 0.01, intervalMax: 0.01, framesMin: 1, framesMax: 1)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 50, y: 0), at: 0.1)

    var foundHiddenArc = false
    for index in 0...60 {
      let timestamp = 0.21 + Double(index) / 60
      let frame = engine.frame(at: timestamp, frameDuration: 1.0 / 60)
      if frame.bolts.first?.arcs.contains(where: { !$0.visible }) == true {
        foundHiddenArc = true
        break
      }
    }
    XCTAssertTrue(foundHiddenArc)
  }

  func testStoppingOrReducingMotionDoesNotFlickerTheTrunk() throws {
    let frameDuration = 1.0 / 60.0
    var engine = LightningTrailEngine(seed: 73)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 400, y: 0), at: 0)
    engine.stop(at: 0.2)

    XCTAssertTrue(try XCTUnwrap(engine.frame(at: 0.2, frameDuration: frameDuration).bolts.first).trunkVisible)

    engine.setReduceMotion(true)
    engine.move(to: CGPoint(x: 0, y: 0), at: 1)
    engine.move(to: CGPoint(x: 400, y: 0), at: 1)
    for index in 0...240 {
      let timestamp = 1 + Double(index) * frameDuration
      engine.move(to: CGPoint(x: 400 + CGFloat(index), y: 0), at: timestamp)
      XCTAssertTrue(
        try XCTUnwrap(engine.frame(at: timestamp, frameDuration: frameDuration).bolts.first)
          .trunkVisible)
    }
  }

  private func trunkVisibilitySequence(
    seed: UInt64, frameDuration: TimeInterval
  ) -> [Bool] {
    var engine = LightningTrailEngine(seed: seed)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 400, y: 0), at: 0)

    return (0...240).map { index in
      let timestamp = Double(index) * frameDuration
      engine.move(to: CGPoint(x: 400 + CGFloat(index), y: 0), at: timestamp)
      return engine.frame(at: timestamp, frameDuration: frameDuration).bolts.first?.trunkVisible ?? true
    }
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
    first.updateBendOffsetConfiguration(
      spacingMin: 24, spacingMax: 36,
      distanceMin: 6, distanceMax: 24, directionMinDegrees: -90, directionMaxDegrees: 90)
    second.updateBendOffsetConfiguration(
      spacingMin: 24, spacingMax: 36,
      distanceMin: 6, distanceMax: 24, directionMinDegrees: -90, directionMaxDegrees: 90)
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
    engine.updateWidthConfiguration(
      trunkScaleMin: 0.45, trunkScaleMax: 1.6,
      arcScaleMin: 0.25, arcScaleMax: 0.45)
    engine.updateBendOffsetConfiguration(
      spacingMin: 24, spacingMax: 36,
      distanceMin: 6, distanceMax: 24, directionMinDegrees: -90, directionMaxDegrees: 90)
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

  func testConfiguredWidthRangesApplyIndependentlyToTrunkAndCompanionArcs() {
    var engine = LightningTrailEngine(seed: 42)
    engine.updateWidthConfiguration(
      trunkScaleMin: 0.70, trunkScaleMax: 0.80,
      arcScaleMin: 0.20, arcScaleMax: 0.30)
    engine.updateBendOffsetConfiguration(
      spacingMin: 30, spacingMax: 30,
      distanceMin: 6, distanceMax: 24, directionMinDegrees: -90, directionMaxDegrees: 90,
      arcGapMin: 24, arcGapMax: 24)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 400, y: 0), at: 0.1)

    let bolt = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first)
    XCTAssertTrue(bolt.segments.allSatisfy { (0.70...0.80).contains($0.widthScale) })
    XCTAssertFalse(bolt.arcs.isEmpty)
    XCTAssertTrue(bolt.arcs.allSatisfy { (0.20...0.30).contains($0.widthScale) })
  }

  func testTrunkDoesNotInsertAdditionalInterBendOffsets() {
    var engine = LightningTrailEngine(seed: 42)
    engine.updateBendOffsetConfiguration(
      spacingMin: 24, spacingMax: 36,
      distanceMin: 6, distanceMax: 24, directionMinDegrees: -90, directionMaxDegrees: 90)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 200, y: 0), at: 0.1)

    let points = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first?.trunk.points)
    XCTAssertEqual(points.count, 8)
  }

  func testCompanionArcsAreThinIndependentPolylinesThatFollowTheTrunkDirection() {
    var found = false
    for seed in 0..<200 {
      var engine = LightningTrailEngine(seed: UInt64(seed))
      engine.updateBendOffsetConfiguration(
        spacingMin: 30, spacingMax: 30,
        distanceMin: 6, distanceMax: 24, directionMinDegrees: -.pi * 180 / .pi,
        directionMaxDegrees: .pi * 180 / .pi,
        arcGapMin: 24, arcGapMax: 24)
      engine.move(to: CGPoint(x: 0, y: 0), at: 0)
      engine.move(to: CGPoint(x: 400, y: 0), at: 0.1)
      guard let bolt = engine.frame(at: 0.1).bolts.first, let arc = bolt.arcs.first else { continue }

      found = true
      XCTAssertGreaterThan(arc.startDistance, 0)
      XCTAssertGreaterThan(arc.endDistance, arc.startDistance)
      XCTAssertFalse(bolt.trunk.points.contains(arc.stroke.points.first!))
      XCTAssertFalse(bolt.trunk.points.contains(arc.stroke.points.last!))
      XCTAssertTrue(arc.stroke.points.dropFirst().dropLast().contains { point in
        !bolt.trunk.points.contains(point)
      })
      let arcDirection = arc.stroke.points.last!.x - arc.stroke.points.first!.x
      let trunkDirection = bolt.trunk.points.last!.x - bolt.trunk.points.first!.x
      XCTAssertGreaterThan(arcDirection * trunkDirection, 0)
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
    first.updateBendOffsetConfiguration(
      spacingMin: 30, spacingMax: 30,
      distanceMin: 6, distanceMax: 24, directionMinDegrees: -90, directionMaxDegrees: 90,
      arcGapMin: 200, arcGapMax: 200)
    second.updateBendOffsetConfiguration(
      spacingMin: 30, spacingMax: 30,
      distanceMin: 6, distanceMax: 24, directionMinDegrees: -90, directionMaxDegrees: 90,
      arcGapMin: 200, arcGapMax: 200)
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
    XCTAssertEqual(initial.arcs, sameSeed.arcs)

    first.move(to: CGPoint(x: 300, y: 30), at: 0.15)
    let extended = try! XCTUnwrap(first.frame(at: 0.15).bolts.first)
    XCTAssertEqual(extended.arcs.map(\.id), initial.arcs.map(\.id))
    XCTAssertEqual(
      Array(extended.arcs.first!.stroke.points.prefix(initial.arcs.first!.stroke.points.count)),
      initial.arcs.first!.stroke.points)
    XCTAssertGreaterThan(extended.arcs.first?.endDistance ?? 0, initial.arcs.first?.endDistance ?? 0)
  }

  func testGeneratingANewCompanionArcDoesNotFreezeThePreviousArc() throws {
    var engine = LightningTrailEngine(seed: 42)
    engine.updateBendOffsetConfiguration(
      spacingMin: 30, spacingMax: 30,
      distanceMin: 6, distanceMax: 24, directionMinDegrees: -90, directionMaxDegrees: 90,
      arcLengthMin: 200, arcLengthMax: 200,
      arcGapMin: 70, arcGapMax: 70,
      arcHoldMin: 1, arcHoldMax: 1)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 100, y: 0), at: 0.1)
    let beforeReplacement = try XCTUnwrap(engine.frame(at: 0.1).bolts.first?.arcs)
    let oldArc = try XCTUnwrap(beforeReplacement.first)

    engine.move(to: CGPoint(x: 150, y: 0), at: 0.15)
    let afterGeneration = try XCTUnwrap(engine.frame(at: 0.15).bolts.first?.arcs)
    XCTAssertEqual(afterGeneration.count, 2)
    let growingArc = try XCTUnwrap(afterGeneration.first { $0.id == oldArc.id })
    XCTAssertGreaterThan(growingArc.endDistance, oldArc.endDistance)

    engine.move(to: CGPoint(x: 200, y: 0), at: 0.2)
    let afterGrowth = try XCTUnwrap(engine.frame(at: 0.2).bolts.first?.arcs)
    let stillGrowingArc = try XCTUnwrap(afterGrowth.first { $0.id == oldArc.id })
    XCTAssertGreaterThan(stillGrowingArc.endDistance, growingArc.endDistance)
  }

  func testCompanionArcsRespectTheirConfiguredLengthLimit() throws {
    var engine = LightningTrailEngine(seed: 42)
    engine.updateBendOffsetConfiguration(
      spacingMin: 30, spacingMax: 30,
      distanceMin: 6, distanceMax: 24, directionMinDegrees: -90, directionMaxDegrees: 90,
      arcLengthMin: 80, arcLengthMax: 80,
      arcGapMin: 24, arcGapMax: 24)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 40, y: 0), at: 0.1)
    engine.move(to: CGPoint(x: 400, y: 0), at: 0.15)

    let arc = try XCTUnwrap(engine.frame(at: 0.15).bolts.first?.arcs.first)
    XCTAssertEqual(arc.endDistance - arc.startDistance, 80, accuracy: 0.001)
    XCTAssertLessThan(arc.stroke.points.last!.x, 150)
  }

  func testCompanionArcGenerationTimingIsRandomButDeterministic() throws {
    func firstArcStart(seed: UInt64) -> CGFloat? {
      var engine = LightningTrailEngine(seed: seed)
      engine.updateBendOffsetConfiguration(
        spacingMin: 30, spacingMax: 30,
        distanceMin: 6, distanceMax: 24, directionMinDegrees: -90, directionMaxDegrees: 90,
        arcGapMin: 24, arcGapMax: 72)
      engine.move(to: CGPoint(x: 0, y: 0), at: 0)
      engine.move(to: CGPoint(x: 400, y: 0), at: 0.1)
      return engine.frame(at: 0.1).bolts.first?.arcs.first?.startDistance
    }

    let first = try XCTUnwrap(firstArcStart(seed: 1))
    XCTAssertEqual(first, try XCTUnwrap(firstArcStart(seed: 1)))
    XCTAssertNotEqual(first, try XCTUnwrap(firstArcStart(seed: 2)))
  }

  func testCompanionArcsAreNotLimitedOrReplaced() throws {
    var engine = LightningTrailEngine(seed: 42)
    engine.updateBendOffsetConfiguration(
      spacingMin: 30, spacingMax: 30,
      distanceMin: 6, distanceMax: 24, directionMinDegrees: -90, directionMaxDegrees: 90,
      arcGapMin: 24, arcGapMax: 24)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 100, y: 0), at: 0.1)
    let initial = try XCTUnwrap(engine.frame(at: 0.1).bolts.first?.arcs)
    XCTAssertGreaterThan(initial.count, 2)

    engine.move(to: CGPoint(x: 160, y: 0), at: 0.15)
    let extended = try XCTUnwrap(engine.frame(at: 0.15).bolts.first?.arcs)
    XCTAssertGreaterThanOrEqual(extended.count, initial.count)
    XCTAssertTrue(extended.map(\.id).contains(initial.first!.id))
  }

  func testReducedMotionDoesNotGenerateCompanionArcs() {
    var engine = LightningTrailEngine(seed: 42)
    engine.setReduceMotion(true)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 240, y: 0), at: 0.1)

    let bolt = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first)
    XCTAssertTrue(bolt.arcs.isEmpty)
  }

  func testCompanionArcsDissipateIndependentlyFromTheTrunk() {
    var engine = LightningTrailEngine(seed: 42)
    engine.updateBendOffsetConfiguration(
      spacingMin: 30, spacingMax: 30,
      distanceMin: 6, distanceMax: 24, directionMinDegrees: -90, directionMaxDegrees: 90,
      arcLengthMin: 40, arcLengthMax: 40,
      arcGapMin: 24, arcGapMax: 24,
      arcHoldMin: 0.4, arcHoldMax: 0.4)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 240, y: 0), at: 0.1)
    let initial = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first)
    guard let initialArc = initial.arcs.first else {
      XCTFail("expected a companion arc")
      return
    }

    let stopped = try! XCTUnwrap(engine.frame(at: 0.35).bolts.first)
    let stoppedArc = try! XCTUnwrap(stopped.arcs.first)
    XCTAssertEqual(stoppedArc.stroke, initialArc.stroke)
    XCTAssertTrue(zip(stoppedArc.segments, initialArc.segments).contains { $0.widthScale < $1.widthScale })
    XCTAssertTrue(engine.frame(at: 0.7).bolts.first?.arcs.isEmpty ?? true)
  }

  func testLongRoutesKeepAllNonExpiredCompanionArcsFromTheSameMovement() {
    var engine = LightningTrailEngine(seed: 99)
    engine.updateBendOffsetConfiguration(
      spacingMin: 30, spacingMax: 30,
      distanceMin: 6, distanceMax: 24, directionMinDegrees: -90, directionMaxDegrees: 90,
      arcLengthMin: 40, arcLengthMax: 40,
      arcGapMin: 24, arcGapMax: 24,
      arcHoldMin: 1, arcHoldMax: 1)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 1_600, y: 0), at: 0.1)

    let bolt = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first)
    XCTAssertGreaterThan(bolt.arcs.count, 2)
    XCTAssertLessThan(bolt.arcs[0].startDistance, bolt.arcs[1].startDistance)
    XCTAssertGreaterThan(bolt.arcs[0].endDistance, bolt.arcs[0].startDistance)
    XCTAssertGreaterThan(bolt.arcs[1].endDistance, bolt.arcs[1].startDistance)
  }

  func testCompanionArcUsesConfiguredRandomLengthAndStopsGrowingAtThatLength() throws {
    var engine = LightningTrailEngine(seed: 42)
    engine.updateBendOffsetConfiguration(
      spacingMin: 30, spacingMax: 30,
      distanceMin: 0, distanceMax: 0, directionMinDegrees: 0, directionMaxDegrees: 0,
      arcLengthMin: 40, arcLengthMax: 40,
      arcGapMin: 24, arcGapMax: 24,
      arcHoldMin: 0.2, arcHoldMax: 0.5)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 50, y: 0), at: 0.1)
    let growing = try XCTUnwrap(engine.frame(at: 0.1).bolts.first?.arcs.first)
    XCTAssertEqual(growing.endDistance - growing.startDistance, 26, accuracy: 0.001)

    engine.move(to: CGPoint(x: 80, y: 0), at: 0.15)
    let stopped = try XCTUnwrap(engine.frame(at: 0.15).bolts.first?.arcs.first)
    XCTAssertEqual(stopped.endDistance - stopped.startDistance, 40, accuracy: 0.001)

    engine.move(to: CGPoint(x: 140, y: 0), at: 0.2)
    let unchanged = try XCTUnwrap(engine.frame(at: 0.2).bolts.first?.arcs.first)
    XCTAssertEqual(unchanged, stopped)
  }

  func testUnfinishedCompanionArcStartsItsHoldTimerWhenTheTrunkStops() throws {
    var engine = LightningTrailEngine(seed: 42)
    engine.updateBendOffsetConfiguration(
      spacingMin: 30, spacingMax: 30,
      distanceMin: 0, distanceMax: 0, directionMinDegrees: 0, directionMaxDegrees: 0,
      arcLengthMin: 200, arcLengthMax: 200,
      arcGapMin: 24, arcGapMax: 24,
      arcHoldMin: 0.2, arcHoldMax: 0.2)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 50, y: 0), at: 0.1)
    let beforeStop = try XCTUnwrap(engine.frame(at: 0.1).bolts.first?.arcs.first)

    let duringHold = try XCTUnwrap(engine.frame(at: 0.29).bolts.first?.arcs.first)
    XCTAssertEqual(duringHold.stroke, beforeStop.stroke)
    XCTAssertFalse(engine.frame(at: 0.31).isEmpty)
    XCTAssertTrue(engine.frame(at: 0.41).bolts.first?.arcs.isEmpty ?? true)
  }

  func testCompanionArcsExpireIndependentlyOfEachOther() throws {
    var engine = LightningTrailEngine(seed: 42)
    engine.updateBendOffsetConfiguration(
      spacingMin: 30, spacingMax: 30,
      distanceMin: 0, distanceMax: 0, directionMinDegrees: 0, directionMaxDegrees: 0,
      arcLengthMin: 40, arcLengthMax: 40,
      arcGapMin: 100, arcGapMax: 100,
      arcHoldMin: 0.2, arcHoldMax: 0.2)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 130, y: 0), at: 0.1)
    engine.move(to: CGPoint(x: 160, y: 0), at: 0.19)
    engine.move(to: CGPoint(x: 260, y: 0), at: 0.28)

    let beforeExpiry = try XCTUnwrap(engine.frame(at: 0.38).bolts.first?.arcs)
    XCTAssertEqual(beforeExpiry.count, 2)
    let afterFirstExpiry = try XCTUnwrap(engine.frame(at: 0.41).bolts.first?.arcs)
    XCTAssertEqual(afterFirstExpiry.count, 1)
    XCTAssertGreaterThan(afterFirstExpiry[0].startDistance, beforeExpiry[0].startDistance)
    XCTAssertEqual(engine.frame(at: 0.51).bolts.first?.arcs.count, 0)
  }

  func testCompanionArcsRemainAfterTheTrunkHasDissipated() throws {
    var engine = LightningTrailEngine(seed: 42)
    engine.updateBendOffsetConfiguration(
      spacingMin: 30, spacingMax: 30,
      distanceMin: 0, distanceMax: 0, directionMinDegrees: 0, directionMaxDegrees: 0,
      arcLengthMin: 200, arcLengthMax: 200,
      arcGapMin: 24, arcGapMax: 24,
      arcHoldMin: 1, arcHoldMax: 1)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 50, y: 0), at: 0.1)

    let frame = engine.frame(at: 0.76)
    XCTAssertEqual(frame.bolts.count, 1)
    XCTAssertFalse(frame.bolts[0].arcs.isEmpty)
    XCTAssertTrue(frame.bolts[0].segments.allSatisfy { $0.widthScale == 0 })
  }

  func testLongRoutesKeepAllNonExpiredCompanionArcs() throws {
    var engine = LightningTrailEngine(seed: 99)
    engine.updateBendOffsetConfiguration(
      spacingMin: 30, spacingMax: 30,
      distanceMin: 0, distanceMax: 0, directionMinDegrees: 0, directionMaxDegrees: 0,
      arcLengthMin: 40, arcLengthMax: 40,
      arcGapMin: 24, arcGapMax: 24,
      arcHoldMin: 1, arcHoldMax: 1)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 1_600, y: 0), at: 0.1)

    let arcs = try XCTUnwrap(engine.frame(at: 0.1).bolts.first?.arcs)
    XCTAssertGreaterThan(arcs.count, 2)
    XCTAssertEqual(Set(arcs.map(\.id)).count, arcs.count)
  }

  func testArcThatIsCrossedByALargeMoveContinuesToTheCurrentEndpoint() {
    var engine = LightningTrailEngine(seed: 7)
    engine.updateBendOffsetConfiguration(
      spacingMin: 20, spacingMax: 20,
      distanceMin: 0, distanceMax: 0,
      directionMinDegrees: 0, directionMaxDegrees: 0,
      arcLengthMin: 80, arcLengthMax: 80,
      arcGapMin: 24, arcGapMax: 24)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 50, y: 0), at: 0.1)
    let partial = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first?.arcs.first)
    XCTAssertGreaterThan(partial.stroke.points.last!.x, partial.stroke.points.first!.x)

    engine.move(to: CGPoint(x: 200, y: 0), at: 0.15)
    let arcs = try! XCTUnwrap(engine.frame(at: 0.15).bolts.first?.arcs)
    XCTAssertTrue(arcs.contains { $0.stroke.points.last!.x > 190 })
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

  func testStoppedHiddenTrunkDoesNotReappearWhenVisibilityChangesLater() throws {
    var engine = LightningTrailEngine(seed: 15)
    engine.setMainTrunkEnabled(false)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 80, y: 0), at: 0.1)
    engine.stop(at: 0.11)

    engine.setMainTrunkEnabled(true)

    XCTAssertFalse(try XCTUnwrap(engine.frame(at: 0.35).bolts.first).trunkVisible)
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

  func testNewMovementCanGrowBesideAnOlderBoltWithIndependentArcs() {
    var engine = LightningTrailEngine(seed: 7)
    engine.updateBendOffsetConfiguration(
      spacingMin: 30, spacingMax: 30,
      distanceMin: 6, distanceMax: 24, directionMinDegrees: -90, directionMaxDegrees: 90,
      arcLengthMin: 40, arcLengthMax: 40,
      arcGapMin: 24, arcGapMax: 24,
      arcHoldMin: 1, arcHoldMax: 1)
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
    XCTAssertEqual(afterSecondStop.count, 2)
    XCTAssertTrue(afterSecondStop.contains { $0.id == firstID })
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
