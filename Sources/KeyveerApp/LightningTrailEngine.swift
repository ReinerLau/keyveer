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
  let targetLength: CGFloat
  let continuesGrowing: Bool
  let growthStoppedAt: TimeInterval?
  let holdDuration: TimeInterval
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
  let arcHoldMin: TimeInterval
  let arcHoldMax: TimeInterval

  static let `default` = LightningBendConfiguration(
    spacingMin: 30,
    spacingMax: 100,
    offsetDistanceMin: 6,
    offsetDistanceMax: 50,
    offsetDirectionMinRadians: -.pi / 2,
    offsetDirectionMaxRadians: .pi / 2,
    arcLengthMin: 300,
    arcLengthMax: 500,
    arcGapMin: 200,
    arcGapMax: 300,
    arcHoldMin: 0.20,
    arcHoldMax: 1)
}

fileprivate struct LightningWidthConfiguration: Equatable {
  let trunkScaleMin: CGFloat
  let trunkScaleMax: CGFloat
  let arcScaleMin: CGFloat
  let arcScaleMax: CGFloat

  static let `default` = LightningWidthConfiguration(
    trunkScaleMin: 0.1, trunkScaleMax: 2,
    arcScaleMin: 0.25, arcScaleMax: 0.8)
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
  let mainTrunkEnabledAtStop: Bool?
  let glowScale: CGFloat
  let bendConfiguration: LightningBendConfiguration
  fileprivate let widthConfiguration: LightningWidthConfiguration
}

struct RenderedLightningBolt: Equatable {
  let id: UInt64
  let trunk: LightningStroke
  let trunkVisible: Bool
  let segments: [RenderedLightningSegment]
  let arcs: [RenderedLightningArc]
  let alpha: CGFloat
  let glowScale: CGFloat

