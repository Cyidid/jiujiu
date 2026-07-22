import Cocoa
import QuartzCore
import UserNotifications

enum PetMode: String {
    case roam
    case follow
    case corner
}

enum PetMood: String {
    case idle
    case blink
    case react
    case hop
    case groom
    case scratch
    case sleep
    case roll
}

struct PetSettings {
    static let modeKey = "mode"
    static let scaleKey = "scale"
    static let scaleVersionKey = "scaleVersion"
    static let speedKey = "speed"
    static let remindersEnabledKey = "remindersEnabled"
    static let doNotDisturbKey = "doNotDisturb"
    static let alwaysOnTopKey = "alwaysOnTop"

    var mode: PetMode
    var scale: CGFloat
    var speed: CGFloat
    var remindersEnabled: Bool
    var doNotDisturb: Bool
    var alwaysOnTop: Bool

    static func load() -> PetSettings {
        let defaults = UserDefaults.standard
        let mode = PetMode(rawValue: defaults.string(forKey: modeKey) ?? "") ?? .roam
        let storedScale = defaults.object(forKey: scaleKey) as? Double
        let scaleVersion = defaults.integer(forKey: scaleVersionKey)
        let scaleValue = Self.normalizedScale(storedScale, version: scaleVersion)
        if scaleVersion < 2 {
            defaults.set(scaleValue, forKey: scaleKey)
            defaults.set(2, forKey: scaleVersionKey)
        }
        let speedValue = defaults.object(forKey: speedKey) as? Double ?? 1.0
        let reminders = defaults.object(forKey: remindersEnabledKey) as? Bool ?? true
        let dnd = defaults.object(forKey: doNotDisturbKey) as? Bool ?? false
        let alwaysOnTop = defaults.object(forKey: alwaysOnTopKey) as? Bool ?? true
        return PetSettings(mode: mode,
                           scale: CGFloat(scaleValue),
                           speed: CGFloat(speedValue),
                           remindersEnabled: reminders,
                           doNotDisturb: dnd,
                           alwaysOnTop: alwaysOnTop)
    }

    private static func normalizedScale(_ storedScale: Double?, version: Int) -> Double {
        guard let storedScale else { return 0.34 }
        if version < 2 {
            if storedScale <= 0.50 { return 0.27 }
            if storedScale <= 0.65 { return 0.34 }
            return 0.43
        }
        return min(0.46, max(0.24, storedScale))
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(mode.rawValue, forKey: PetSettings.modeKey)
        defaults.set(Double(scale), forKey: PetSettings.scaleKey)
        defaults.set(2, forKey: PetSettings.scaleVersionKey)
        defaults.set(Double(speed), forKey: PetSettings.speedKey)
        defaults.set(remindersEnabled, forKey: PetSettings.remindersEnabledKey)
        defaults.set(doNotDisturb, forKey: PetSettings.doNotDisturbKey)
        defaults.set(alwaysOnTop, forKey: PetSettings.alwaysOnTopKey)
    }
}

struct PetStats {
    static let hungerKey = "hunger"
    static let happinessKey = "happiness"
    static let energyKey = "energy"
    static let lastUpdatedKey = "lastUpdated"

    var hunger: Int
    var happiness: Int
    var energy: Int
    var lastUpdated: Date

    static func load() -> PetStats {
        let defaults = UserDefaults.standard
        var stats = PetStats(
            hunger: defaults.object(forKey: hungerKey) as? Int ?? 74,
            happiness: defaults.object(forKey: happinessKey) as? Int ?? 78,
            energy: defaults.object(forKey: energyKey) as? Int ?? 82,
            lastUpdated: defaults.object(forKey: lastUpdatedKey) as? Date ?? Date()
        )
        stats.applyOfflineDecay()
        stats.save()
        return stats
    }

    var moodLine: String {
        if hunger < 30 { return "有点饿" }
        if energy < 28 { return "想睡觉" }
        if happiness < 35 { return "想被陪一下" }
        if hunger > 82 && happiness > 82 && energy > 72 { return "状态很好" }
        return "安静陪你"
    }

    var compactLine: String {
        "饱腹 \(hunger)%  开心 \(happiness)%  精力 \(energy)%"
    }

    mutating func adjust(hunger hungerDelta: Int = 0, happiness happinessDelta: Int = 0, energy energyDelta: Int = 0) {
        hunger = Self.clamp(hunger + hungerDelta)
        happiness = Self.clamp(happiness + happinessDelta)
        energy = Self.clamp(energy + energyDelta)
        lastUpdated = Date()
        save()
    }

    mutating func decayTick() {
        adjust(hunger: -1, happiness: -1, energy: -1)
    }

    mutating func applyOfflineDecay() {
        let minutes = Int(Date().timeIntervalSince(lastUpdated) / 60)
        guard minutes >= 20 else { return }
        let steps = min(18, minutes / 20)
        hunger = Self.clamp(hunger - steps)
        happiness = Self.clamp(happiness - max(1, steps / 2))
        energy = Self.clamp(energy - max(1, steps / 2))
        lastUpdated = Date()
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(hunger, forKey: Self.hungerKey)
        defaults.set(happiness, forKey: Self.happinessKey)
        defaults.set(energy, forKey: Self.energyKey)
        defaults.set(lastUpdated, forKey: Self.lastUpdatedKey)
    }

    private static func clamp(_ value: Int) -> Int {
        min(100, max(0, value))
    }
}

