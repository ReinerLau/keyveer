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

struct LightningArc: Equatable {
  let id: UInt64
  let startDistance: CGFloat
  let endDistance: CGFloat
  let bendConfiguration: LightningBendConfiguration
  let stroke: LightningStroke
  let segments: [LightningSegmentProfile]
  let widthScale: CGFloat
  let opacity: CGFloat
}

struct LightningBendConfiguration: Equatable {
  let spacingMin: CGFloat
  let spacingMax: CGFloat
  let offsetDistanceMin: CGFloat
  let offsetDistanceMax: CGFloat
  let offsetDirectionMinRadians: CGFloat
  let offsetDirectionMaxRadians: CGFloat
  let arcLengthMin: CGFloat
  let arcLengthMax: CGFloat
  let arcGapMin: CGFloat
  let arcGapMax: CGFloat

  static let `default` = LightningBendConfiguration(
    spacingMin: 24,
    spacingMax: 36,
    offsetDistanceMin: 6,
    offsetDistanceMax: 24,
    offsetDirectionMinRadians: -.pi / 2,
    offsetDirectionMaxRadians: .pi / 2,
    arcLengthMin: 80,
    arcLengthMax: 180,
    arcGapMin: 24,
    arcGapMax: 72)
}

struct LightningBolt: Equatable {
  let id: UInt64
  let seed: UInt64
  let trunk: LightningStroke
  let segments: [LightningSegmentProfile]
  let arcs: [LightningArc]
  let nextArcStartDistance: CGFloat
  let nextArcIndex: Int
  let createdAt: TimeInterval
  let stoppedAt: TimeInterval?
  let glowScale: CGFloat
  let bendConfiguration: LightningBendConfiguration
}

struct RenderedLightningBolt: Equatable {
  let id: UInt64
  let trunk: LightningStroke
  let segments: [RenderedLightningSegment]
  let arcs: [RenderedLightningArc]
  let alpha: CGFloat
  let glowScale: CGFloat

  init(
    id: UInt64,
    trunk: LightningStroke,
    segments: [RenderedLightningSegment]? = nil,
    arcs: [RenderedLightningArc] = [],
    alpha: CGFloat,
    glowScale: CGFloat
  ) {
    self.id = id
    self.trunk = trunk
    self.segments = segments ?? zip(trunk.points, trunk.points.dropFirst()).map { start, end in
      RenderedLightningSegment(start: start, end: end, widthScale: 1)
    }
    self.arcs = arcs
    self.alpha = alpha
    self.glowScale = glowScale
  }
}

struct RenderedLightningArc: Equatable {
  let id: UInt64
  let startDistance: CGFloat
  let endDistance: CGFloat
  let stroke: LightningStroke
  let segments: [RenderedLightningSegment]
  let widthScale: CGFloat
  let opacity: CGFloat

