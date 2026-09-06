import AppKit
import KeyveerRuntime
import XCTest

@testable import KeyveerApp

final class GlowingMarkerViewTests: XCTestCase {
  @MainActor
  func testGlowRemainsVisibleAndFadesBeyondTheSolidMarker() throws {
    let side = 28
    let view = GlowingMarkerView(frame: NSRect(x: 0, y: 0, width: side, height: side))
    let bitmap = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: side,
        pixelsHigh: side,
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

    let center = try color(in: bitmap, x: 14, y: 14)
    let coreEdge = try color(in: bitmap, x: 17, y: 14)
    let middleGlow = try color(in: bitmap, x: 19, y: 14)
    let outerGlow = try color(in: bitmap, x: 20, y: 14)
    let edge = try color(in: bitmap, x: 23, y: 14)

    XCTAssertGreaterThan(center.redComponent, 0.9)
    XCTAssertGreaterThan(center.greenComponent, 0.9)
    XCTAssertGreaterThan(center.blueComponent, 0.9)
    XCTAssertGreaterThan(coreEdge.redComponent, 0.5)
    XCTAssertGreaterThan(coreEdge.greenComponent, 0.8)
    XCTAssertGreaterThan(coreEdge.blueComponent, 0.8)
    XCTAssertGreaterThan(middleGlow.alphaComponent, 0.06)
    XCTAssertGreaterThan(outerGlow.alphaComponent, 0.02)
    XCTAssertGreaterThan(middleGlow.alphaComponent, outerGlow.alphaComponent)
    XCTAssertGreaterThan(outerGlow.alphaComponent, edge.alphaComponent)
  }

  @MainActor
  func testCustomMarkerVisualSettingsAffectGeometryAndColor() throws {
    let settings = MarkerVisualSettings(
      coreDiameter: 9, glowRadius: 12,
      coreColor: "#FFFFFF", outerGlowColor: "#00FF00")
    let view = GlowingMarkerView(
      frame: NSRect(x: 0, y: 0, width: 32, height: 32), visualSettings: settings)
    XCTAssertEqual(view.visualSettings, settings)

    let bitmap = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 32,
        pixelsHigh: 32,
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

    let outerGlow = try color(in: bitmap, x: 21, y: 16)
    XCTAssertGreaterThan(outerGlow.greenComponent, outerGlow.redComponent)
    XCTAssertGreaterThan(outerGlow.greenComponent, outerGlow.blueComponent)
    XCTAssertGreaterThan(outerGlow.alphaComponent, 0.05)
  }

  @MainActor
  func testLargeGaussianGlowDoesNotFlattenAtCanvasEdge() throws {
    let settings = MarkerVisualSettings(coreDiameter: 20, glowRadius: 21)
    let side = Int(ceil(GlowingMarkerView.canvasSize(for: settings)))
    let view = GlowingMarkerView(
      frame: NSRect(x: 0, y: 0, width: side, height: side), visualSettings: settings)
    let bitmap = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: side,
        pixelsHigh: side,
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

    let edge = try color(in: bitmap, x: 0, y: side / 2)
    let nearEdge = try color(in: bitmap, x: 30, y: side / 2)
    XCTAssertLessThan(edge.alphaComponent, 0.01)
    XCTAssertGreaterThan(nearEdge.alphaComponent, edge.alphaComponent)
  }

  @MainActor
  func testGlowOpacityControlsRenderedAlpha() throws {
    let low = MarkerVisualSettings(glowRadius: 12, outerGlowOpacity: 0.2)
    let high = MarkerVisualSettings(glowRadius: 12, outerGlowOpacity: 0.8)
    let lowAlpha = try renderedAlpha(for: low, offset: 12)
    let highAlpha = try renderedAlpha(for: high, offset: 12)
    XCTAssertGreaterThan(highAlpha, lowAlpha)
  }

  @MainActor
  func testGlowStrengthControlsRenderedAlpha() throws {
    let low = MarkerVisualSettings(glowRadius: 12, outerGlowOpacity: 1, glowStrength: 0.5)
    let high = MarkerVisualSettings(glowRadius: 12, outerGlowOpacity: 1, glowStrength: 2)
    let lowAlpha = try renderedAlpha(for: low, offset: 12)
    let highAlpha = try renderedAlpha(for: high, offset: 12)
    XCTAssertGreaterThan(highAlpha, lowAlpha)
  }

  @MainActor
  private func renderedAlpha(for settings: MarkerVisualSettings, offset: Int) throws -> CGFloat {
    let side = Int(ceil(GlowingMarkerView.canvasSize(for: settings)))
    let view = GlowingMarkerView(
      frame: NSRect(x: 0, y: 0, width: side, height: side), visualSettings: settings)
    let bitmap = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: side,
        pixelsHigh: side,
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
    return try color(in: bitmap, x: side / 2 + offset, y: side / 2).alphaComponent
  }

  private func color(in bitmap: NSBitmapImageRep, x: Int, y: Int) throws -> NSColor {
    try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
  }
}