final class CatView: NSView {
    private let shadowLayer = CALayer()
    private let rigLayer = CALayer()
    private let tailLayer = CALayer()
    private let bodyLayer = CALayer()
    private let haunchLayer = CALayer()
    private let leftPawLayer = CALayer()
    private let rightPawLayer = CALayer()
    private let headLayer = CALayer()
    private let walkTailLayer = CALayer()
    private let walkRearLegLayer = CALayer()
    private let walkHindLegLayer = CALayer()
    private let walkBodyLayer = CALayer()
    private let walkFrontDownLegLayer = CALayer()
    private let walkFrontLegLayer = CALayer()
    private let walkHeadLayer = CALayer()
    private var currentMood: PetMood = .idle
    private var settleTimer: Timer?
    private var isWalking = false
    private var wasDragged = false
    private var dragStartPoint: NSPoint = .zero
    private var dragStartWindowOrigin: NSPoint = .zero
    private weak var controller: PetController?

    private var sittingLayers: [CALayer] {
        [tailLayer, haunchLayer, bodyLayer, leftPawLayer, rightPawLayer, headLayer]
    }

    private var walkingLayers: [CALayer] {
        [walkTailLayer, walkRearLegLayer, walkHindLegLayer, walkBodyLayer,
         walkFrontDownLegLayer, walkFrontLegLayer, walkHeadLayer]
    }

    private var partLayers: [CALayer] {
        sittingLayers + walkingLayers
    }

    var isPerformingAction: Bool {
        currentMood != .idle
    }

    init(frame: NSRect, controller: PetController) {
        self.controller = controller
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        setupRenderLayers()
        loadRigParts()
        showMood(.idle)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        rigLayer.frame = bounds.insetBy(dx: bounds.width * 0.08, dy: bounds.height * 0.05)
        configurePart(tailLayer, anchor: CGPoint(x: 0.43, y: 0.23))
        configurePart(haunchLayer, anchor: CGPoint(x: 0.56, y: 0.19))
        configurePart(bodyLayer, anchor: CGPoint(x: 0.56, y: 0.31))
        configurePart(leftPawLayer, anchor: CGPoint(x: 0.48, y: 0.31))
        configurePart(rightPawLayer, anchor: CGPoint(x: 0.69, y: 0.31))
        configurePart(headLayer, anchor: CGPoint(x: 0.52, y: 0.39))
        configurePart(walkTailLayer, anchor: CGPoint(x: 0.23, y: 0.37))
        configurePart(walkRearLegLayer, anchor: CGPoint(x: 0.29, y: 0.30))
        configurePart(walkHindLegLayer, anchor: CGPoint(x: 0.45, y: 0.30))
        configurePart(walkBodyLayer, anchor: CGPoint(x: 0.43, y: 0.31))
        configurePart(walkFrontDownLegLayer, anchor: CGPoint(x: 0.58, y: 0.33))
        configurePart(walkFrontLegLayer, anchor: CGPoint(x: 0.62, y: 0.36))
        configurePart(walkHeadLayer, anchor: CGPoint(x: 0.56, y: 0.34))
        shadowLayer.frame = NSRect(x: bounds.width * 0.24,
                                   y: bounds.height * 0.055,
                                   width: bounds.width * 0.52,
                                   height: max(8, bounds.height * 0.075))
        shadowLayer.cornerRadius = shadowLayer.frame.height / 2
    }

    private func setupRenderLayers() {
        guard let rootLayer = layer else { return }
        rootLayer.sublayerTransform = CATransform3DIdentity
        rootLayer.sublayerTransform.m34 = -1.0 / 700.0

        shadowLayer.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        shadowLayer.opacity = 0.7
        shadowLayer.masksToBounds = true
        rootLayer.addSublayer(shadowLayer)

        rigLayer.masksToBounds = false
        rootLayer.addSublayer(rigLayer)
        for part in partLayers {
            part.contentsGravity = .resizeAspect
            part.minificationFilter = .linear
            part.magnificationFilter = .linear
            part.masksToBounds = false
            rigLayer.addSublayer(part)
        }
        needsLayout = true
    }

    private func configurePart(_ part: CALayer, anchor: CGPoint) {
        part.bounds = rigLayer.bounds
        part.anchorPoint = anchor
        part.position = CGPoint(x: rigLayer.bounds.width * anchor.x,
                                y: rigLayer.bounds.height * anchor.y)
    }

    private func loadRigParts() {
        let resources: [(CALayer, String)] = [
            (tailLayer, "rig_tail"),
            (bodyLayer, "rig_body"),
            (haunchLayer, "rig_haunches"),
            (leftPawLayer, "rig_paw_left"),
            (rightPawLayer, "rig_paw_right"),
            (headLayer, "rig_head"),
            (walkTailLayer, "walk_tail"),
            (walkRearLegLayer, "walk_rear_leg"),
            (walkHindLegLayer, "walk_hind_leg"),
            (walkBodyLayer, "walk_body"),
            (walkFrontDownLegLayer, "walk_front_down_leg"),
            (walkFrontLegLayer, "walk_front_leg"),
            (walkHeadLayer, "walk_head")
        ]
        for (part, name) in resources {
            guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
                  let image = NSImage(contentsOf: url) else { continue }
            part.contents = image
        }
        setWalkingPose(false)
    }

    private func setWalkingPose(_ walking: Bool, animated: Bool = false) {
        let sittingOpacity: Float = walking ? 0 : 1
        let walkingOpacity: Float = walking ? 1 : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sittingLayers.forEach { $0.opacity = sittingOpacity }
        walkingLayers.forEach { $0.opacity = walkingOpacity }
        CATransaction.commit()

        guard animated else { return }
        for layer in sittingLayers {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = walking ? 1 : 0
            fade.toValue = sittingOpacity
            fade.duration = 0.14
            layer.add(fade, forKey: "poseFade")
        }
        for layer in walkingLayers {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = walking ? 0 : 1
            fade.toValue = walkingOpacity
            fade.duration = 0.14
            layer.add(fade, forKey: "poseFade")
        }
    }

    private func showMood(_ mood: PetMood) {
        currentMood = mood
        clearActionMotion()
        if mood == .idle {
            startIdleMotion()
        }
    }

