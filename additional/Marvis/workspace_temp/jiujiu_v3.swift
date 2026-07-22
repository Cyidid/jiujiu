import Cocoa

class CatView: NSView {
    var image: NSImage!
    var startPoint: NSPoint = .zero
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        self.wantsLayer = true
        self.layer?.contentsGravity = .resizeAspect  // 不缩放保持原始比例
        
        if let path = Bundle.main.path(forResource: "jiujiu_cat", ofType: "png") {
            image = NSImage(contentsOfFile: path)
        } else {
            image = NSImage(contentsOfFile: "/Users/cydid/啾啾/jiujiu_cat.png")
        }
        
        // 禁用插值 → 像素风保持锐利
        self.layer?.minificationFilter = .nearest
        self.layer?.magnificationFilter = .nearest
        self.layer?.contents = image
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    // 手动实现拖拽
    override func mouseDown(with event: NSEvent) {
        startPoint = event.locationInWindow
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window else { return }
        let current = event.locationInWindow
        let dx = current.x - startPoint.x
        let dy = current.y - startPoint.y
        var origin = window.frame.origin
        origin.x += dx
        origin.y += dy
        window.setFrameOrigin(origin)
    }
    
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "退出啾啾", action: #selector(quit), keyEquivalent: ""))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    
    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    // 呼吸动画
    func startBreathing() {
        let breath = CABasicAnimation(keyPath: "transform.scale")
        breath.fromValue = 1.0
        breath.toValue = 1.03
        breath.duration = 2.5
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        self.layer?.add(breath, forKey: "breath")
    }
    
    // 点击歪头
    @objc func tiltHead() {
        let tilt = CABasicAnimation(keyPath: "transform.rotation.z")
        tilt.fromValue = 0
        tilt.toValue = -0.08
        tilt.duration = 0.12
        tilt.autoreverses = true
        tilt.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        self.layer?.add(tilt, forKey: "tilt")
    }
}

class JiujiuWindow: NSWindow {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.isMovable = false  // 禁用系统拖动，用自定义
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: JiujiuWindow!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 窗口大小 = 图片大小 (保持 1:1 像素精确)
        let catSize = NSSize(width: 512, height: 528)
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let origin = NSPoint(
            x: screen.maxX - catSize.width - 40,
            y: screen.minY + 60
        )
        
        window = JiujiuWindow(contentRect: NSRect(origin: origin, size: catSize),
                              styleMask: [.borderless, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        
        let catView = CatView(frame: NSRect(origin: .zero, size: catSize))
        window.contentView = catView
        
        // 双击退出
        let dbl = NSClickGestureRecognizer(target: catView, action: #selector(CatView.quit))
        dbl.numberOfClicksRequired = 2
        catView.addGestureRecognizer(dbl)
        
        // 单击歪头
        let sgl = NSClickGestureRecognizer(target: catView, action: #selector(CatView.tiltHead))
        sgl.numberOfClicksRequired = 1
        sgl.delaysPrimaryMouseButtonEvents = false
        catView.addGestureRecognizer(sgl)
        
        window.makeKeyAndOrderFront(nil)
        catView.startBreathing()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()