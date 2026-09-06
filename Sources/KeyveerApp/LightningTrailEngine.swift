import CoreGraphics
import Foundation

struct LightningStroke: Equatable {
  let points: [CGPoint]
}

struct RenderedLightningSegment: Equatable {
  let start: CGPoint
  let end: CGPoint
  let widthScale: CGFloat
}

struct LightningSegmentProfile: Equatable {
  let start: CGPoint
  let end: CGPoint
  let baseWidthScale: CGFloat
  let dissipationDelay: TimeInterval
  let dissipationDuration: TimeInterval
}

struct LightningBolt: Equatable {
  let id: UInt64
  let seed: UInt64
  let trunk: LightningStroke
  let segments: [LightningSegmentProfile]
  let createdAt: TimeInterval
  let stoppedAt: TimeInterval?
  let glowScale: CGFloat
}

struct RenderedLightningBolt: Equatable {
  let id: UInt64
  let trunk: LightningStroke
  let segments: [RenderedLightningSegment]
  let alpha: CGFloat
  let glowScale: CGFloat

  init(
    id: UInt64,
    trunk: LightningStroke,
    segments: [RenderedLightningSegment]? = nil,
    alpha: CGFloat,
    glowScale: CGFloat
  ) {
    self.id = id
    self.trunk = trunk
    self.segments = segments ?? zip(trunk.points, trunk.points.dropFirst()).map { start, end in
      RenderedLightningSegment(start: start, end: end, widthScale: 1)
    }
    self.alpha = alpha
    self.glowScale = glowScale
  }
}

struct LightningTrailFrame: Equatable {
  let bolts: [RenderedLightningBolt]

  static let empty = LightningTrailFrame(bolts: [])
  var isEmpty: Bool { bolts.isEmpty }
}

struct LightningTrailEngine {
  private struct Sample: Equatable {
    let point: CGPoint
  }