    func play(_ mood: PetMood, frameDuration: TimeInterval = 0.16, loops: Int = 1) {
        settleTimer?.invalidate()
        currentMood = mood
        isWalking = false
        let actionFrames: [PetMood: Int] = [.blink: 4, .hop: 8, .groom: 7, .scratch: 12, .roll: 8]
        let duration = frameDuration * Double(actionFrames[mood] ?? 5) * Double(max(1, loops))
        applyActionMotion(for: mood, duration: duration)
        settleTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.showMood(.idle)
        }
    }

    func playIfIdle(_ mood: PetMood, frameDuration: TimeInterval = 0.16, loops: Int = 1) {
        guard currentMood == .idle else { return }
        play(mood, frameDuration: frameDuration, loops: loops)
    }

    func startSleepLoop() {
        settleTimer?.invalidate()
        currentMood = .sleep
        isWalking = false
        clearActionMotion()
        applySleepMotion()
        settleTimer = Timer.scheduledTimer(withTimeInterval: 18, repeats: false) { [weak self] _ in
            self?.showMood(.idle)
        }
    }

    func startSleepIfIdle() {
        guard currentMood == .idle else { return }
        startSleepLoop()
    }

    private func clearActionMotion() {
        rigLayer.removeAllAnimations()
        shadowLayer.removeAllAnimations()
        partLayers.forEach { $0.removeAllAnimations() }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rigLayer.transform = CATransform3DIdentity
        partLayers.forEach { $0.transform = CATransform3DIdentity }
        headLayer.transform = CATransform3DMakeRotation(-0.18, 0, 0, 1)
        walkHeadLayer.transform = CATransform3DIdentity
        shadowLayer.opacity = 0.7
        CATransaction.commit()
        setWalkingPose(false)
    }

    private func keyframe(_ keyPath: String,
                          values: [CGFloat],
                          duration: TimeInterval,
                          keyTimes: [NSNumber]? = nil,
                          additive: Bool = true,
                          repeatCount: Float = 0) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = keyTimes
        animation.duration = duration
        animation.isAdditive = additive
        animation.calculationMode = .cubic
        animation.repeatCount = repeatCount
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut),
                                          count: max(1, values.count - 1))
        return animation
    }

    private func applyActionMotion(for mood: PetMood, duration: TimeInterval) {
        clearActionMotion()
        let total = max(0.18, duration)
        switch mood {
        case .idle:
            break
        case .blink:
            add(headLayer, "transform.scale.y", [1.0, 0.94, 1.0], total, additive: false)
            add(headLayer, "transform.rotation.z", [0, -0.025, 0], total)
            add(leftPawLayer, "transform.rotation.z", [0, 0.035, 0], total)
            add(rightPawLayer, "transform.rotation.z", [0, -0.035, 0], total)
        case .react:
            break
        case .hop:
            let lift = max(18, bounds.height * 0.18)
            let times: [NSNumber] = [0, 0.14, 0.36, 0.62, 0.82, 1]
            add(rigLayer, "transform.translation.y", [0, -lift * 0.08, lift, lift * 0.62, -lift * 0.06, 0], total, times)
            add(bodyLayer, "transform.scale.y", [1, 0.91, 1.07, 1.02, 0.9, 1], total, times, additive: false)
            add(haunchLayer, "transform.scale.x", [1, 1.08, 0.95, 0.98, 1.1, 1], total, times, additive: false)
            add(headLayer, "transform.translation.y", [0, -5, -10, 4, 2, 0], total, times)
            add(headLayer, "transform.rotation.z", [0, -0.05, 0.04, -0.025, 0.018, 0], total, times)
            add(leftPawLayer, "transform.rotation.z", [0, -0.12, 0.3, 0.24, -0.08, 0], total, times)
            add(rightPawLayer, "transform.rotation.z", [0, 0.12, -0.3, -0.24, 0.08, 0], total, times)
            add(leftPawLayer, "transform.translation.y", [0, -2, 15, 12, -4, 0], total, times)
            add(rightPawLayer, "transform.translation.y", [0, -2, 15, 12, -4, 0], total, times)
            add(tailLayer, "transform.rotation.z", [0, -0.16, 0.34, -0.24, 0.14, 0], total, times)
            addShadowPulse(scale: [1.05, 0.76, 0.66, 0.82, 1.22, 1.0],
                           opacity: [0.72, 0.42, 0.34, 0.48, 0.86, 0.7],
                           duration: total,
                           keyTimes: times)
        case .groom:
            let times: [NSNumber] = [0, 0.18, 0.36, 0.54, 0.72, 0.9, 1]
            add(leftPawLayer, "transform.translation.y", [0, 45, 58, 48, 60, 42, 0], total, times)
            add(leftPawLayer, "transform.translation.x", [0, -7, -13, -4, -14, -5, 0], total, times)
            add(leftPawLayer, "transform.rotation.z", [0, -0.42, -0.58, -0.36, -0.6, -0.3, 0], total, times)
            add(headLayer, "transform.rotation.z", [0, 0.08, 0.13, 0.05, 0.14, 0.06, 0], total, times)
            add(headLayer, "transform.translation.x", [0, -2, -5, -1, -5, -2, 0], total, times)
            add(rightPawLayer, "transform.rotation.z", [0, 0.04, 0.02, 0.05, 0.02, 0.03, 0], total, times)
            add(tailLayer, "transform.rotation.z", [0, 0.12, -0.08, 0.14, -0.06, 0.1, 0], total, times)
        case .scratch:
            let times: [NSNumber] = [0, 0.1, 0.2, 0.32, 0.44, 0.56, 0.68, 0.8, 0.9, 1]
            add(rigLayer, "transform.translation.y", [0, -3, -4, -4, -4, -4, -4, -3, -1, 0], total, times)
            add(bodyLayer, "transform.scale.y", [1, 0.96, 0.95, 0.955, 0.95, 0.955, 0.95, 0.965, 0.985, 1],
                total, times, additive: false)
            add(headLayer, "transform.translation.y", [0, -2, -4, -3, -4, -3, -4, -2, -1, 0], total, times)
            add(headLayer, "transform.translation.x", [0, 0, -1, 1, -1, 1, -1, 0, 0, 0], total, times)
            add(leftPawLayer, "transform.translation.y", [0, 2, -5, 4, -6, 4, -6, 3, 1, 0], total, times)
            add(leftPawLayer, "transform.translation.x", [0, -2, 5, -4, 6, -4, 6, -3, 1, 0], total, times)
            add(leftPawLayer, "transform.rotation.z", [0, -0.04, 0.13, -0.1, 0.15, -0.1, 0.14, -0.06, 0.02, 0], total, times)
            add(rightPawLayer, "transform.translation.y", [0, -4, 3, -6, 4, -6, 4, -5, 1, 0], total, times)
            add(rightPawLayer, "transform.translation.x", [0, -5, 4, -6, 4, -6, 4, -5, -1, 0], total, times)
            add(rightPawLayer, "transform.rotation.z", [0, -0.12, 0.08, -0.15, 0.1, -0.15, 0.1, -0.12, -0.02, 0], total, times)
            add(haunchLayer, "transform.scale.x", [1, 1.035, 1.04, 1.025, 1.04, 1.025, 1.04, 1.02, 1.01, 1],
                total, times, additive: false)
            add(tailLayer, "transform.rotation.z", [0, -0.08, 0.1, -0.12, 0.13, -0.12, 0.11, -0.07, 0.03, 0], total, times)
            addShadowPulse(scale: [1, 1.05, 1.08, 1.04, 1.08, 1.04, 1.08, 1.04, 1.01, 1],
                           opacity: [0.68, 0.73, 0.76, 0.72, 0.76, 0.72, 0.76, 0.72, 0.69, 0.68],
                           duration: total,
                           keyTimes: times)
        case .sleep:
            applySleepMotion()
        case .roll:
            let times: [NSNumber] = [0, 0.13, 0.27, 0.42, 0.58, 0.73, 0.88, 1]
            add(rigLayer, "transform.rotation.z", [0, 0.75, 1.55, 2.45, 3.25, 4.15, 5.15, 6.28], total, times)
            add(rigLayer, "transform.translation.y", [0, 16, 24, 12, -5, 8, 14, 0], total, times)
            add(leftPawLayer, "transform.rotation.z", [0, 0.38, 0.48, 0.4, 0.32, 0.22, 0.1, 0], total, times)
            add(rightPawLayer, "transform.rotation.z", [0, -0.38, -0.48, -0.4, -0.32, -0.22, -0.1, 0], total, times)
            add(tailLayer, "transform.rotation.z", [0, -0.3, -0.45, -0.2, 0.2, 0.42, 0.2, 0], total, times)
            add(headLayer, "transform.scale", [1, 0.96, 0.93, 0.94, 0.96, 0.98, 1.01, 1], total, times, additive: false)
            addShadowPulse(scale: [1.0, 0.9, 1.12, 0.94, 1.0],
                           opacity: [0.7, 0.48, 0.78, 0.58, 0.7],
                           duration: total)
        }
    }

    private func add(_ target: CALayer,
                     _ keyPath: String,
                     _ values: [CGFloat],
                     _ duration: TimeInterval,
                     _ keyTimes: [NSNumber]? = nil,
                     additive: Bool = true,
                     repeatCount: Float = 0,
                     key: String? = nil) {
        target.add(keyframe(keyPath,
                            values: values,
                            duration: duration,
                            keyTimes: keyTimes,
                            additive: additive,
                            repeatCount: repeatCount),
                   forKey: key ?? keyPath)
    }

    private func applySleepMotion() {
        clearActionMotion()
        let duration: TimeInterval = 2.9
        add(rigLayer, "transform.translation.y", [0, -7, -7], 0.45, additive: true)
        add(bodyLayer, "transform.scale.y", [0.96, 0.985, 0.96], duration, additive: false, repeatCount: .infinity)
        add(haunchLayer, "transform.scale.x", [1.04, 1.08, 1.04], duration, additive: false, repeatCount: .infinity)
        add(headLayer, "transform.rotation.z", [-0.08, -0.055, -0.08], duration, repeatCount: .infinity)
        add(headLayer, "transform.translation.y", [-5, -2, -5], duration, repeatCount: .infinity)
        add(leftPawLayer, "transform.rotation.z", [0.12, 0.15, 0.12], duration, repeatCount: .infinity)
        add(rightPawLayer, "transform.rotation.z", [-0.12, -0.15, -0.12], duration, repeatCount: .infinity)
        add(tailLayer, "transform.rotation.z", [-0.28, -0.22, -0.28], duration, repeatCount: .infinity)
        addShadowPulse(scale: [1.0, 1.08, 1.0],
                       opacity: [0.62, 0.76, 0.62],
                       duration: duration,
                       repeatForever: true)
    }

    private func startIdleMotion() {
        add(bodyLayer, "transform.scale.y", [0.995, 1.018, 0.995], 2.5,
            additive: false, repeatCount: .infinity, key: "idleBreath")
        add(tailLayer, "transform.rotation.z", [-0.055, 0.075, -0.055], 2.6,
            repeatCount: .infinity, key: "idleTail")
        addShadowPulse(scale: [0.97, 1.03, 0.97],
                       opacity: [0.64, 0.72, 0.64],
                       duration: 2.5,
                       repeatForever: true)
    }

    private func startWalkCycle() {
        guard !isWalking, currentMood == .idle else { return }
        clearActionMotion()
        isWalking = true
        setWalkingPose(true, animated: true)
        let forever = Float.infinity
        add(walkFrontLegLayer, "transform.rotation.z", [-0.055, 0.06, -0.055], 0.54,
            repeatCount: forever, key: "walkFrontRotation")
        add(walkFrontLegLayer, "transform.translation.y", [0, 2.4, 0], 0.54,
            repeatCount: forever, key: "walkFrontLift")
        add(walkRearLegLayer, "transform.rotation.z", [0.055, -0.055, 0.055], 0.54,
            repeatCount: forever, key: "walkRearRotation")
        add(walkRearLegLayer, "transform.translation.y", [2.4, 0, 2.4], 0.54,
            repeatCount: forever, key: "walkRearLift")
        add(walkHindLegLayer, "transform.rotation.z", [-0.045, 0.045, -0.045], 0.54,
            repeatCount: forever, key: "walkHindRotation")
        add(walkHindLegLayer, "transform.translation.y", [0, 2, 0], 0.54,
            repeatCount: forever, key: "walkHindLift")
        add(walkFrontDownLegLayer, "transform.rotation.z", [0.045, -0.045, 0.045], 0.54,
            repeatCount: forever, key: "walkFrontDownRotation")
        add(walkFrontDownLegLayer, "transform.translation.y", [2, 0, 2], 0.54,
            repeatCount: forever, key: "walkFrontDownLift")
        add(walkBodyLayer, "transform.translation.y", [0, 1.4, 0], 0.27,
            repeatCount: forever, key: "walkBodyBob")
        add(walkBodyLayer, "transform.scale.x", [1, 1.006, 1], 0.54,
            additive: false, repeatCount: forever, key: "walkBodyStride")
        add(walkHeadLayer, "transform.translation.y", [0.4, -0.7, 0.4], 0.54,
            repeatCount: forever, key: "walkHeadBob")
        add(walkTailLayer, "transform.rotation.z", [-0.045, 0.055, -0.045], 0.82,
            repeatCount: forever, key: "walkTail")
        addShadowPulse(scale: [0.94, 1.04, 0.94],
                       opacity: [0.62, 0.74, 0.62],
                       duration: 0.54,
                       repeatForever: true)
    }

    private func finishInteraction(after duration: TimeInterval) {
        settleTimer?.invalidate()
        settleTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.showMood(.idle)
        }
    }

    private func reactToClick(at location: NSPoint) {
        currentMood = .react
        isWalking = false
        clearActionMotion()
        let direction: CGFloat = location.x < bounds.midX ? -1 : 1
        let total: TimeInterval = 0.72
        let times: [NSNumber] = [0, 0.16, 0.42, 0.72, 1]

        add(headLayer, "transform.rotation.z",
            [0, direction * 0.025, direction * 0.04, -direction * 0.012, 0], total, times)
        add(headLayer, "transform.translation.x",
            [0, direction * 2, direction * 3.5, direction, 0], total, times)
        add(headLayer, "transform.translation.y", [0, -1, 1.5, 0.5, 0], total, times)
        add(bodyLayer, "transform.scale.y", [1, 0.985, 1.012, 1.004, 1], total, times, additive: false)
        add(rigLayer, "transform.translation.y", [0, -1.5, 2.5, 1, 0], total, times)
        add(tailLayer, "transform.rotation.z",
            [0, -direction * 0.08, direction * 0.14, -direction * 0.045, 0], total, times)

        let respondingPaw = direction < 0 ? leftPawLayer : rightPawLayer
        add(respondingPaw, "transform.translation.y", [0, 3, 8, 3, 0], total, times)
        add(respondingPaw, "transform.rotation.z",
            [0, -direction * 0.025, -direction * 0.07, -direction * 0.02, 0], total, times)
        addShadowPulse(scale: [1, 1.03, 0.97, 1.01, 1],
                       opacity: [0.68, 0.72, 0.64, 0.69, 0.68],
                       duration: total,
                       keyTimes: times)
        finishInteraction(after: total)
    }

    private func settleAfterDrag() {
        currentMood = .react
        isWalking = false
        clearActionMotion()
        let total: TimeInterval = 0.46
        let times: [NSNumber] = [0, 0.28, 0.62, 1]
        add(rigLayer, "transform.translation.y", [4, -2, 1, 0], total, times)
        add(bodyLayer, "transform.scale.y", [1.02, 0.975, 1.008, 1], total, times, additive: false)
        add(leftPawLayer, "transform.rotation.z", [-0.04, 0.035, -0.012, 0], total, times)
        add(rightPawLayer, "transform.rotation.z", [0.04, -0.035, 0.012, 0], total, times)
        add(tailLayer, "transform.rotation.z", [0.08, -0.05, 0.02, 0], total, times)
        finishInteraction(after: total)
    }

    private func stopWalkCycle() {
        guard isWalking else { return }
        isWalking = false
        clearActionMotion()
        setWalkingPose(false, animated: true)
        startIdleMotion()
    }

    private func addShadowPulse(scale: [CGFloat],
                                opacity: [CGFloat],
                                duration: TimeInterval,
                                keyTimes: [NSNumber]? = nil,
                                repeatForever: Bool = false) {
        let shadowScale = keyframe("transform.scale.x",
                                   values: scale,
                                   duration: duration,
                                   keyTimes: keyTimes,
                                   additive: false)
        let shadowOpacity = keyframe("opacity",
                                     values: opacity,
                                     duration: duration,
                                     keyTimes: keyTimes,
                                     additive: false)
        if repeatForever {
            shadowScale.repeatCount = .infinity
            shadowOpacity.repeatCount = .infinity
        }
        shadowLayer.add(shadowScale, forKey: "actionShadowScale")
        shadowLayer.add(shadowOpacity, forKey: "actionShadowOpacity")
    }

    func setMotionTilt(dx: CGFloat, dy: CGFloat) {
        guard currentMood == .idle else { return }
        let moving = hypot(dx, dy) > 0.5
        if moving {
            startWalkCycle()
        } else {
            stopWalkCycle()
        }
        let limitedX = max(-1.0, min(1.0, dx / 4.0))
        let transform = CATransform3DMakeScale(limitedX < 0 ? -1 : 1, 1, 1)

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        rigLayer.transform = transform
        shadowLayer.opacity = Float(0.6 + min(0.12, abs(limitedX) * 0.1))
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        dragStartPoint = event.locationInWindow
        dragStartWindowOrigin = window?.frame.origin ?? .zero
        wasDragged = false
        controller?.pauseMovement()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let current = event.locationInWindow
        let dx = current.x - dragStartPoint.x
        let dy = current.y - dragStartPoint.y
        if hypot(dx, dy) > 3 {
            wasDragged = true
        }
        window.setFrameOrigin(NSPoint(x: dragStartWindowOrigin.x + dx, y: dragStartWindowOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        controller?.resumeMovementAfterInteraction()
        if wasDragged {
            settleAfterDrag()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = controller?.makeMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc func clickReact() {
        let windowPoint = window?.mouseLocationOutsideOfEventStream ?? NSPoint(x: bounds.midX, y: bounds.midY)
        reactToClick(at: convert(windowPoint, from: nil))
        controller?.receiveClick()
    }

    func runInteractionPreview() {
        reactToClick(at: NSPoint(x: bounds.midX * 0.72, y: bounds.midY))
    }

    func runScratchPreview() {
        play(.scratch, frameDuration: 0.11, loops: 1)
    }
}

final class TianMiaoWindow: NSWindow {
    override var canBecomeKey: Bool { true }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isMovable = false
        ignoresMouseEvents = false
    }
}

final class BubbleWindow: NSWindow {
    private let label = NSTextField(labelWithString: "")
    private let bubbleSize = NSSize(width: 176, height: 46)

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: bubbleSize),
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        ignoresMouseEvents = true

        let content = NSView(frame: NSRect(origin: .zero, size: bubbleSize))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.92).cgColor
        content.layer?.cornerRadius = 14
        content.layer?.borderColor = NSColor(calibratedWhite: 0.86, alpha: 1).cgColor
        content.layer?.borderWidth = 1

        label.frame = NSRect(x: 10, y: 7, width: bubbleSize.width - 20, height: bubbleSize.height - 14)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = NSColor(calibratedWhite: 0.18, alpha: 1)
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
        content.addSubview(label)
        self.contentView = content
    }

    func show(_ message: String, near frame: NSRect, for seconds: TimeInterval = 3.2) {
        label.stringValue = message
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let rawOrigin = NSPoint(x: frame.midX - self.frame.width / 2, y: frame.maxY + 8)
        let origin = NSPoint(
            x: min(max(rawOrigin.x, screen.minX + 8), screen.maxX - self.frame.width - 8),
            y: min(max(rawOrigin.y, screen.minY + 8), screen.maxY - self.frame.height - 8)
        )
        setFrameOrigin(origin)
        orderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.orderOut(nil)
        }
    }
}

