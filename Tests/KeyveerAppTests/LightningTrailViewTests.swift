import AppKit
import KeyveerRuntime
import XCTest

@testable import KeyveerApp

final class LightningTrailViewTests: XCTestCase {
  @MainActor
  func testBroadGlowRemainsVisibleTenPointsFromTrunk() throws {
    let width = 200
    let height = 80
    let view = LightningTrailView(
      frame: NSRect(x: 0, y: 0, width: width, height: height))
    view.drawingState = .init(
      frame: LightningTrailFrame(
        bolts: [
          RenderedLightningBolt(
            id: 1,
            trunk: LightningStroke(
              points: [CGPoint(x: 20, y: 40), CGPoint(x: 180, y: 40)]),
            alpha: 1,
            glowScale: 1)
        ]),
      canvasOrigin: .zero)

    let bitmap = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0))
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()

    let visibleGlow = try color(in: bitmap, x: 150, y: 50)
    let distantPixel = try color(in: bitmap, x: 150, y: 70)

    XCTAssertGreaterThan(visibleGlow.alphaComponent, 0.03)
    XCTAssertGreaterThan(visibleGlow.blueComponent, visibleGlow.redComponent)
    XCTAssertGreaterThan(visibleGlow.alphaComponent, distantPixel.alphaComponent)
  }

  @MainActor
  func testCustomTrailVisualSettingsAreCarriedByDrawingState() throws {
    let settings = TrailVisualSettings(
      coreWidth: 6,
      blurRadius: 24,
      coreColor: "#FFFFFF", outerGlowColor: "#FF0000", glowStrength: 1.5)
    let view = LightningTrailView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
    view.drawingState = .init(
      frame: LightningTrailFrame(
        bolts: [
          RenderedLightningBolt(
            id: 2,
            trunk: LightningStroke(
              points: [CGPoint(x: 20, y: 40), CGPoint(x: 180, y: 40)]),
            alpha: 1,
            glowScale: 1)
        ]),
      canvasOrigin: .zero,
      visualSettings: settings)

    XCTAssertEqual(view.drawingState.visualSettings, settings)

    let bitmap = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 200,
        pixelsHigh: 80,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0))
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()

    let outerGlow = try color(in: bitmap, x: 150, y: 50)
    XCTAssertGreaterThan(outerGlow.redComponent, outerGlow.blueComponent)
    XCTAssertGreaterThan(outerGlow.alphaComponent, 0.03)
  }

  @MainActor
  func testAnExistingBoltIDCanExtendItsCachedGeometry() throws {
    let view = LightningTrailView(frame: NSRect(x: 0, y: 0, width: 220, height: 80))
    view.drawingState = .init(
      frame: LightningTrailFrame(
        bolts: [
          RenderedLightningBolt(
            id: 3,
            trunk: LightningStroke(points: [CGPoint(x: 20, y: 40), CGPoint(x: 80, y: 40)]),
            alpha: 1,
            glowScale: 1)
        ]),
      canvasOrigin: .zero)
    view.drawingState = .init(
      frame: LightningTrailFrame(
        bolts: [
          RenderedLightningBolt(
            id: 3,
            trunk: LightningStroke(
              points: [CGPoint(x: 20, y: 40), CGPoint(x: 80, y: 40), CGPoint(x: 200, y: 40)]),
            alpha: 1,
            glowScale: 1)
        ]),
      canvasOrigin: .zero)

    let bitmap = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 220,
        pixelsHigh: 80,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0))
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()

    XCTAssertGreaterThan(try color(in: bitmap, x: 180, y: 40).alphaComponent, 0.1)
  }

  @MainActor
  func testCompanionArcIsRenderedAlongsideTheTrunk() throws {
    let view = LightningTrailView(frame: NSRect(x: 0, y: 0, width: 220, height: 120))
    let arc = RenderedLightningArc(
      stroke: LightningStroke(
        points: [CGPoint(x: 80, y: 60), CGPoint(x: 92, y: 72), CGPoint(x: 110, y: 64)]),
      segments: [
        RenderedLightningSegment(
          start: CGPoint(x: 80, y: 60), end: CGPoint(x: 92, y: 72), widthScale: 0.35),
        RenderedLightningSegment(
          start: CGPoint(x: 92, y: 72), end: CGPoint(x: 110, y: 64), widthScale: 0.35),
      ],
      widthScale: 0.35,
      opacity: 0.5)
    view.drawingState = .init(
      frame: LightningTrailFrame(
        bolts: [
          RenderedLightningBolt(
            id: 4,
            trunk: LightningStroke(points: [CGPoint(x: 20, y: 60), CGPoint(x: 180, y: 60)]),
            arcs: [arc],
            alpha: 1,
            glowScale: 1)
        ]),
      canvasOrigin: .zero)

    let bitmap = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 220,
        pixelsHigh: 120,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0))
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()

    XCTAssertGreaterThan(try color(in: bitmap, x: 100, y: 66).alphaComponent, 0.02)
  }

  @MainActor
  func testCompanionArcUsesStraightSegmentsThroughItsIndependentBendPoints() throws {
    let view = LightningTrailView(frame: NSRect(x: 0, y: 0, width: 180, height: 140))
    let points = [
      CGPoint(x: 40, y: 100), CGPoint(x: 80, y: 40), CGPoint(x: 120, y: 100)
    ]
    let arc = RenderedLightningArc(
      stroke: LightningStroke(points: points),
      segments: renderedArcSegments(for: points),
      widthScale: 0.35,
      opacity: 1)
    view.drawingState = .init(
      frame: LightningTrailFrame(
        bolts: [
          RenderedLightningBolt(
            id: 6,
            trunk: LightningStroke(points: [CGPoint(x: 20, y: 120), CGPoint(x: 140, y: 120)]),
            arcs: [arc],
            alpha: 1,
            glowScale: 1)
        ]),
      canvasOrigin: .zero,
      visualSettings: TrailVisualSettings(
        coreWidth: 3.5, blurRadius: 0, outerGlowOpacity: 0, glowStrength: 0))

    let bitmap = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 180,
        pixelsHigh: 140,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0))
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()

    // The bitmap's y-axis is flipped relative to the view. A polyline would render the chord
    // near bitmap y=66 at x=58, while the old curved path was near bitmap y=74.
    XCTAssertGreaterThan(try color(in: bitmap, x: 40, y: 40).alphaComponent, 0.2)
    XCTAssertGreaterThan(try color(in: bitmap, x: 80, y: 100).alphaComponent, 0.2)
    XCTAssertGreaterThan(try color(in: bitmap, x: 120, y: 40).alphaComponent, 0.2)
    XCTAssertGreaterThan(try color(in: bitmap, x: 58, y: 67).alphaComponent, 0.2)
    XCTAssertLessThan(try color(in: bitmap, x: 58, y: 74).alphaComponent, 0.02)
  }

  @MainActor
  func testCompanionArcIsRenderedWhenTheTrunkIsHidden() throws {
    let view = LightningTrailView(frame: NSRect(x: 0, y: 0, width: 220, height: 120))
    let arc = RenderedLightningArc(
      stroke: LightningStroke(
        points: [CGPoint(x: 80, y: 60), CGPoint(x: 92, y: 72), CGPoint(x: 110, y: 64)]),
      segments: [
        RenderedLightningSegment(
          start: CGPoint(x: 80, y: 60), end: CGPoint(x: 92, y: 72), widthScale: 0.35),
        RenderedLightningSegment(
          start: CGPoint(x: 92, y: 72), end: CGPoint(x: 110, y: 64), widthScale: 0.35),
      ],
      widthScale: 0.35,
      opacity: 0.5)
    view.drawingState = .init(
      frame: LightningTrailFrame(
        bolts: [
          RenderedLightningBolt(
            id: 5,
            trunk: LightningStroke(points: [CGPoint(x: 20, y: 60), CGPoint(x: 180, y: 60)]),
            trunkVisible: false,
            arcs: [arc],
            alpha: 1,
            glowScale: 1)
        ]),
      canvasOrigin: .zero)

    let bitmap = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 220,
        pixelsHigh: 120,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0))
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()

    XCTAssertGreaterThan(try color(in: bitmap, x: 100, y: 66).alphaComponent, 0.005)
  }

  private func color(in bitmap: NSBitmapImageRep, x: Int, y: Int) throws -> NSColor {
    try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
  }

  private func renderedArcSegments(for points: [CGPoint]) -> [RenderedLightningSegment] {
    var segments: [RenderedLightningSegment] = []
    for (start, end) in zip(points, points.dropFirst()) {
      let length = hypot(end.x - start.x, end.y - start.y)
      let count = max(1, Int(ceil(length / 4)))
      for subdivision in 0..<count {
        let startProgress = CGFloat(subdivision) / CGFloat(count)
        let endProgress = CGFloat(subdivision + 1) / CGFloat(count)
        let delta = CGPoint(x: end.x - start.x, y: end.y - start.y)
        segments.append(
          RenderedLightningSegment(
            start: CGPoint(
              x: start.x + delta.x * startProgress,
              y: start.y + delta.y * startProgress),
            end: CGPoint(
              x: start.x + delta.x * endProgress,
              y: start.y + delta.y * endProgress),
            widthScale: 0.35))
      }
    }
    return segments
  }
}