  init(
    id: UInt64 = 0,
    startDistance: CGFloat = 0,
    endDistance: CGFloat = 0,
    stroke: LightningStroke,
    segments: [RenderedLightningSegment],
    widthScale: CGFloat,
    opacity: CGFloat
  ) {
    self.id = id
    self.startDistance = startDistance
    self.endDistance = endDistance
    self.stroke = stroke
    self.segments = segments
    self.widthScale = widthScale
    self.opacity = opacity
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
  private static let reducedMotionSpacing: CGFloat = 18

  private var samples: [Sample] = []
  private var bolts: [LightningBolt] = []
  private var random: SplitMix64
  private var bendConfiguration = LightningBendConfiguration.default
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

  mutating func updateBendOffsetConfiguration(
    spacingMin: CGFloat,
    spacingMax: CGFloat,
    distanceMin: CGFloat,
    distanceMax: CGFloat,
    directionMinDegrees: CGFloat,
    directionMaxDegrees: CGFloat,
    arcLengthMin: CGFloat = 80,
    arcLengthMax: CGFloat = 180,
    arcGapMin: CGFloat = 24,
    arcGapMax: CGFloat = 72
  ) {
    bendConfiguration = LightningBendConfiguration(
      spacingMin: spacingMin,
      spacingMax: spacingMax,
      offsetDistanceMin: distanceMin,
      offsetDistanceMax: distanceMax,
      offsetDirectionMinRadians: directionMinDegrees * .pi / 180,
      offsetDirectionMaxRadians: directionMaxDegrees * .pi / 180,
      arcLengthMin: arcLengthMin,
      arcLengthMax: arcLengthMax,
      arcGapMin: arcGapMin,
      arcGapMax: arcGapMax)
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
        arcs: renderedArcs(for: bolt, at: timestamp),
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
    let configuration: LightningBendConfiguration
    if let activeIndex {
      boltID = bolts[activeIndex].id
      boltSeed = bolts[activeIndex].seed
      createdAt = bolts[activeIndex].createdAt
      configuration = bolts[activeIndex].bendConfiguration
    } else {
      boltID = nextBoltID
      nextBoltID &+= 1
      boltSeed = random.next()
      createdAt = timestamp
      configuration = bendConfiguration
    }
    let generated = makeBolt(
      along: centerline, id: boltID, seed: boltSeed, createdAt: createdAt,
      bendConfiguration: configuration,
      existingArcs: activeIndex.map { bolts[$0].arcs } ?? [],
      nextArcStartDistance: activeIndex.map { bolts[$0].nextArcStartDistance } ?? 0,
      nextArcIndex: activeIndex.map { bolts[$0].nextArcIndex } ?? 0,
      arcConfiguration: bendConfiguration)
    if let activeIndex {
      bolts[activeIndex] = generated
    } else {
      bolts.append(generated)
    }
  }

  private func makeBolt(
    along centerline: [CGPoint], id: UInt64, seed: UInt64, createdAt: TimeInterval,
    bendConfiguration: LightningBendConfiguration,
    existingArcs: [LightningArc], nextArcStartDistance: CGFloat, nextArcIndex: Int,
    arcConfiguration: LightningBendConfiguration
  ) -> LightningBolt {
    var spacingRandom = SplitMix64(seed: seed ^ 0xD1B5_4A32_D192_ED03)
    let sampledCenterline: [CGPoint]
    if reduceMotion {
      sampledCenterline = resampledPath(centerline, spacing: Self.reducedMotionSpacing)
    } else {
      sampledCenterline = randomResampledPath(
        centerline,
        spacingRange: bendConfiguration.spacingMin...bendConfiguration.spacingMax,
        random: &spacingRandom)
    }
    let anchor = sampledCenterline.first!
    let head = sampledCenterline.last!
    var profileRandom = SplitMix64(seed: seed ^ 0xA24B_AED4_963E_E407)
    if reduceMotion {
      return LightningBolt(
        id: id, seed: seed, trunk: LightningStroke(points: sampledCenterline),
        segments: makeSegmentProfiles(
          points: sampledCenterline, randomWidths: false, random: &profileRandom),
        arcs: [], nextArcStartDistance: 0, nextArcIndex: 0,
        createdAt: createdAt, stoppedAt: nil, glowScale: 1,
        bendConfiguration: bendConfiguration)
    }

    var primaryRandom = SplitMix64(seed: seed ^ 0x9E37_79B9_7F4A_7C15)
    var primaryBendPoints = [anchor]
    for index in 1..<(sampledCenterline.count - 1) {
      let center = sampledCenterline[index]
      // Use the heading entering this anchor so an already-generated prefix does not
      // change when later movement samples are appended.
      let forward = subtract(sampledCenterline[index], sampledCenterline[index - 1])
      let forwardAngle = atan2(forward.y, forward.x)
      let offset = randomOffset(
        using: bendConfiguration, random: &primaryRandom, forwardAngle: forwardAngle)
      primaryBendPoints.append(add(center, offset))
    }
    primaryBendPoints.append(head)
    let trunk = LightningStroke(points: primaryBendPoints)
    let (arcs, nextStart, nextIndex) = makeCompanionArcs(
      centerline: sampledCenterline, trunk: trunk, seed: seed,
      bendConfiguration: arcConfiguration, existingArcs: existingArcs,
      nextArcStartDistance: nextArcStartDistance, nextArcIndex: nextArcIndex)

    return LightningBolt(
      id: id, seed: seed, trunk: trunk,
      segments: makeSegmentProfiles(
        points: primaryBendPoints, randomWidths: true, random: &profileRandom),
      arcs: arcs,
      nextArcStartDistance: nextStart,
      nextArcIndex: nextIndex,
      createdAt: createdAt,
      stoppedAt: nil, glowScale: 1,
      bendConfiguration: bendConfiguration)
  }

  private func makeCompanionArcs(
    centerline: [CGPoint], trunk: LightningStroke, seed: UInt64,
    bendConfiguration: LightningBendConfiguration,
    existingArcs: [LightningArc], nextArcStartDistance: CGFloat, nextArcIndex: Int
  ) -> ([LightningArc], CGFloat, Int) {
    guard !reduceMotion, centerline.count >= 2, trunk.points.count >= 2 else {
      return ([], 0, 0)
    }
    let totalLength = polylineLength(centerline)
    guard totalLength >= Self.minimumSpan else { return ([], 0, 0) }

    var arcs = existingArcs
    // Only the last segment can still be partial. Rebuild it deterministically on each route
    // extension so a large input jump crossing its endpoint still completes it exactly at the
    // scheduled distance; once complete, the same seed produces byte-for-byte identical geometry.
    if let lastIndex = arcs.indices.last {
      let last = arcs[lastIndex]
      arcs[lastIndex] = makeCompanionArc(
        centerline: centerline, trunk: trunk, seed: seed, segmentIndex: lastIndex,
        startDistance: last.startDistance, endDistance: last.endDistance,
        widthScale: last.widthScale, opacity: last.opacity,
        bendConfiguration: last.bendConfiguration)
    }

    var nextStart = nextArcStartDistance
    var index = nextArcIndex
    while totalLength + 0.000_001 >= nextStart {
      var random = SplitMix64(
        seed: seed ^ 0x6A09_E667_F3BC_C909 ^ UInt64(index) &* 0x9E37_79B9_7F4A_7C15)
      let length = random.value(in: bendConfiguration.arcLengthMin...bendConfiguration.arcLengthMax)
      let endDistance = nextStart + length
      let widthScale = random.value(in: 0.25...0.45)
      let opacity = 0.35 + CGFloat(random.unit()) * 0.25
      arcs.append(makeCompanionArc(
        centerline: centerline, trunk: trunk, seed: seed, segmentIndex: index,
        startDistance: nextStart, endDistance: endDistance,
        widthScale: widthScale, opacity: opacity,
        bendConfiguration: bendConfiguration))
      nextStart = endDistance + random.value(in: bendConfiguration.arcGapMin...bendConfiguration.arcGapMax)
      index += 1
    }
    return (arcs, nextStart, index)
  }

  private func makeCompanionArc(
    centerline: [CGPoint], trunk: LightningStroke, seed: UInt64,
    segmentIndex: Int, startDistance: CGFloat, endDistance: CGFloat,
    widthScale: CGFloat, opacity: CGFloat, bendConfiguration: LightningBendConfiguration
  ) -> LightningArc {
    let routeLength = polylineLength(centerline)
    let clippedEnd = min(endDistance, routeLength)
    var points = [correspondingPoint(
      reference: centerline, target: trunk.points, atDistance: startDistance)]
    var random = SplitMix64(
      seed: seed ^ UInt64(segmentIndex) &* 0xD1B5_4A32_D192_ED03)
    var cumulative: CGFloat = 0
    if centerline.count > 2 {
      for index in 1..<(centerline.count - 1) {
        cumulative += distance(centerline[index - 1], centerline[index])
        guard cumulative > startDistance, cumulative < clippedEnd else { continue }
        let center = centerline[index]
        let forward = subtract(centerline[index], centerline[index - 1])
        let offset = randomOffset(
          using: bendConfiguration, random: &random,
          forwardAngle: atan2(forward.y, forward.x))
        points.append(add(center, offset))
      }
    }
    points.append(correspondingPoint(
      reference: centerline, target: trunk.points, atDistance: clippedEnd))
    var profileRandom = SplitMix64(
      seed: seed ^ UInt64(segmentIndex) &* 0xA24B_AED4_963E_E407)
    return LightningArc(
      id: seed ^ UInt64(segmentIndex) &* 0x94D0_49BB_1331_11EB,
      startDistance: startDistance,
      endDistance: endDistance,
      bendConfiguration: bendConfiguration,
      stroke: LightningStroke(points: points),
      segments: makeArcSegmentProfiles(
        points: points, widthScale: widthScale, random: &profileRandom),
      widthScale: widthScale,
      opacity: opacity)
  }

  private func makeArcSegmentProfiles(
    points: [CGPoint], widthScale: CGFloat, random: inout SplitMix64
  ) -> [LightningSegmentProfile] {
    guard points.count >= 2 else { return [] }
    var profiles: [LightningSegmentProfile] = []
    for (start, end) in zip(points, points.dropFirst()) {
      let length = distance(start, end)
      guard length > 0 else { continue }
      let count = max(1, Int(ceil(length / 4)))
      for subdivision in 0..<count {
        let startProgress = CGFloat(subdivision) / CGFloat(count)
        let endProgress = CGFloat(subdivision + 1) / CGFloat(count)
        profiles.append(
          LightningSegmentProfile(
            start: add(start, multiply(subtract(end, start), startProgress)),
            end: add(start, multiply(subtract(end, start), endProgress)),
            baseWidthScale: widthScale,
            dissipationDelay: TimeInterval(random.value(in: 0...0.10)),
            dissipationDuration: TimeInterval(random.value(in: 0.20...0.35))))
      }
    }
    return profiles
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
      arcs: active.arcs,
      nextArcStartDistance: active.nextArcStartDistance,
      nextArcIndex: active.nextArcIndex,
      createdAt: active.createdAt,
      stoppedAt: timestamp,
      glowScale: active.glowScale,
      bendConfiguration: active.bendConfiguration)
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

  private func renderedArcs(
    for bolt: LightningBolt, at timestamp: TimeInterval
  ) -> [RenderedLightningArc] {
    bolt.arcs.map { arc in
      RenderedLightningArc(
        id: arc.id,
        startDistance: arc.startDistance,
        endDistance: arc.endDistance,
        stroke: arc.stroke,
        segments: arc.segments.map { segment in
          RenderedLightningSegment(
            start: segment.start,
            end: segment.end,
            widthScale: segment.baseWidthScale * segmentDissipationScale(
              for: segment, bolt: bolt, at: timestamp))
        },
        widthScale: arc.widthScale,
        opacity: arc.opacity)
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
    using configuration: LightningBendConfiguration,
    random: inout SplitMix64,
    forwardAngle: CGFloat
  ) -> CGPoint {
    let angle = random.value(
      in: configuration.offsetDirectionMinRadians...configuration.offsetDirectionMaxRadians)
      + forwardAngle
    let radius = random.value(
      in: configuration.offsetDistanceMin...configuration.offsetDistanceMax)
    return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
  }

  private func randomResampledPath(
    _ points: [CGPoint],
    spacingRange: ClosedRange<CGFloat>,
    random: inout SplitMix64
  ) -> [CGPoint] {
    guard let first = points.first, spacingRange.lowerBound > 0 else { return points }
    var result = [quantized(first)]
    var distanceUntilNext = random.value(in: spacingRange)

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
        distanceUntilNext = random.value(in: spacingRange)
      }
      distanceUntilNext -= remainingLength
    }

    if let last = points.last {
      let endpoint = quantized(last)
      if result.last != endpoint { result.append(endpoint) }
    }
    return result
  }

}

private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
  hypot(lhs.x - rhs.x, lhs.y - rhs.y)
}

private func correspondingPoint(
  reference: [CGPoint], target: [CGPoint], atDistance targetDistance: CGFloat
) -> CGPoint {
  guard reference.count == target.count, reference.count >= 2 else {
    return target.last ?? .zero
  }
  var remaining = max(0, targetDistance)
  for index in 0..<(reference.count - 1) {
    let referenceLength = distance(reference[index], reference[index + 1])
    guard referenceLength > 0 else { continue }
    if remaining <= referenceLength {
      let progress = remaining / referenceLength
      return add(
        target[index], multiply(subtract(target[index + 1], target[index]), progress))
    }
    remaining -= referenceLength
  }
  return target.last ?? .zero
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