final class PetController: NSObject {
    private(set) var window: TianMiaoWindow!
    private(set) var catView: CatView!
    private let bubbleWindow = BubbleWindow()
    private var movementTimer: Timer?
    private var behaviorTimer: Timer?
    private var reminderTimer: Timer?
    private var decayTimer: Timer?
    private var focusTimer: Timer?
    private var velocity = CGVector(dx: -1.45, dy: 0)
    private var isRoamWalking = true
    private var roamTransitionAt = Date().addingTimeInterval(5)
    private var settings = PetSettings.load()
    private var stats = PetStats.load()
    private let baseSize = NSSize(width: 360, height: 392)

    func start() {
        let size = currentSize()
        window = TianMiaoWindow(contentRect: NSRect(origin: initialOrigin(size: size), size: size))
        window.level = settings.alwaysOnTop ? .floating : .normal
        catView = CatView(frame: NSRect(origin: .zero, size: size), controller: self)
        window.contentView = catView

        let singleClick = NSClickGestureRecognizer(target: catView, action: #selector(CatView.clickReact))
        singleClick.numberOfClicksRequired = 1
        singleClick.delaysPrimaryMouseButtonEvents = false
        catView.addGestureRecognizer(singleClick)

        window.makeKeyAndOrderFront(nil)
        startMovement()
        startAmbientBehaviors()
        startGentleReminders()
        startNeedsDecay()
        showBubble("甜喵来啦，\(stats.moodLine)")
        if ProcessInfo.processInfo.environment["TIANMIAO_PREVIEW_INTERACTION"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.catView.runInteractionPreview()
            }
        }
        if ProcessInfo.processInfo.environment["TIANMIAO_PREVIEW_ACTION"] == "scratch" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.catView.runScratchPreview()
            }
        }
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let status = NSMenuItem(title: stats.compactLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(NSMenuItem(title: "看状态", action: #selector(showStatus), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "喂小鱼干", action: #selector(feed), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "陪它玩", action: #selector(playTogether), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "摸摸头", action: #selector(pat), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(item("自由游走", action: #selector(setRoam), checked: settings.mode == .roam))
        menu.addItem(item("跟随鼠标", action: #selector(setFollow), checked: settings.mode == .follow))
        menu.addItem(item("角落休息", action: #selector(setCorner), checked: settings.mode == .corner))
        menu.addItem(NSMenuItem(title: "召唤到鼠标旁", action: #selector(summonToMouse), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(item("小一点", action: #selector(sizeSmall), checked: abs(settings.scale - 0.27) < 0.01))
        menu.addItem(item("标准大小", action: #selector(sizeNormal), checked: abs(settings.scale - 0.34) < 0.01))
        menu.addItem(item("大一点", action: #selector(sizeLarge), checked: abs(settings.scale - 0.43) < 0.01))
        menu.addItem(.separator())
        menu.addItem(item("慢悠悠", action: #selector(speedSlow), checked: settings.speed == 0.65))
        menu.addItem(item("正常速度", action: #selector(speedNormal), checked: settings.speed == 1.0))
        menu.addItem(item("精神一点", action: #selector(speedFast), checked: settings.speed == 1.45))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "打个滚", action: #selector(roll), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "梳毛", action: #selector(groom), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "挠一挠", action: #selector(scratch), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "睡一会儿", action: #selector(nap), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(item("置顶显示", action: #selector(toggleAlwaysOnTop), checked: settings.alwaysOnTop))
        menu.addItem(item("休息提醒", action: #selector(toggleReminders), checked: settings.remindersEnabled))
        menu.addItem(item("勿扰模式", action: #selector(toggleDoNotDisturb), checked: settings.doNotDisturb))
        menu.addItem(NSMenuItem(title: "开始 25 分钟专注", action: #selector(startFocus), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出甜喵物语", action: #selector(quit), keyEquivalent: "q"))
        for menuItem in menu.items where menuItem.action != nil && menuItem.target == nil {
            menuItem.target = self
        }
        return menu
    }

    private func item(_ title: String, action: Selector, checked: Bool) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.state = checked ? .on : .off
        menuItem.target = self
        return menuItem
    }

    private func currentSize() -> NSSize {
        NSSize(width: baseSize.width * settings.scale, height: baseSize.height * settings.scale)
    }

    private func initialOrigin(size: NSSize) -> NSPoint {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: screen.maxX - size.width - 32, y: groundY(in: screen))
    }

    private func groundY(in screen: NSRect) -> CGFloat {
        screen.minY + 12
    }

    private func startMovement() {
        movementTimer?.invalidate()
        movementTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tickMovement()
        }
    }

    private func startAmbientBehaviors() {
        behaviorTimer?.invalidate()
        behaviorTimer = Timer.scheduledTimer(withTimeInterval: 7.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let roll = Int.random(in: 0..<100)
            if roll < 34 {
                self.catView.playIfIdle(.blink, frameDuration: 0.11, loops: 1)
            } else if roll < 54 {
                self.catView.playIfIdle(.groom, frameDuration: 0.16, loops: 1)
            } else if roll < 78 {
                self.catView.playIfIdle(.scratch, frameDuration: 0.11, loops: 1)
            } else if roll < 90 {
                self.catView.playIfIdle(.hop, frameDuration: 0.12, loops: 1)
            } else {
                self.catView.startSleepIfIdle()
            }
        }
    }

    private func startGentleReminders() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        reminderTimer?.invalidate()
        guard settings.remindersEnabled else { return }
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 45 * 60, repeats: true) { [weak self] _ in
            self?.showReminder("休息一下，喝口水")
        }
    }

    private func startNeedsDecay() {
        decayTimer?.invalidate()
        decayTimer = Timer.scheduledTimer(withTimeInterval: 8 * 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.stats.decayTick()
            if self.stats.hunger < 26 {
                self.showBubble("有点饿，想吃小鱼干")
            } else if self.stats.energy < 24 {
                self.catView.startSleepLoop()
                self.showBubble("甜喵困了")
            } else if self.stats.happiness < 28 {
                self.showBubble("想被陪一下")
            }
        }
    }

    private func tickMovement() {
        guard let window else { return }
        switch settings.mode {
        case .roam:
            roam(window)
        case .follow:
            followMouse(window)
        case .corner:
            moveTowardCorner(window)
        }
    }

    private func roam(_ window: NSWindow) {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var frame = window.frame
        frame.origin.y += (groundY(in: screen) - frame.origin.y) * 0.16

        if catView.isPerformingAction {
            window.setFrameOrigin(frame.origin)
            return
        }

        if Date() >= roamTransitionAt {
            isRoamWalking.toggle()
            if isRoamWalking {
                let magnitude = CGFloat.random(in: 1.15...1.7)
                velocity.dx = Bool.random() ? magnitude : -magnitude
                roamTransitionAt = Date().addingTimeInterval(Double.random(in: 4.5...9.0))
            } else {
                roamTransitionAt = Date().addingTimeInterval(Double.random(in: 1.8...4.5))
            }
        }

        guard isRoamWalking else {
            catView.setMotionTilt(dx: 0, dy: 0)
            window.setFrameOrigin(frame.origin)
            return
        }

        frame.origin.x += velocity.dx * settings.speed * 0.52

        if frame.minX < screen.minX || frame.maxX > screen.maxX {
            velocity.dx *= -1
            frame.origin.x = min(max(frame.origin.x, screen.minX), screen.maxX - frame.width)
            isRoamWalking = false
            roamTransitionAt = Date().addingTimeInterval(Double.random(in: 0.8...1.8))
        }
        catView.setMotionTilt(dx: velocity.dx, dy: 0)
        window.setFrameOrigin(frame.origin)
    }

    private func followMouse(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let frame = window.frame
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let target = NSPoint(x: min(max(mouse.x - frame.width / 2, screen.minX), screen.maxX - frame.width),
                             y: groundY(in: screen))
        catView.setMotionTilt(dx: target.x - frame.origin.x, dy: 0)
        move(window, toward: target, easing: 0.045 * settings.speed)
    }

    private func moveTowardCorner(_ window: NSWindow) {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let target = NSPoint(x: screen.maxX - window.frame.width - 28, y: groundY(in: screen))
        catView.setMotionTilt(dx: target.x - window.frame.origin.x, dy: 0)
        move(window, toward: target, easing: 0.05)
    }

    private func move(_ window: NSWindow, toward target: NSPoint, easing: CGFloat) {
        var origin = window.frame.origin
        origin.x += (target.x - origin.x) * easing
        origin.y += (target.y - origin.y) * easing
        window.setFrameOrigin(origin)
    }

    func pauseMovement() {
        movementTimer?.invalidate()
    }

    func resumeMovementAfterInteraction() {
        settings.mode = .roam
        settings.save()
        isRoamWalking = true
        roamTransitionAt = Date().addingTimeInterval(Double.random(in: 4.5...8.0))
        startMovement()
    }

    func nudgeAwayFromMouse() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        velocity = CGVector(dx: center.x >= mouse.x ? 1.7 : -1.7, dy: 0)
    }

    func receiveClick() {
        stats.adjust(happiness: 2)
        if Int.random(in: 0..<3) == 0 {
            showBubble(["在呢", "喵", stats.moodLine].randomElement() ?? "喵")
        }
    }

    func showBubble(_ message: String, seconds: TimeInterval = 3.2) {
        guard !settings.doNotDisturb, let window else { return }
        bubbleWindow.level = settings.alwaysOnTop ? .floating : .normal
        bubbleWindow.show(message, near: window.frame, for: seconds)
    }

    private func showReminder(_ message: String) {
        guard settings.remindersEnabled, !settings.doNotDisturb else { return }
        let content = UNMutableNotificationContent()
        content.title = "甜喵物语"
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: "tianmiao-break-\(Date().timeIntervalSince1970)",
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
        catView.play(.hop, frameDuration: 0.12, loops: 2)
    }

    private func applySettings() {
        settings.save()
        let size = currentSize()
        guard let window else { return }
        window.level = settings.alwaysOnTop ? .floating : .normal
        window.setFrame(NSRect(origin: window.frame.origin, size: size), display: true, animate: true)
        catView.frame = NSRect(origin: .zero, size: size)
        if settings.mode == .corner {
            moveTowardCorner(window)
        }
        startMovement()
    }

    @objc private func setRoam() {
        settings.mode = .roam
        isRoamWalking = true
        roamTransitionAt = Date().addingTimeInterval(Double.random(in: 4.5...8.0))
        applySettings()
        showBubble("我去逛逛")
    }

    @objc private func setFollow() {
        settings.mode = .follow
        applySettings()
        showBubble("跟着你走")
    }

    @objc private func setCorner() {
        settings.mode = .corner
        applySettings()
        catView.startSleepLoop()
        showBubble("我在角落陪你")
    }

    @objc private func sizeSmall() {
        settings.scale = 0.27
        applySettings()
        showBubble("变小一点")
    }

    @objc private func sizeNormal() {
        settings.scale = 0.34
        applySettings()
        showBubble("标准大小")
    }

    @objc private func sizeLarge() {
        settings.scale = 0.43
        applySettings()
        showBubble("变大一点")
    }

    @objc private func speedSlow() {
        settings.speed = 0.65
        applySettings()
        showBubble("慢悠悠")
    }

    @objc private func speedNormal() {
        settings.speed = 1.0
        applySettings()
        showBubble("正常速度")
    }

    @objc private func speedFast() {
        settings.speed = 1.45
        applySettings()
        showBubble("精神起来了")
    }

    @objc private func roll() {
        stats.adjust(happiness: 4, energy: -3)
        catView.play(.roll, frameDuration: 0.08, loops: 1)
        showBubble("咕噜")
    }

    @objc private func groom() {
        stats.adjust(happiness: 3, energy: -1)
        catView.play(.groom, frameDuration: 0.15, loops: 2)
        showBubble("把毛整理好")
    }

    @objc private func scratch() {
        stats.adjust(happiness: 4, energy: -2)
        catView.play(.scratch, frameDuration: 0.11, loops: 1)
        showBubble("磨磨小爪子")
    }

    @objc private func nap() {
        stats.adjust(energy: 10)
        catView.startSleepLoop()
        showBubble("睡一小会儿")
    }

    @objc private func showStatus() {
        showBubble("\(stats.moodLine)\n\(stats.compactLine)", seconds: 5.0)
    }

    @objc private func feed() {
        stats.adjust(hunger: 18, happiness: 5, energy: 2)
        catView.play(.groom, frameDuration: 0.13, loops: 1)
        showBubble("小鱼干真好吃")
    }

    @objc private func playTogether() {
        stats.adjust(hunger: -5, happiness: 16, energy: -8)
        catView.play(.hop, frameDuration: 0.1, loops: 2)
        nudgeAwayFromMouse()
        showBubble("再玩一下")
    }

    @objc private func pat() {
        stats.adjust(happiness: 10, energy: 2)
        catView.play(.blink, frameDuration: 0.1, loops: 2)
        showBubble("呼噜呼噜")
    }

    @objc private func summonToMouse() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: min(max(mouse.x - window.frame.width / 2, screen.minX), screen.maxX - window.frame.width),
                             y: groundY(in: screen))
        window.setFrameOrigin(origin)
        settings.mode = .follow
        settings.save()
        startMovement()
        showBubble("我来了")
    }

    @objc private func toggleAlwaysOnTop() {
        settings.alwaysOnTop.toggle()
        settings.save()
        window.level = settings.alwaysOnTop ? .floating : .normal
        showBubble(settings.alwaysOnTop ? "继续置顶" : "不挡你了")
    }

    @objc private func toggleReminders() {
        settings.remindersEnabled.toggle()
        settings.save()
        startGentleReminders()
        showBubble(settings.remindersEnabled ? "休息提醒已开启" : "休息提醒已关闭")
    }

    @objc private func toggleDoNotDisturb() {
        settings.doNotDisturb.toggle()
        settings.save()
        if settings.doNotDisturb {
            bubbleWindow.orderOut(nil)
        } else {
            showBubble("勿扰已关闭")
        }
    }

    @objc private func startFocus() {
        focusTimer?.invalidate()
        settings.mode = .corner
        settings.save()
        applySettings()
        catView.startSleepLoop()
        showBubble("开始 25 分钟专注", seconds: 4.0)
        focusTimer = Timer.scheduledTimer(withTimeInterval: 25 * 60, repeats: false) { [weak self] _ in
            self?.stats.adjust(happiness: 6, energy: 6)
            self?.showReminder("专注结束，起来活动一下")
            self?.catView.play(.hop, frameDuration: 0.11, loops: 3)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let petController = PetController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        petController.start()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
