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

  private func color(in bitmap: NSBitmapImageRep, x: Int, y: Int) throws -> NSColor {
    try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
  }
}