  private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
      state = seed
    }

    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var value = state
      value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
      value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
      return value ^ (value >> 31)
    }

    mutating func unit() -> CGFloat {
      CGFloat(Double(next() >> 11) / Double(1 << 53))
    }

    mutating func value(in range: ClosedRange<CGFloat>) -> CGFloat {
      range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }
  }

  private static let standardLifetime: TimeInterval = 0.45
  private static let reducedMotionLifetime: TimeInterval = 0.15
  private static let stopDelay: TimeInterval = 0.10
  private static let minimumSpan: CGFloat = 8
  private static let growthSpacing: CGFloat = 18

  private var samples: [Sample] = []
  private var bolts: [LightningBolt] = []
  private var random: SplitMix64
  private var lastMovementTime: TimeInterval?
  private var lastKnownPoint: CGPoint?
  private var nextBoltID: UInt64 = 0
  private(set) var reduceMotion = false
  private var movementSuppressed = false

  init(seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)) {
    random = SplitMix64(seed: seed)
  }

  mutating func setReduceMotion(_ enabled: Bool) {
    guard enabled != reduceMotion else { return }
    reduceMotion = enabled
    clear()
  }

  mutating func clear() {
    samples.removeAll(keepingCapacity: true)
    bolts.removeAll(keepingCapacity: true)
    lastMovementTime = nil
    lastKnownPoint = nil
    movementSuppressed = false
  }

  mutating func resumeMovement() {
    movementSuppressed = false
  }

  mutating func move(to point: CGPoint, at timestamp: TimeInterval) {
    prune(at: timestamp)
    guard !movementSuppressed else {
      lastKnownPoint = point
      return
    }
    guard lastKnownPoint != point else { return }
    if samples.isEmpty, let lastKnownPoint {
      samples.append(Sample(point: lastKnownPoint))
    }
    samples.append(Sample(point: point))
    lastKnownPoint = point
    lastMovementTime = timestamp
    emitIfReady(at: timestamp)
  }

  /// Ends the current continuous movement immediately.
  ///
  /// Physical pointer input still uses the stationary-time fallback in `frame(at:)`, while
  /// keyboard movement can call this when its final movement key is released.
  mutating func stop(at timestamp: TimeInterval) {
    prune(at: timestamp)
    movementSuppressed = true
    guard let activeIndex = bolts.firstIndex(where: { $0.stoppedAt == nil }) else { return }
    stopActiveBolt(at: timestamp, index: activeIndex)
  }

  mutating func frame(at timestamp: TimeInterval) -> LightningTrailFrame {
    prune(at: timestamp)
    let renderedBolts = bolts.map { bolt in
      RenderedLightningBolt(
        id: bolt.id,
        trunk: bolt.trunk,
        segments: renderedSegments(for: bolt, at: timestamp),
        alpha: 1,
        glowScale: bolt.glowScale)
    }
    return LightningTrailFrame(bolts: renderedBolts)
  }

  private mutating func emitIfReady(at timestamp: TimeInterval) {
    guard samples.last != nil else { return }
    let centerline = samples.map(\.point)
    let span = polylineLength(centerline)
    guard span >= Self.minimumSpan else { return }

    let activeIndex = bolts.firstIndex(where: { $0.stoppedAt == nil })
    let boltID: UInt64
    let boltSeed: UInt64
    let createdAt: TimeInterval
    if let activeIndex {
      boltID = bolts[activeIndex].id
      boltSeed = bolts[activeIndex].seed
      createdAt = bolts[activeIndex].createdAt
    } else {
      boltID = nextBoltID
      nextBoltID &+= 1
      boltSeed = random.next()
      createdAt = timestamp
    }
    let generated = makeBolt(
      along: centerline, id: boltID, seed: boltSeed, createdAt: createdAt)
    if let activeIndex {
      bolts[activeIndex] = generated
    } else {
      bolts.append(generated)
    }
  }

  private func makeBolt(
    along centerline: [CGPoint], id: UInt64, seed: UInt64, createdAt: TimeInterval
  ) -> LightningBolt {
    let sampledCenterline = resampledPath(centerline, spacing: Self.growthSpacing)
    let anchor = sampledCenterline.first!
    let head = sampledCenterline.last!
    var profileRandom = SplitMix64(seed: seed ^ 0xA24B_AED4_963E_E407)
    if reduceMotion {
      return LightningBolt(
        id: id, seed: seed, trunk: LightningStroke(points: sampledCenterline),
        segments: makeSegmentProfiles(
          points: sampledCenterline, randomWidths: false, random: &profileRandom),
        createdAt: createdAt, stoppedAt: nil, glowScale: 1)
    }

    var primaryRandom = SplitMix64(seed: seed ^ 0x9E37_79B9_7F4A_7C15)
    var detailRandom = SplitMix64(seed: seed ^ 0xD1B5_4A32_D192_ED03)
    var primaryBendPoints = [anchor]
    for index in 1..<(sampledCenterline.count - 1) {
      let center = sampledCenterline[index]
      let offset = randomOffset(in: 6...24, random: &primaryRandom)
      primaryBendPoints.append(add(center, offset))
    }
    primaryBendPoints.append(head)
    let trunkPoints = addInterBendOffsets(
      to: primaryBendPoints, random: &detailRandom)
    let trunk = LightningStroke(points: trunkPoints)

    return LightningBolt(
      id: id, seed: seed, trunk: trunk,
      segments: makeSegmentProfiles(
        points: trunkPoints, randomWidths: true, random: &profileRandom),
      createdAt: createdAt,
      stoppedAt: nil, glowScale: 1)
  }

  private func makeSegmentProfiles(
    points: [CGPoint], randomWidths: Bool, random: inout SplitMix64
  ) -> [LightningSegmentProfile] {
    guard points.count >= 2 else { return [] }
    let vertexWidths = points.map { _ in
      randomWidths ? random.value(in: 0.45...1.6) : 1
    }
    var profiles: [LightningSegmentProfile] = []
    for index in 0..<(points.count - 1) {
      let start = points[index]
      let end = points[index + 1]
      let length = distance(start, end)
      guard length > 0 else { continue }
      let count = max(1, Int(ceil(length / 4)))
      for subdivision in 0..<count {
        let startProgress = CGFloat(subdivision) / CGFloat(count)
        let endProgress = CGFloat(subdivision + 1) / CGFloat(count)
        let midpointProgress = (startProgress + endProgress) / 2
        let baseWidth = vertexWidths[index]
          + (vertexWidths[index + 1] - vertexWidths[index]) * midpointProgress
        let delay = randomWidths ? TimeInterval(random.value(in: 0...0.10)) : 0
        let duration = randomWidths ? TimeInterval(random.value(in: 0.20...0.35)) : 0.15
        profiles.append(
          LightningSegmentProfile(
            start: add(start, multiply(subtract(end, start), startProgress)),
            end: add(start, multiply(subtract(end, start), endProgress)),
            baseWidthScale: baseWidth,
            dissipationDelay: delay,
            dissipationDuration: duration))
      }
    }
    return profiles
  }

  private func addInterBendOffsets(
    to points: [CGPoint], random: inout SplitMix64
  ) -> [CGPoint] {
    guard points.count >= 2 else { return points }

    var detailedPoints = [points[0]]
    detailedPoints.reserveCapacity(points.count * 2 - 1)
    for (start, end) in zip(points, points.dropFirst()) {
      let delta = subtract(end, start)
      let progress = random.value(in: 0.38...0.62)
      let center = add(start, multiply(delta, progress))
      detailedPoints.append(add(center, randomOffset(in: 2...5, random: &random)))
      detailedPoints.append(end)
    }
    return detailedPoints
  }

  private mutating func prune(at timestamp: TimeInterval) {
    transitionToDissipationIfNeeded(at: timestamp)
    let boltLifetime = reduceMotion ? Self.reducedMotionLifetime : Self.standardLifetime
    bolts.removeAll { bolt in
      guard let stoppedAt = bolt.stoppedAt else { return false }
      return timestamp - stoppedAt >= boltLifetime
    }
  }

  private mutating func transitionToDissipationIfNeeded(at timestamp: TimeInterval) {
    guard
      let lastMovementTime,
      timestamp - lastMovementTime >= Self.stopDelay,
      let activeIndex = bolts.firstIndex(where: { $0.stoppedAt == nil })
    else {
      if
        let lastMovementTime,
        timestamp - lastMovementTime >= Self.stopDelay,
        bolts.allSatisfy({ $0.stoppedAt != nil }),
        let last = samples.last
      {
        samples = [last]
      }
      return
    }
    stopActiveBolt(at: lastMovementTime + Self.stopDelay, index: activeIndex)
  }

  private mutating func stopActiveBolt(at timestamp: TimeInterval, index activeIndex: Int) {
    let active = bolts[activeIndex]
    let stopped = LightningBolt(
      id: active.id,
      seed: active.seed,
      trunk: active.trunk,
      segments: active.segments,
      createdAt: active.createdAt,
      stoppedAt: timestamp,
      glowScale: active.glowScale)
    bolts = [stopped]
    if let last = samples.last { samples = [last] }
  }

  private func renderedSegments(
    for bolt: LightningBolt, at timestamp: TimeInterval
  ) -> [RenderedLightningSegment] {
    bolt.segments.map { segment in
      RenderedLightningSegment(
        start: segment.start,
        end: segment.end,
        widthScale: segment.baseWidthScale * segmentDissipationScale(
          for: segment, bolt: bolt, at: timestamp))
    }
  }

  private func segmentDissipationScale(
    for segment: LightningSegmentProfile,
    bolt: LightningBolt,
    at timestamp: TimeInterval
  ) -> CGFloat {
    guard let stoppedAt = bolt.stoppedAt else { return 1 }
    let age = max(0, timestamp - stoppedAt)
    if reduceMotion {
      return CGFloat(min(1, max(0, 1 - age / Self.reducedMotionLifetime)))
    }
    guard age > segment.dissipationDelay else { return 1 }
    let progress = min(1, max(0, (age - segment.dissipationDelay) / segment.dissipationDuration))
    return CGFloat(pow(1 - progress, 2))
  }

  private func randomOffset(
    in radiusRange: ClosedRange<CGFloat>, random: inout SplitMix64
  ) -> CGPoint {
    let angle = random.value(in: 0...(2 * .pi))
    let radius = random.value(in: radiusRange)
    return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
  }

}

