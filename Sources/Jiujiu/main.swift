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
    case hop
    case groom
    case sleep
    case roll
}

struct PetSettings {
    static let modeKey = "mode"
    static let scaleKey = "scale"
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
        let scaleValue = Self.normalizedScale(storedScale)
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

    private static func normalizedScale(_ storedScale: Double?) -> Double {
        guard let storedScale else { return 0.58 }
        if storedScale > 0.8 {
            return 0.58
        }
        return min(0.78, max(0.42, storedScale))
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(mode.rawValue, forKey: PetSettings.modeKey)
        defaults.set(Double(scale), forKey: PetSettings.scaleKey)
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
    private let spriteLayer = CALayer()
    private let shadowLayer = CALayer()
    private var frames: [PetMood: [NSImage]] = [:]
    private var currentMood: PetMood = .idle
    private var frameIndex = 0
    private var animationTimer: Timer?
    private var settleTimer: Timer?
    private var dragStartPoint: NSPoint = .zero
    private var dragStartWindowOrigin: NSPoint = .zero
    private weak var controller: PetController?

    init(frame: NSRect, controller: PetController) {
        self.controller = controller
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        setupRenderLayers()
        loadFrames()
        showMood(.idle)
        startBreathing()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let spriteFrame = bounds.insetBy(dx: bounds.width * 0.08, dy: bounds.height * 0.05)
        spriteLayer.frame = spriteFrame
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

        spriteLayer.contentsGravity = .resizeAspect
        spriteLayer.minificationFilter = .nearest
        spriteLayer.magnificationFilter = .nearest
        spriteLayer.anchorPoint = CGPoint(x: 0.5, y: 0.44)
        spriteLayer.masksToBounds = false
        rootLayer.addSublayer(spriteLayer)
        needsLayout = true
    }

    private func loadFrames() {
        frames[.idle] = loadSequence(["normal"])
        frames[.blink] = loadSequence((0...3).map { "blink\($0)" })
        frames[.hop] = loadSequence((0...7).map { "hop\($0)" })
        frames[.groom] = loadSequence((0...6).map { "groom\($0)" })
        frames[.sleep] = loadSequence((0...1).map { "sleep\($0)" })
        frames[.roll] = loadSequence(["roll045", "roll090", "roll135", "roll180", "roll225", "roll270", "roll315", "normal"])
    }

    private func loadSequence(_ names: [String]) -> [NSImage] {
        names.compactMap { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "png") else {
                return nil
            }
            return NSImage(contentsOf: url)
        }
    }

    private func showMood(_ mood: PetMood) {
        currentMood = mood
        frameIndex = 0
        spriteLayer.contents = frames[mood]?.first ?? frames[.idle]?.first
    }

    func play(_ mood: PetMood, frameDuration: TimeInterval = 0.16, loops: Int = 1) {
        animationTimer?.invalidate()
        settleTimer?.invalidate()
        let sequence = frames[mood] ?? []
        guard !sequence.isEmpty else {
            showMood(.idle)
            return
        }

        currentMood = mood
        frameIndex = 0
        var remainingFrames = max(1, loops) * sequence.count
        animationTimer = Timer.scheduledTimer(withTimeInterval: frameDuration, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            self.spriteLayer.contents = sequence[self.frameIndex % sequence.count]
            self.frameIndex += 1
            remainingFrames -= 1
            if remainingFrames <= 0 {
                timer.invalidate()
                self.showMood(.idle)
            }
        }
    }