  init(
    id: UInt64,
    trunk: LightningStroke,
    trunkVisible: Bool = true,
    segments: [RenderedLightningSegment]? = nil,
    arcs: [RenderedLightningArc] = [],
    alpha: CGFloat,
    glowScale: CGFloat
  ) {
    self.id = id
    self.trunk = trunk
    self.trunkVisible = trunkVisible
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
  let visible: Bool

  init(
    id: UInt64 = 0,
    startDistance: CGFloat = 0,
    endDistance: CGFloat = 0,
    stroke: LightningStroke,
    segments: [RenderedLightningSegment],
    widthScale: CGFloat,
    opacity: CGFloat,
    visible: Bool = true
  ) {
    self.id = id
    self.startDistance = startDistance
    self.endDistance = endDistance
    self.stroke = stroke
    self.segments = segments
    self.widthScale = widthScale
    self.opacity = opacity
    self.visible = visible
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

  private struct OffsetPathPoint {
    let point: CGPoint
    let forwardAngle: CGFloat
    let key: UInt64
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
  private static let defaultTrunkFlickerIntervalMin: TimeInterval = 0.12
  private static let defaultTrunkFlickerIntervalMax: TimeInterval = 0.30
  private static let defaultTrunkFlickerFramesMin = 1
  private static let defaultTrunkFlickerFramesMax = 2
  private static let fallbackDisplayFrameDuration: TimeInterval = 1.0 / 60.0
  private static let trunkFlickerSeedSalt: UInt64 = 0xC6BC_2796_92B5_CC83
  private static let companionArcScheduleSeedSalt: UInt64 = 0x6A09_E667_F3BC_C909
  private static let companionArcGeometrySeedSalt: UInt64 = 0xD1B5_4A32_D192_ED03
  private static let companionArcProfileSeedSalt: UInt64 = 0xA24B_AED4_963E_E407
  private static let companionArcIDMultiplier: UInt64 = 0x94D0_49BB_1331_11EB
  private static let companionArcFlickerSeedSalt: UInt64 = 0x510E_527F_ADE6_82D1
  private var samples: [Sample] = []
  private var bolts: [LightningBolt] = []
  private var random: SplitMix64
  private var trunkFlickerRandom: SplitMix64
  private var bendConfiguration = LightningBendConfiguration.default
  private var lastMovementTime: TimeInterval?
  private var lastKnownPoint: CGPoint?
  private var nextBoltID: UInt64 = 0
  private(set) var reduceMotion = false
  private var movementSuppressed = false
  private var mainTrunkEnabled = true
  private var nextTrunkFlickerAt: TimeInterval?
  private var trunkHiddenUntil: TimeInterval?
  private var displayFrameDuration = Self.fallbackDisplayFrameDuration
  private var trunkFlickerIntervalMin = Self.defaultTrunkFlickerIntervalMin
  private var trunkFlickerIntervalMax = Self.defaultTrunkFlickerIntervalMax
  private var trunkFlickerFramesMin = Self.defaultTrunkFlickerFramesMin
  private var trunkFlickerFramesMax = Self.defaultTrunkFlickerFramesMax
  private var widthConfiguration = LightningWidthConfiguration.default

  private struct CompanionArcFlickerState {
    var random: SplitMix64
    var nextFlickerAt: TimeInterval?
    var hiddenUntil: TimeInterval?

    init(arcID: UInt64) {
      random = SplitMix64(seed: arcID ^ LightningTrailEngine.companionArcFlickerSeedSalt)
    }
  }

  private var companionArcFlickerStates: [UInt64: CompanionArcFlickerState] = [:]

  init(seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)) {
    random = SplitMix64(seed: seed)
    trunkFlickerRandom = SplitMix64(seed: seed ^ Self.trunkFlickerSeedSalt)
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
    nextTrunkFlickerAt = nil
    trunkHiddenUntil = nil
    companionArcFlickerStates.removeAll(keepingCapacity: true)
  }

  mutating func resumeMovement() {
    movementSuppressed = false
  }

  /// Controls visibility of the lightning trail during the current movement.
  ///
  /// Trunk flicker remains independent, but the default keyboard speed hides both the
  /// prominent trunk and its companion arcs.
  mutating func setMainTrunkEnabled(_ enabled: Bool) {
    if enabled && !mainTrunkEnabled {
      // Do not reveal movement that happened while the default speed hid the trail. Keep
      // the current pointer as the origin for the next visible movement segment.
      bolts.removeAll { $0.stoppedAt == nil }
      samples.removeAll(keepingCapacity: true)
      lastMovementTime = nil
      resetTrunkFlicker()
      companionArcFlickerStates.removeAll(keepingCapacity: true)
    }
    mainTrunkEnabled = enabled
  }

  mutating func updateTrunkFlickerConfiguration(
    intervalMin: TimeInterval,
    intervalMax: TimeInterval,
    framesMin: Int,
    framesMax: Int
  ) {
    trunkFlickerIntervalMin = intervalMin
    trunkFlickerIntervalMax = intervalMax
    trunkFlickerFramesMin = framesMin
    trunkFlickerFramesMax = framesMax
    resetTrunkFlicker()
    companionArcFlickerStates.removeAll(keepingCapacity: true)
  }

  mutating func updateBendOffsetConfiguration(
    spacingMin: CGFloat,
    spacingMax: CGFloat,
    distanceMin: CGFloat,
    distanceMax: CGFloat,
    directionMinDegrees: CGFloat,
    directionMaxDegrees: CGFloat,
    arcLengthMin: CGFloat = 300,
    arcLengthMax: CGFloat = 500,
    arcGapMin: CGFloat = 200,
    arcGapMax: CGFloat = 300,
    arcHoldMin: TimeInterval = 0.20,
    arcHoldMax: TimeInterval = 1
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
      arcGapMax: arcGapMax,
      arcHoldMin: arcHoldMin,
      arcHoldMax: arcHoldMax)
  }

  mutating func updateWidthConfiguration(
    trunkScaleMin: CGFloat,
    trunkScaleMax: CGFloat,
    arcScaleMin: CGFloat,
    arcScaleMax: CGFloat
  ) {
    widthConfiguration = LightningWidthConfiguration(
      trunkScaleMin: trunkScaleMin,
      trunkScaleMax: trunkScaleMax,
      arcScaleMin: arcScaleMin,
      arcScaleMax: arcScaleMax)
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

  mutating func frame(
    at timestamp: TimeInterval, frameDuration: TimeInterval? = nil
  ) -> LightningTrailFrame {
    prune(at: timestamp)
    if let frameDuration, frameDuration.isFinite, frameDuration > 0 {
      displayFrameDuration = frameDuration
    }
    let activeTrunkVisible = mainTrunkVisibility(at: timestamp)
    let activeArcIDs = Set(bolts.flatMap { $0.arcs.map(\.id) })
    companionArcFlickerStates = companionArcFlickerStates.filter {
      activeArcIDs.contains($0.key)
    }
    var renderedBolts: [RenderedLightningBolt] = []
    for bolt in bolts {
      let trunkVisible = bolt.stoppedAt == nil
        ? activeTrunkVisible
        : (bolt.mainTrunkEnabledAtStop ?? activeTrunkVisible)
      renderedBolts.append(RenderedLightningBolt(
        id: bolt.id,
        trunk: bolt.trunk,
        trunkVisible: trunkVisible,
        segments: renderedSegments(for: bolt, at: timestamp),
        arcs: renderedArcs(for: bolt, at: timestamp),
        alpha: 1,
        glowScale: bolt.glowScale))
    }
    return LightningTrailFrame(bolts: renderedBolts)
  }

  private mutating func mainTrunkVisibility(at timestamp: TimeInterval) -> Bool {
    guard mainTrunkEnabled else {
      resetTrunkFlicker()
      return false
    }
    guard !reduceMotion, bolts.contains(where: { $0.stoppedAt == nil }) else {
      resetTrunkFlicker()
      return true
    }

    if let trunkHiddenUntil {
      if timestamp < trunkHiddenUntil {
        return false
      }
      self.trunkHiddenUntil = nil
    }

    if nextTrunkFlickerAt == nil {
      nextTrunkFlickerAt = timestamp + nextTrunkFlickerInterval()
      return true
    }
    guard timestamp >= nextTrunkFlickerAt! else { return true }

    let frameRange = trunkFlickerFramesMax - trunkFlickerFramesMin
    let hiddenFrameCount = trunkFlickerFramesMin
      + Int(trunkFlickerRandom.next() % UInt64(frameRange + 1))
    trunkHiddenUntil = timestamp + Double(hiddenFrameCount) * displayFrameDuration
    nextTrunkFlickerAt = trunkHiddenUntil! + nextTrunkFlickerInterval()
    return false
  }

  private mutating func nextTrunkFlickerInterval() -> TimeInterval {
    nextTrunkFlickerInterval(using: &trunkFlickerRandom)
  }

  private func nextTrunkFlickerInterval(using random: inout SplitMix64) -> TimeInterval {
    trunkFlickerIntervalMin
      + Double(random.unit()) * (trunkFlickerIntervalMax - trunkFlickerIntervalMin)
  }

  private mutating func resetTrunkFlicker() {
    nextTrunkFlickerAt = nil
    trunkHiddenUntil = nil
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
    let boltWidthConfiguration: LightningWidthConfiguration
    if let activeIndex {
      boltID = bolts[activeIndex].id
      boltSeed = bolts[activeIndex].seed
      createdAt = bolts[activeIndex].createdAt
      configuration = bolts[activeIndex].bendConfiguration
      boltWidthConfiguration = bolts[activeIndex].widthConfiguration
    } else {
      boltID = nextBoltID
      nextBoltID &+= 1
      boltSeed = random.next()
      createdAt = timestamp
      configuration = bendConfiguration
      boltWidthConfiguration = widthConfiguration
    }
    let generated = makeBolt(
      along: centerline, id: boltID, seed: boltSeed, createdAt: createdAt,
      timestamp: timestamp,
      bendConfiguration: configuration,
      widthConfiguration: boltWidthConfiguration,
      existingArcs: activeIndex.map { bolts[$0].arcs } ?? [],
      nextArcStartDistance: activeIndex.map { bolts[$0].nextArcStartDistance } ?? 0,
      nextArcIndex: activeIndex.map { bolts[$0].nextArcIndex } ?? 0,
      arcConfiguration: bendConfiguration,
      arcWidthConfiguration: widthConfiguration)
    if let activeIndex {
      bolts[activeIndex] = generated
    } else {
      bolts.append(generated)
    }
  }

  private func makeBolt(
    along centerline: [CGPoint], id: UInt64, seed: UInt64, createdAt: TimeInterval,
    timestamp: TimeInterval,
    bendConfiguration: LightningBendConfiguration,
    widthConfiguration: LightningWidthConfiguration,
    existingArcs: [LightningArc], nextArcStartDistance: CGFloat, nextArcIndex: Int,
    arcConfiguration: LightningBendConfiguration,
    arcWidthConfiguration: LightningWidthConfiguration
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
    var profileRandom = SplitMix64(seed: seed ^ 0xA24B_AED4_963E_E407)
    if reduceMotion {
      return LightningBolt(
        id: id, seed: seed, trunk: LightningStroke(points: sampledCenterline),
        segments: makeSegmentProfiles(
          points: sampledCenterline, randomWidths: false,
          widthConfiguration: widthConfiguration, random: &profileRandom),
        arcs: [], nextArcStartDistance: 0, nextArcIndex: 0,
        createdAt: createdAt, stoppedAt: nil, mainTrunkEnabledAtStop: nil, glowScale: 1,
        bendConfiguration: bendConfiguration,
        widthConfiguration: widthConfiguration)
    }

    let primaryBendPoints = offsetPathPoints(
      sampledCenterline.enumerated().map { index, point in
        let previous = sampledCenterline[max(0, index - 1)]
        let forward = subtract(point, previous)
        return OffsetPathPoint(
          point: point, forwardAngle: atan2(forward.y, forward.x), key: UInt64(index))
      }, configuration: bendConfiguration, seed: seed ^ 0x9E37_79B9_7F4A_7C15)
    let trunk = LightningStroke(points: primaryBendPoints)
    let (arcs, nextStart, nextIndex) = makeCompanionArcs(
      centerline: sampledCenterline, seed: seed,
      bendConfiguration: arcConfiguration, existingArcs: existingArcs,
      nextArcStartDistance: nextArcStartDistance, nextArcIndex: nextArcIndex,
      widthConfiguration: arcWidthConfiguration, timestamp: timestamp)

    return LightningBolt(
      id: id, seed: seed, trunk: trunk,
      segments: makeSegmentProfiles(
        points: primaryBendPoints, randomWidths: true,
        widthConfiguration: widthConfiguration, random: &profileRandom),
      arcs: arcs,
      nextArcStartDistance: nextStart,
      nextArcIndex: nextIndex,
      createdAt: createdAt,
      stoppedAt: nil, mainTrunkEnabledAtStop: nil, glowScale: 1,
      bendConfiguration: bendConfiguration,
      widthConfiguration: widthConfiguration)
  }

  private func makeCompanionArcs(
    centerline: [CGPoint], seed: UInt64,
    bendConfiguration: LightningBendConfiguration,
    existingArcs: [LightningArc], nextArcStartDistance: CGFloat, nextArcIndex: Int,
    widthConfiguration: LightningWidthConfiguration, timestamp: TimeInterval
  ) -> ([LightningArc], CGFloat, Int) {
    guard !reduceMotion, centerline.count >= 2 else {
      return ([], 0, 0)
    }
    let totalLength = polylineLength(centerline)
    guard totalLength >= Self.minimumSpan else { return ([], 0, 0) }

    var arcs: [LightningArc] = existingArcs.compactMap { arc in
      guard !isCompanionArcExpired(arc, at: timestamp) else { return nil }
      return updateCompanionArc(centerline: centerline, existing: arc, at: timestamp)
    }

    var nextStart = nextArcStartDistance
    var index = nextArcIndex
    if arcs.isEmpty, index == 0, nextStart <= 0 {
      nextStart = nextCompanionArcGap(
        seed: seed, index: index, bendConfiguration: bendConfiguration)
    }
    while totalLength > nextStart + 0.000_001 {
      var random = SplitMix64(
        seed: seed ^ Self.companionArcScheduleSeedSalt
          ^ UInt64(index) &* 0x9E37_79B9_7F4A_7C15)
      let widthScale = random.value(
        in: widthConfiguration.arcScaleMin...widthConfiguration.arcScaleMax)
      let opacity = 0.35 + CGFloat(random.unit()) * 0.25
      let targetLength = random.value(
        in: bendConfiguration.arcLengthMin...bendConfiguration.arcLengthMax)
      let holdDuration = TimeInterval(random.value(
        in: CGFloat(bendConfiguration.arcHoldMin)...CGFloat(bendConfiguration.arcHoldMax)))
      let id = seed ^ UInt64(index) &* Self.companionArcIDMultiplier
      arcs.append(makeCompanionArc(
        centerline: centerline, id: id,
        startDistance: nextStart,
        targetLength: targetLength, holdDuration: holdDuration,
        widthScale: widthScale, opacity: opacity,
        bendConfiguration: bendConfiguration, timestamp: timestamp))
      nextStart += max(
        1, random.value(in: bendConfiguration.arcGapMin...bendConfiguration.arcGapMax))
      index += 1
    }
    return (arcs, nextStart, index)
  }

  private func nextCompanionArcGap(
    seed: UInt64, index: Int, bendConfiguration: LightningBendConfiguration
  ) -> CGFloat {
    var random = SplitMix64(
      seed: seed ^ Self.companionArcScheduleSeedSalt
        ^ UInt64(index) &* 0x9E37_79B9_7F4A_7C15)
    return random.value(in: bendConfiguration.arcGapMin...bendConfiguration.arcGapMax)
  }

  private func makeCompanionArc(
    centerline: [CGPoint], id: UInt64, startDistance: CGFloat,
    targetLength: CGFloat, holdDuration: TimeInterval,
    widthScale: CGFloat, opacity: CGFloat, bendConfiguration: LightningBendConfiguration,
    timestamp: TimeInterval
  ) -> LightningArc {
    let routeLength = polylineLength(centerline)
    let endDistance = min(routeLength, startDistance + targetLength)
    let points = companionArcPoints(
      centerline: centerline, startDistance: startDistance, endDistance: endDistance, seed: id,
      bendConfiguration: bendConfiguration)
    return makeCompanionArc(
      id: id, startDistance: startDistance, endDistance: endDistance, targetLength: targetLength,
      points: points,
      widthScale: widthScale, opacity: opacity, bendConfiguration: bendConfiguration,
      holdDuration: holdDuration,
      growthStoppedAt: endDistance + 0.000_001 >= startDistance + targetLength
        ? timestamp : nil)
  }

  private func updateCompanionArc(
    centerline: [CGPoint], existing: LightningArc, at timestamp: TimeInterval
  ) -> LightningArc {
    guard existing.continuesGrowing else { return existing }
    let routeLength = polylineLength(centerline)
    let targetEnd = min(routeLength, existing.startDistance + existing.targetLength)
    guard targetEnd > existing.endDistance + 0.000_001 else {
      if targetEnd + 0.000_001 >= existing.startDistance + existing.targetLength {
        return makeCompanionArc(
          id: existing.id, startDistance: existing.startDistance, endDistance: existing.endDistance,
          targetLength: existing.targetLength, points: existing.stroke.points,
          widthScale: existing.widthScale, opacity: existing.opacity,
          bendConfiguration: existing.bendConfiguration, holdDuration: existing.holdDuration,
          growthStoppedAt: timestamp)
      }
      return existing
    }
    let extensionPoints = companionArcPoints(
      centerline: centerline, startDistance: existing.endDistance, endDistance: targetEnd,
      seed: existing.id,
      bendConfiguration: existing.bendConfiguration)
    let points = existing.stroke.points + Array(extensionPoints.dropFirst())
    return makeCompanionArc(
      id: existing.id, startDistance: existing.startDistance, endDistance: targetEnd,
      targetLength: existing.targetLength, points: points,
      widthScale: existing.widthScale, opacity: existing.opacity,
      bendConfiguration: existing.bendConfiguration, holdDuration: existing.holdDuration,
      growthStoppedAt: targetEnd + 0.000_001 >= existing.startDistance + existing.targetLength
        ? timestamp : nil)
  }

  private func makeCompanionArc(
    id: UInt64, startDistance: CGFloat, endDistance: CGFloat, targetLength: CGFloat,
    points: [CGPoint],
    widthScale: CGFloat, opacity: CGFloat, bendConfiguration: LightningBendConfiguration,
    holdDuration: TimeInterval, growthStoppedAt: TimeInterval?
  ) -> LightningArc {
    var profileRandom = SplitMix64(seed: id ^ Self.companionArcProfileSeedSalt)
    return LightningArc(
      id: id,
      startDistance: startDistance,
      endDistance: endDistance,
      targetLength: targetLength,
      continuesGrowing: growthStoppedAt == nil,
      growthStoppedAt: growthStoppedAt,
      holdDuration: holdDuration,
      bendConfiguration: bendConfiguration,
      stroke: LightningStroke(points: points),
      segments: makeArcSegmentProfiles(
        points: points, widthScale: widthScale, random: &profileRandom),
      widthScale: widthScale,
      opacity: opacity)
  }

  private func freezingCompanionArc(_ arc: LightningArc, at timestamp: TimeInterval) -> LightningArc {
    guard arc.continuesGrowing else { return arc }
    return LightningArc(
      id: arc.id,
      startDistance: arc.startDistance,
      endDistance: arc.endDistance,
      targetLength: arc.targetLength,
      continuesGrowing: false,
      growthStoppedAt: timestamp,
      holdDuration: arc.holdDuration,
      bendConfiguration: arc.bendConfiguration,
      stroke: arc.stroke,
      segments: arc.segments,
      widthScale: arc.widthScale,
      opacity: arc.opacity)
  }

  private func companionArcPoints(
    centerline: [CGPoint], startDistance: CGFloat, endDistance: CGFloat, seed: UInt64,
    bendConfiguration: LightningBendConfiguration
  ) -> [CGPoint] {
    let routeLength = polylineLength(centerline)
    let clampedStart = min(max(0, startDistance), routeLength)
    let clampedEnd = min(max(clampedStart, endDistance), routeLength)
    guard clampedEnd > clampedStart + 0.000_001 else { return [] }
    var rawPoints: [OffsetPathPoint] = []
    var cumulative: CGFloat = 0

    for index in 0..<(centerline.count - 1) {
      let start = centerline[index]
      let end = centerline[index + 1]
      let span = distance(start, end)
      guard span > 0 else { continue }
      let angle = atan2(end.y - start.y, end.x - start.x)
      let segmentStart = cumulative
      let segmentEnd = cumulative + span
      let visibleStart = max(clampedStart, segmentStart)
      let visibleEnd = min(clampedEnd, segmentEnd)
      if visibleEnd > visibleStart + 0.000_001 {
        let startProgress = (visibleStart - segmentStart) / span
        let endProgress = (visibleEnd - segmentStart) / span
        let startPoint = add(start, multiply(subtract(end, start), startProgress))
        let endPoint = add(start, multiply(subtract(end, start), endProgress))
        if rawPoints.isEmpty {
          rawPoints.append(
            OffsetPathPoint(point: startPoint, forwardAngle: angle, key: UInt64(index)))
        }
        if distance(rawPoints.last!.point, endPoint) > 0.000_001 {
          rawPoints.append(
            OffsetPathPoint(point: endPoint, forwardAngle: angle, key: UInt64(index + 1)))
        }
      }
      cumulative += span
    }

    guard rawPoints.count >= 2 else { return [] }
    return offsetPathPoints(
      rawPoints, configuration: bendConfiguration, seed: seed ^ Self.companionArcGeometrySeedSalt)
  }

  private func offsetPathPoints(
    _ points: [OffsetPathPoint], configuration: LightningBendConfiguration, seed: UInt64
  ) -> [CGPoint] {
    guard points.count >= 2 else { return points.map(\.point) }

    var result = [points[0].point]
    result.reserveCapacity(points.count)
    for point in points.dropFirst().dropLast() {
      var random = SplitMix64(
        seed: seed ^ point.key &* 0x9E37_79B9_7F4A_7C15)
      let offset = randomOffset(
        using: configuration, random: &random, forwardAngle: point.forwardAngle)
      result.append(add(point.point, offset))
    }
    result.append(points[points.count - 1].point)
    return result
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
    points: [CGPoint], randomWidths: Bool,
    widthConfiguration: LightningWidthConfiguration,
    random: inout SplitMix64
  ) -> [LightningSegmentProfile] {
    guard points.count >= 2 else { return [] }
    let vertexWidths = points.map { _ in
      randomWidths
        ? random.value(
          in: widthConfiguration.trunkScaleMin...widthConfiguration.trunkScaleMax)
        : 1
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
    bolts = bolts.map { bolt in
      let liveArcs = bolt.arcs.filter { !isCompanionArcExpired($0, at: timestamp) }
      guard liveArcs.count != bolt.arcs.count else { return bolt }
      return LightningBolt(
        id: bolt.id,
        seed: bolt.seed,
        trunk: bolt.trunk,
        segments: bolt.segments,
        arcs: liveArcs,
        nextArcStartDistance: bolt.nextArcStartDistance,
        nextArcIndex: bolt.nextArcIndex,
        createdAt: bolt.createdAt,
        stoppedAt: bolt.stoppedAt,
        mainTrunkEnabledAtStop: bolt.mainTrunkEnabledAtStop,
        glowScale: bolt.glowScale,
        bendConfiguration: bolt.bendConfiguration,
        widthConfiguration: bolt.widthConfiguration)
    }
    let boltLifetime = reduceMotion ? Self.reducedMotionLifetime : Self.standardLifetime
    bolts.removeAll { bolt in
      guard let stoppedAt = bolt.stoppedAt else { return false }
      return timestamp - stoppedAt >= boltLifetime && bolt.arcs.isEmpty
    }
  }

  private func isCompanionArcExpired(_ arc: LightningArc, at timestamp: TimeInterval) -> Bool {
    guard let growthStoppedAt = arc.growthStoppedAt else { return false }
    return timestamp - growthStoppedAt >= arc.holdDuration
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
      arcs: active.arcs.map { freezingCompanionArc($0, at: timestamp) },
      nextArcStartDistance: active.nextArcStartDistance,
      nextArcIndex: active.nextArcIndex,
      createdAt: active.createdAt,
      stoppedAt: timestamp,
      mainTrunkEnabledAtStop: mainTrunkEnabled,
      glowScale: active.glowScale,
      bendConfiguration: active.bendConfiguration,
      widthConfiguration: active.widthConfiguration)
    bolts[activeIndex] = stopped
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

  private mutating func renderedArcs(
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
            widthScale: segment.baseWidthScale * companionArcDissipationScale(
              for: segment, arc: arc, at: timestamp))
        },
        widthScale: arc.widthScale,
        opacity: arc.opacity,
        visible: companionArcVisibility(for: arc, bolt: bolt, at: timestamp))
    }
  }

  private mutating func companionArcVisibility(
    for arc: LightningArc, bolt: LightningBolt, at timestamp: TimeInterval
  ) -> Bool {
    var state = companionArcFlickerStates[arc.id]
      ?? CompanionArcFlickerState(arcID: arc.id)
    let trailEnabled = bolt.stoppedAt == nil
      ? mainTrunkEnabled
      : (bolt.mainTrunkEnabledAtStop ?? mainTrunkEnabled)
    guard trailEnabled else {
      state.nextFlickerAt = nil
      state.hiddenUntil = nil
      companionArcFlickerStates[arc.id] = state
      return false
    }
    guard !reduceMotion else {
      state.nextFlickerAt = nil
      state.hiddenUntil = nil
      companionArcFlickerStates[arc.id] = state
      return true
    }

    if let hiddenUntil = state.hiddenUntil {
      if timestamp < hiddenUntil {
        companionArcFlickerStates[arc.id] = state
        return false
      }
      state.hiddenUntil = nil
    }

    if state.nextFlickerAt == nil {
      state.nextFlickerAt = timestamp + nextTrunkFlickerInterval(using: &state.random)
      companionArcFlickerStates[arc.id] = state
      return true
    }
    guard timestamp >= state.nextFlickerAt! else {
      companionArcFlickerStates[arc.id] = state
      return true
    }

    let frameRange = trunkFlickerFramesMax - trunkFlickerFramesMin
    let hiddenFrameCount = trunkFlickerFramesMin
      + Int(state.random.next() % UInt64(frameRange + 1))
    state.hiddenUntil = timestamp + Double(hiddenFrameCount) * displayFrameDuration
    state.nextFlickerAt = state.hiddenUntil!
      + nextTrunkFlickerInterval(using: &state.random)
    companionArcFlickerStates[arc.id] = state
    return false
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

  private func companionArcDissipationScale(
    for segment: LightningSegmentProfile,
    arc: LightningArc,
    at timestamp: TimeInterval
  ) -> CGFloat {
    guard let growthStoppedAt = arc.growthStoppedAt else { return 1 }
    let age = max(0, timestamp - growthStoppedAt)
    guard age < arc.holdDuration else { return 0 }
    let fadeLength = segment.dissipationDelay + segment.dissipationDuration
    let fadeStart = max(0, arc.holdDuration - fadeLength)
    let progress = min(
      1,
      max(0, (age - fadeStart - segment.dissipationDelay) / segment.dissipationDuration))
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
