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

    var mode: PetMode
    var scale: CGFloat
    var speed: CGFloat

    static func load() -> PetSettings {
        let defaults = UserDefaults.standard
        let mode = PetMode(rawValue: defaults.string(forKey: modeKey) ?? "") ?? .roam
        let scaleValue = defaults.object(forKey: scaleKey) as? Double ?? 0.82
        let speedValue = defaults.object(forKey: speedKey) as? Double ?? 1.0
        return PetSettings(mode: mode, scale: CGFloat(scaleValue), speed: CGFloat(speedValue))
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(mode.rawValue, forKey: PetSettings.modeKey)
        defaults.set(Double(scale), forKey: PetSettings.scaleKey)
        defaults.set(Double(speed), forKey: PetSettings.speedKey)
    }
}

final class CatView: NSView {
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
        layer?.contentsGravity = .resizeAspect
        layer?.minificationFilter = .nearest
        layer?.magnificationFilter = .nearest
        loadFrames()
        showMood(.idle)
        startBreathing()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        layer?.contents = frames[mood]?.first ?? frames[.idle]?.first
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

            self.layer?.contents = sequence[self.frameIndex % sequence.count]
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
            self.layer?.contents = sequence[self.frameIndex % sequence.count]
            self.frameIndex += 1
        }
        settleTimer = Timer.scheduledTimer(withTimeInterval: 18, repeats: false) { [weak self] _ in
            self?.showMood(.idle)
        }
    }

    func startBreathing() {
        let breath = CABasicAnimation(keyPath: "transform.scale")
        breath.fromValue = 1.0
        breath.toValue = 1.025
        breath.duration = 2.4
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(breath, forKey: "breath")
    }

    override func mouseDown(with event: NSEvent) {
        dragStartPoint = event.locationInWindow
        dragStartWindowOrigin = window?.frame.origin ?? .zero
        controller?.pauseMovement()
        play(.blink, frameDuration: 0.12, loops: 1)
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
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = controller?.makeMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc func clickReact() {
        play([PetMood.blink, .groom, .hop].randomElement() ?? .blink, frameDuration: 0.13, loops: 1)
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

final class PetController: NSObject {
    private(set) var window: JiujiuWindow!
    private(set) var catView: CatView!
    private var movementTimer: Timer?
    private var behaviorTimer: Timer?
    private var reminderTimer: Timer?
    private var velocity = CGVector(dx: 1.8, dy: 1.2)
    private var settings = PetSettings.load()
    private let baseSize = NSSize(width: 512, height: 528)

    func start() {
        let size = currentSize()
        window = JiujiuWindow(contentRect: NSRect(origin: initialOrigin(size: size), size: size))
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
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("自由游走", action: #selector(setRoam), checked: settings.mode == .roam))
        menu.addItem(item("跟随鼠标", action: #selector(setFollow), checked: settings.mode == .follow))
        menu.addItem(item("角落休息", action: #selector(setCorner), checked: settings.mode == .corner))
        menu.addItem(.separator())
        menu.addItem(item("小一点", action: #selector(sizeSmall), checked: settings.scale == 0.68))
        menu.addItem(item("标准大小", action: #selector(sizeNormal), checked: settings.scale == 0.82))
        menu.addItem(item("大一点", action: #selector(sizeLarge), checked: settings.scale == 1.0))
        menu.addItem(.separator())
        menu.addItem(item("慢悠悠", action: #selector(speedSlow), checked: settings.speed == 0.65))
        menu.addItem(item("正常速度", action: #selector(speedNormal), checked: settings.speed == 1.0))
        menu.addItem(item("精神一点", action: #selector(speedFast), checked: settings.speed == 1.45))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "打个滚", action: #selector(roll), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "梳毛", action: #selector(groom), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "睡一会儿", action: #selector(nap), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出啾啾", action: #selector(quit), keyEquivalent: "q"))
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
        movementTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
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
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 45 * 60, repeats: true) { [weak self] _ in
            self?.showReminder("休息一下，喝口水")
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
        frame.origin.x += velocity.dx * settings.speed
        frame.origin.y += velocity.dy * settings.speed

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
        window.setFrameOrigin(frame.origin)
    }

    private func followMouse(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let frame = window.frame
        let target = NSPoint(x: mouse.x - frame.width / 2, y: mouse.y - frame.height / 2)
        move(window, toward: target, easing: 0.045 * settings.speed)
    }

    private func moveTowardCorner(_ window: NSWindow) {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let target = NSPoint(x: screen.maxX - window.frame.width - 28, y: screen.minY + 28)
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

    private func showReminder(_ message: String) {
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
    }

    @objc private func setFollow() {
        settings.mode = .follow
        applySettings()
    }

    @objc private func setCorner() {
        settings.mode = .corner
        applySettings()
    }

    @objc private func sizeSmall() {
        settings.scale = 0.68
        applySettings()
    }

    @objc private func sizeNormal() {
        settings.scale = 0.82
        applySettings()
    }

    @objc private func sizeLarge() {
        settings.scale = 1.0
        applySettings()
    }

    @objc private func speedSlow() {
        settings.speed = 0.65
        applySettings()
    }

    @objc private func speedNormal() {
        settings.speed = 1.0
        applySettings()
    }

    @objc private func speedFast() {
        settings.speed = 1.45
        applySettings()
    }

    @objc private func roll() {
        catView.play(.roll, frameDuration: 0.08, loops: 1)
    }

    @objc private func groom() {
        catView.play(.groom, frameDuration: 0.15, loops: 2)
    }

    @objc private func nap() {
        catView.startSleepLoop()
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
