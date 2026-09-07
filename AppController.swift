import Cocoa

final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var walls: [WallpaperWindow] = []
    private var clock: Timer?
    private var lastTime: CFTimeInterval = 0
    private var sourceItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let id = Bundle.main.bundleIdentifier ?? "com.pratikaman.newtonscradle"
        if NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }

        MotionHub.shared.start()
        setupStatusItem()
        rebuildWalls()
        startClock()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        clock?.invalidate()
        MotionHub.shared.stop()
        walls.forEach { $0.close() }
    }

    private func startClock() {
        lastTime = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        clock = t
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTime, 0.05)
        lastTime = now
        MotionHub.shared.sample()
        for w in walls {
            (w.contentView as? CradleView)?.tick(dt: dt)
        }
    }

    @objc private func screensChanged() {
        rebuildWalls()
    }

    private func rebuildWalls() {
        walls.forEach { $0.close() }
        walls = NSScreen.screens.map { WallpaperWindow(screen: $0) }
        for (i, screen) in NSScreen.screens.enumerated() {
            walls[i].setFrame(screen.frame, display: true)
            walls[i].contentView?.frame = NSRect(origin: .zero, size: screen.frame.size)
            walls[i].orderFrontRegardless()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = statusIcon()
            button.toolTip = "Newton's Cradle"
        }
        let menu = NSMenu()
        menu.delegate = self

        let title = NSMenuItem(title: "Newton's Cradle", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let src = NSMenuItem(title: "Input: …", action: nil, keyEquivalent: "")
        src.isEnabled = false
        menu.addItem(src)
        sourceItem = src

        menu.addItem(.separator())

        let pause = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        pause.tag = 10
        menu.addItem(pause)

        let demo = NSMenuItem(title: "Auto Demo", action: #selector(toggleDemo), keyEquivalent: "")
        demo.target = self
        demo.tag = 11
        menu.addItem(demo)

        menu.addItem(.separator())

        let input = NSMenu()
        input.addItem(modeItem("Auto", mode: .auto))
        input.addItem(modeItem("Mac accelerometer / controller", mode: .accelerometer))
        input.addItem(modeItem("AirPods motion", mode: .headphones))
        input.addItem(modeItem("Mouse tilt", mode: .mouse))
        let inputParent = NSMenuItem(title: "Input Source", action: nil, keyEquivalent: "")
        inputParent.submenu = input
        menu.addItem(inputParent)

        let sens = NSMenu()
        sens.addItem(sensItem("Low", value: 0.55))
        sens.addItem(sensItem("Medium", value: 1.0))
        sens.addItem(sensItem("High", value: 1.75))
        let sensParent = NSMenuItem(title: "Sensitivity", action: nil, keyEquivalent: "")
        sensParent.submenu = sens
        menu.addItem(sensParent)

        menu.addItem(.separator())
        let nl = NSMenuItem(title: "Nudge Left", action: #selector(nudgeLeft), keyEquivalent: "")
        nl.target = self
        menu.addItem(nl)
        let nr = NSMenuItem(title: "Nudge Right", action: #selector(nudgeRight), keyEquivalent: "")
        nr.target = self
        menu.addItem(nr)
        let n2 = NSMenuItem(title: "Drop Two Balls", action: #selector(nudgeTwo), keyEquivalent: "")
        n2.target = self
        menu.addItem(n2)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Newton's Cradle", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func modeItem(_ title: String, mode: InputMode) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(setMode(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = mode.rawValue
        return item
    }

    private func sensItem(_ title: String, value: Double) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(setSens(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = value
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let hub = MotionHub.shared
        sourceItem?.title = "Input: \(hub.sourceName)"
        for item in menu.items {
            if item.tag == 10 {
                item.title = hub.paused ? "Resume" : "Pause"
                item.state = hub.paused ? .on : .off
            }
            if item.tag == 11 {
                item.state = hub.autoDemo ? .on : .off
            }
        }
        if let input = menu.items.first(where: { $0.title == "Input Source" })?.submenu {
            for item in input.items {
                let raw = item.representedObject as? String
                item.state = (raw == hub.mode.rawValue) ? .on : .off
            }
        }
        if let sens = menu.items.first(where: { $0.title == "Sensitivity" })?.submenu {
            for item in sens.items {
                let v = item.representedObject as? Double ?? -1
                item.state = abs(v - hub.sensitivity) < 0.01 ? .on : .off
            }
        }
        hub.writeStatus()
    }

    @objc private func togglePause() {
        MotionHub.shared.paused.toggle()
    }

    @objc private func toggleDemo() {
        MotionHub.shared.autoDemo.toggle()
    }

    @objc private func setMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = InputMode(rawValue: raw) {
            MotionHub.shared.mode = mode
        }
    }

    @objc private func setSens(_ sender: NSMenuItem) {
        if let v = sender.representedObject as? Double {
            MotionHub.shared.sensitivity = v
        }
    }

    @objc private func nudgeLeft() {
        MotionHub.shared.queuePull(side: .left, count: 1)
    }

    @objc private func nudgeRight() {
        MotionHub.shared.queuePull(side: .right, count: 1)
    }

    @objc private func nudgeTwo() {
        MotionHub.shared.queuePull(side: .left, count: 2)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func statusIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.labelColor.setFill()
        let r: CGFloat = 2.1
        let y: CGFloat = 6.2
        for i in 0..<5 {
            let x = 1.6 + CGFloat(i) * 3.15
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: r * 2, height: r * 2)).fill()
        }
        img.unlockFocus()
        img.isTemplate = true
        return img
    }
}