private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
  hypot(lhs.x - rhs.x, lhs.y - rhs.y)
}

private func polylineLength(_ points: [CGPoint]) -> CGFloat {
  zip(points, points.dropFirst()).map(distance).reduce(0, +)
}

private func resampledPath(_ points: [CGPoint], spacing: CGFloat) -> [CGPoint] {
  guard let first = points.first, spacing > 0 else { return points }
  var result = [quantized(first)]
  var distanceUntilNext = spacing

  for (rawStart, rawEnd) in zip(points, points.dropFirst()) {
    var cursor = rawStart
    var remainingLength = distance(cursor, rawEnd)
    guard remainingLength > 0 else { continue }
    while remainingLength + 0.000_001 >= distanceUntilNext {
      let progress = distanceUntilNext / remainingLength
      cursor = add(cursor, multiply(subtract(rawEnd, cursor), progress))
      let sampled = quantized(cursor)
      if result.last != sampled { result.append(sampled) }
      remainingLength = distance(cursor, rawEnd)
      distanceUntilNext = spacing
    }
    distanceUntilNext -= remainingLength
  }

  if let last = points.last {
    let endpoint = quantized(last)
    if result.last != endpoint { result.append(endpoint) }
  }
  return result
}

private func quantized(_ point: CGPoint) -> CGPoint {
  let scale: CGFloat = 1024
  return CGPoint(
    x: (point.x * scale).rounded() / scale,
    y: (point.y * scale).rounded() / scale)
}

private func add(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
  CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
}

private func subtract(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
  CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
}

private func multiply(_ point: CGPoint, _ scalar: CGFloat) -> CGPoint {
  CGPoint(x: point.x * scalar, y: point.y * scalar)
}
