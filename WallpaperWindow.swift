import Cocoa

final class WallpaperWindow: NSWindow {
    convenience init(screen: NSScreen) {
        self.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: true)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = true
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        isRestorable = false
        animationBehavior = .none
        backgroundColor = NSColor(calibratedRed: 0.075, green: 0.045, blue: 0.028, alpha: 1)
        hidesOnDeactivate = false
        contentView = CradleView(frame: NSRect(origin: .zero, size: screen.frame.size))
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