    func startSleepLoop() {
        animationTimer?.invalidate()
        showMood(.sleep)
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.72, repeats: true) { [weak self] _ in
            guard let self, let sequence = self.frames[.sleep], !sequence.isEmpty else { return }
            self.spriteLayer.contents = sequence[self.frameIndex % sequence.count]
            self.frameIndex += 1
        }
        settleTimer = Timer.scheduledTimer(withTimeInterval: 18, repeats: false) { [weak self] _ in
            self?.showMood(.idle)
        }
    }

    func startBreathing() {
        let breath = CABasicAnimation(keyPath: "transform.scale")
        breath.fromValue = 0.995
        breath.toValue = 1.025
        breath.duration = 2.2
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        spriteLayer.add(breath, forKey: "breath")

        let float = CABasicAnimation(keyPath: "position.y")
        float.byValue = bounds.height * 0.018
        float.duration = 2.2
        float.autoreverses = true
        float.repeatCount = .infinity
        float.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        spriteLayer.add(float, forKey: "float")

        let shadowPulse = CABasicAnimation(keyPath: "transform.scale.x")
        shadowPulse.fromValue = 0.92
        shadowPulse.toValue = 1.08
        shadowPulse.duration = 2.2
        shadowPulse.autoreverses = true
        shadowPulse.repeatCount = .infinity
        shadowPulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shadowLayer.add(shadowPulse, forKey: "shadowPulse")
    }

    func setMotionTilt(dx: CGFloat, dy: CGFloat) {
        let limitedX = max(-1.0, min(1.0, dx / 4.0))
        let limitedY = max(-1.0, min(1.0, dy / 4.0))
        var transform = CATransform3DIdentity
        transform.m34 = -1.0 / 650.0
        transform = CATransform3DRotate(transform, limitedX * 0.12, 0, 1, 0)
        transform = CATransform3DRotate(transform, -limitedY * 0.08, 1, 0, 0)
        transform = CATransform3DRotate(transform, -limitedX * 0.035, 0, 0, 1)

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        spriteLayer.transform = transform
        shadowLayer.opacity = Float(0.55 + min(0.22, abs(limitedX) * 0.16 + abs(limitedY) * 0.08))
        CATransaction.commit()
    }

    func bounce(_ strength: CGFloat = 1.0) {
        let squash = CAKeyframeAnimation(keyPath: "transform.scale")
        squash.values = [1.0, 1.08 + strength * 0.04, 0.94, 1.02, 1.0]
        squash.keyTimes = [0, 0.24, 0.48, 0.76, 1]
        squash.duration = 0.34
        squash.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        spriteLayer.add(squash, forKey: "bounce")
    }

    override func mouseDown(with event: NSEvent) {
        dragStartPoint = event.locationInWindow
        dragStartWindowOrigin = window?.frame.origin ?? .zero
        controller?.pauseMovement()
        play(.blink, frameDuration: 0.12, loops: 1)
        bounce(0.6)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let current = event.locationInWindow
        let dx = current.x - dragStartPoint.x
        let dy = current.y - dragStartPoint.y
        window.setFrameOrigin(NSPoint(x: dragStartWindowOrigin.x + dx, y: dragStartWindowOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        controller?.resumeMovementAfterInteraction()
        play(.hop, frameDuration: 0.12, loops: 1)
        bounce(1.0)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = controller?.makeMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc func clickReact() {
        play([PetMood.blink, .groom, .hop].randomElement() ?? .blink, frameDuration: 0.13, loops: 1)
        bounce(0.8)
        controller?.receiveClick()
        controller?.nudgeAwayFromMouse()
    }
}

final class JiujiuWindow: NSWindow {
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
    private(set) var window: JiujiuWindow!
    private(set) var catView: CatView!
    private let bubbleWindow = BubbleWindow()
    private var movementTimer: Timer?
    private var behaviorTimer: Timer?
    private var reminderTimer: Timer?
    private var decayTimer: Timer?
    private var focusTimer: Timer?
    private var velocity = CGVector(dx: 1.8, dy: 1.2)
    private var settings = PetSettings.load()
    private var stats = PetStats.load()
    private let baseSize = NSSize(width: 279, height: 340)

    func start() {
        let size = currentSize()
        window = JiujiuWindow(contentRect: NSRect(origin: initialOrigin(size: size), size: size))
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
        showBubble("啾啾来了，\(stats.moodLine)")
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
        menu.addItem(item("小一点", action: #selector(sizeSmall), checked: abs(settings.scale - 0.46) < 0.01))
        menu.addItem(item("标准大小", action: #selector(sizeNormal), checked: abs(settings.scale - 0.58) < 0.01))
        menu.addItem(item("大一点", action: #selector(sizeLarge), checked: abs(settings.scale - 0.72) < 0.01))
        menu.addItem(.separator())
        menu.addItem(item("慢悠悠", action: #selector(speedSlow), checked: settings.speed == 0.65))
        menu.addItem(item("正常速度", action: #selector(speedNormal), checked: settings.speed == 1.0))
        menu.addItem(item("精神一点", action: #selector(speedFast), checked: settings.speed == 1.45))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "打个滚", action: #selector(roll), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "梳毛", action: #selector(groom), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "睡一会儿", action: #selector(nap), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(item("置顶显示", action: #selector(toggleAlwaysOnTop), checked: settings.alwaysOnTop))
        menu.addItem(item("休息提醒", action: #selector(toggleReminders), checked: settings.remindersEnabled))
        menu.addItem(item("勿扰模式", action: #selector(toggleDoNotDisturb), checked: settings.doNotDisturb))
        menu.addItem(NSMenuItem(title: "开始 25 分钟专注", action: #selector(startFocus), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出啾啾", action: #selector(quit), keyEquivalent: "q"))
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
        return NSPoint(x: screen.maxX - size.width - 32, y: screen.minY + 36)
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
            if roll < 48 {
                self.catView.play(.blink, frameDuration: 0.11, loops: 1)
            } else if roll < 72 {
                self.catView.play(.groom, frameDuration: 0.16, loops: 1)
            } else if roll < 88 {
                self.catView.play(.hop, frameDuration: 0.12, loops: 1)
            } else {
                self.catView.startSleepLoop()
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
                self.showBubble("啾啾困了")
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
        frame.origin.x += velocity.dx * settings.speed * 0.55
        frame.origin.y += velocity.dy * settings.speed * 0.55

        if frame.minX < screen.minX || frame.maxX > screen.maxX {
            velocity.dx *= -1
            frame.origin.x = min(max(frame.origin.x, screen.minX), screen.maxX - frame.width)
            catView.play(.roll, frameDuration: 0.08, loops: 1)
        }
        if frame.minY < screen.minY || frame.maxY > screen.maxY {
            velocity.dy *= -1
            frame.origin.y = min(max(frame.origin.y, screen.minY), screen.maxY - frame.height)
            catView.play(.hop, frameDuration: 0.11, loops: 1)
        }

        if Int.random(in: 0..<260) == 0 {
            velocity.dx = CGFloat.random(in: -2.2...2.2)
            velocity.dy = CGFloat.random(in: -1.8...1.8)
        }
        catView.setMotionTilt(dx: velocity.dx, dy: velocity.dy)
        window.setFrameOrigin(frame.origin)
    }

    private func followMouse(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let frame = window.frame
        let target = NSPoint(x: mouse.x - frame.width / 2, y: mouse.y - frame.height / 2)
        catView.setMotionTilt(dx: target.x - frame.origin.x, dy: target.y - frame.origin.y)
        move(window, toward: target, easing: 0.045 * settings.speed)
    }

    private func moveTowardCorner(_ window: NSWindow) {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let target = NSPoint(x: screen.maxX - window.frame.width - 28, y: screen.minY + 28)
        catView.setMotionTilt(dx: target.x - window.frame.origin.x, dy: target.y - window.frame.origin.y)
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
        startMovement()
    }

    func nudgeAwayFromMouse() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        velocity = CGVector(dx: center.x >= mouse.x ? 2.4 : -2.4, dy: center.y >= mouse.y ? 1.8 : -1.8)
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
        content.title = "啾啾"
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: "jiujiu-break-\(Date().timeIntervalSince1970)",
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
        settings.scale = 0.46
        applySettings()
        showBubble("变小一点")
    }

    @objc private func sizeNormal() {
        settings.scale = 0.58
        applySettings()
        showBubble("标准大小")
    }

    @objc private func sizeLarge() {
        settings.scale = 0.72
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
        let origin = NSPoint(x: mouse.x - window.frame.width / 2, y: mouse.y - window.frame.height / 2)
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
