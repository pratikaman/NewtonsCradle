import Cocoa
import CoreMotion
import GameController
import IOKit.hid

enum InputMode: String {
    case auto
    case accelerometer
    case headphones
    case mouse
}

final class MotionHub {
    static let shared = MotionHub()

    private let headphones = CMHeadphoneMotionManager()
    private var hidManager: IOHIDManager?
    private var hidBuffers: [UnsafeMutablePointer<UInt8>] = []
    private var headphoneSample: CMDeviceMotion?
    private var hidAccel: (x: Double, y: Double, z: Double)?
    private var hidHaveSample = false

    private(set) var gravityX: Double = 0
    private(set) var gravityY: Double = -1
    private(set) var jerkImpulse: Double = 0
    private(set) var sourceName: String = "Mouse tilt"
    private(set) var accelerometerAvailable = false
    private(set) var headphonesAvailable = false
    private(set) var controllerAvailable = false

    private(set) var pullSeq: UInt64 = 0
    private(set) var pullPayload: (side: CradleSide, count: Int)?

    var paused: Bool {
        didSet { UserDefaults.standard.set(paused, forKey: "paused") }
    }
    var autoDemo: Bool {
        didSet { UserDefaults.standard.set(autoDemo, forKey: "autoDemo") }
    }
    var mode: InputMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "inputMode") }
    }
    var sensitivity: Double {
        didSet { UserDefaults.standard.set(sensitivity, forKey: "sensitivity") }
    }

    private var lastAccelX: Double = 0
    private var haveLastAccel = false
    private var lastMouseX: Double = 0
    private var haveLastMouse = false

    private init() {
        let d = UserDefaults.standard
        paused = d.bool(forKey: "paused")
        autoDemo = d.object(forKey: "autoDemo") as? Bool ?? true
        sensitivity = d.object(forKey: "sensitivity") as? Double ?? 1.0
        mode = InputMode(rawValue: d.string(forKey: "inputMode") ?? "auto") ?? .auto
    }

    func start() {
        headphonesAvailable = headphones.isDeviceMotionAvailable
        if headphonesAvailable {
            headphones.startDeviceMotionUpdates(to: OperationQueue.main) { [weak self] data, _ in
                self?.headphoneSample = data
            }
        }

        startHIDAccelerometer()
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main
        ) { [weak self] _ in
            self?.controllerAvailable = !GCController.controllers().compactMap({ $0.motion }).isEmpty
        }
        controllerAvailable = !GCController.controllers().compactMap({ $0.motion }).isEmpty
        writeStatus()
    }

    func stop() {
        if headphones.isDeviceMotionAvailable {
            headphones.stopDeviceMotionUpdates()
        }
        if let manager = hidManager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        hidManager = nil
    }

    func queuePull(side: CradleSide, count: Int) {
        pullPayload = (side, count)
        pullSeq &+= 1
    }

    var hasMacIMU: Bool {
        hidHaveSample || controllerAvailable
    }

    func sample() {
        jerkImpulse = 0
        let s = max(0.25, min(2.5, sensitivity))
        controllerAvailable = !GCController.controllers().compactMap({ $0.motion }).isEmpty

        let effective: InputMode
        switch mode {
        case .auto:
            if hidHaveSample || controllerAvailable { effective = .accelerometer }
            else if headphoneSample != nil { effective = .headphones }
            else { effective = .mouse }
        default:
            effective = mode
        }

        switch effective {
        case .accelerometer:
            if applyHIDAccel(sensitivity: s) {
                // ok
            } else if applyController(sensitivity: s) {
                // ok
            } else {
                applyMouseTilt(sensitivity: s)
                sourceName = "Mouse tilt (no Mac IMU stream)"
            }
        case .headphones:
            if !applyHeadphones(sensitivity: s) {
                applyMouseTilt(sensitivity: s)
                sourceName = "Mouse tilt (no AirPods IMU)"
            }
        case .mouse, .auto:
            applyMouseTilt(sensitivity: s)
            sourceName = "Mouse tilt"
        }
    }

    private func applyHIDAccel(sensitivity s: Double) -> Bool {
        guard let a = hidAccel, hidHaveSample else { return false }
        let tilt = atan2(a.x, max(0.15, abs(a.z) + abs(a.y)))
        gravityX = sin(tilt) * s
        gravityY = -cos(tilt)
        if haveLastAccel {
            let jerk = a.x - lastAccelX
            if abs(jerk) > 0.06 {
                jerkImpulse = jerk * 2.8 * s
            }
        }
        lastAccelX = a.x
        haveLastAccel = true
        sourceName = "Mac accelerometer"
        return true
    }

    private func applyController(sensitivity s: Double) -> Bool {
        guard let motion = GCController.controllers().compactMap({ $0.motion }).first else { return false }
        let g = motion.gravity
        let tilt = atan2(g.x, max(0.15, abs(g.z) + abs(g.y)))
        gravityX = sin(tilt) * s
        gravityY = -cos(tilt)
        let ax = motion.userAcceleration.x
        if haveLastAccel {
            let jerk = ax - lastAccelX
            if abs(jerk) > 0.05 {
                jerkImpulse = jerk * 3.0 * s
            }
        }
        lastAccelX = ax
        haveLastAccel = true
        sourceName = "Game controller IMU"
        return true
    }

    private func applyHeadphones(sensitivity s: Double) -> Bool {
        guard let dm = headphoneSample else { return false }
        let tilt = atan2(dm.gravity.x, max(0.15, abs(dm.gravity.z)))
        gravityX = sin(tilt) * s
        gravityY = -cos(tilt)
        let ax = dm.userAcceleration.x
        if haveLastAccel {
            let jerk = ax - lastAccelX
            if abs(jerk) > 0.05 {
                jerkImpulse = jerk * 3.0 * s
            }
        }
        lastAccelX = ax
        haveLastAccel = true
        sourceName = "AirPods motion"
        return true
    }

    private func applyMouseTilt(sensitivity s: Double) {
        let loc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(loc, $0.frame, false) }) ?? NSScreen.main
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let u = (loc.x - frame.minX) / max(frame.width, 1)
        let tilt = (u - 0.5) * 0.62 * s
        gravityX = sin(tilt)
        gravityY = -cos(tilt)
        if haveLastMouse {
            let dx = loc.x - lastMouseX
            if abs(dx) > 70 {
                jerkImpulse = (dx / 400) * s
            }
        }
        lastMouseX = loc.x
        haveLastMouse = true
    }

    // MARK: - Built-in AOP accelerometer (HID product "accel")

    private func startHIDAccelerometer() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = manager
        let match: [String: Any] = [kIOHIDProductKey as String: "accel"]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            Unmanaged<MotionHub>.fromOpaque(context!).takeUnretainedValue().attachAccel(device)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        _ = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        accelerometerAvailable = true
    }

    private func attachAccel(_ device: IOHIDDevice) {
        let name = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? ""
        guard name == "accel" else { return }
        let open = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard open == kIOReturnSuccess else { return }
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 32)
        buf.initialize(repeating: 0, count: 32)
        hidBuffers.append(buf)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buf, 32, { context, _, _, _, _, report, len in
            Unmanaged<MotionHub>.fromOpaque(context!).takeUnretainedValue().handleAccelReport(report, length: Int(len))
        }, ctx)
    }

    /// Apple SPU accel HID report is a 22-byte vendor blob. When the OS
    /// actually streams it, try int16le triplets at a few offsets.
    private func handleAccelReport(_ report: UnsafePointer<UInt8>, length: Int) {
        guard length >= 6 else { return }
        func i16(_ o: Int) -> Double {
            guard o + 1 < length else { return 0 }
            let lo = Int16(bitPattern: UInt16(report[o]) | (UInt16(report[o + 1]) << 8))
            return Double(lo)
        }
        // Prefer a 6-byte xyz packed after an 8-byte timestamp, else at offset 0.
        var samples = [(i16(8), i16(10), i16(12)), (i16(0), i16(2), i16(4))]
        if length >= 22 {
            samples.append((i16(16), i16(18), i16(20)))
        }
        let picked = samples.max(by: { hypot($0.0, hypot($0.1, $0.2)) < hypot($1.0, hypot($1.1, $1.2)) })!
        let mag = hypot(picked.0, hypot(picked.1, picked.2))
        guard mag > 20 else { return }
        hidAccel = (picked.0 / mag, picked.1 / mag, picked.2 / mag)
        hidHaveSample = true
    }

    func writeStatus() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NewtonsCradle")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload: [String: Any] = [
            "accelerometerAvailable": accelerometerAvailable,
            "hidStreaming": hidHaveSample,
            "headphonesAvailable": headphonesAvailable,
            "controllerAvailable": controllerAvailable,
            "source": sourceName,
            "mode": mode.rawValue,
            "paused": paused,
            "autoDemo": autoDemo,
            "sensitivity": sensitivity
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
            try? data.write(to: dir.appendingPathComponent("status.json"))
        }
    }
}
