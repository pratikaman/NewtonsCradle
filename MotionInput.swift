import Cocoa
import CoreMotion
import GameController
import IOKit
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
    private var headphoneSample: CMDeviceMotion?
    private var hidDevices: [IOHIDDevice] = []
    private var hidBuffers: [UnsafeMutablePointer<UInt8>] = []
    private var hidAccel: (x: Double, y: Double, z: Double)?
    private var hidHaveSample = false
    private var hidReports: UInt64 = 0
    private var hidSkip = 0
    private var lastStatusWrite: CFTimeInterval = 0

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
        for hid in hidDevices {
            IOHIDDeviceUnscheduleFromRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(hid, 0)
        }
        hidDevices.removeAll()
        hidBuffers.forEach { $0.deallocate() }
        hidBuffers.removeAll()
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
            if hidHaveSample { effective = .accelerometer }
            else if controllerAvailable { effective = .accelerometer }
            else if headphoneSample != nil { effective = .headphones }
            else { effective = .mouse }
        default:
            effective = mode
        }

        switch effective {
        case .accelerometer:
            if applyHIDAccel(sensitivity: s) {
                break
            } else if applyController(sensitivity: s) {
                break
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

        let now = CACurrentMediaTime()
        if now - lastStatusWrite > 1.0 {
            lastStatusWrite = now
            writeStatus()
        }
    }

    private func applyHIDAccel(sensitivity s: Double) -> Bool {
        guard let a = hidAccel, hidHaveSample else { return false }
        let tilt = atan2(a.x, max(0.15, abs(a.z)))
        gravityX = sin(tilt) * s
        gravityY = -cos(tilt)
        if haveLastAccel {
            let jerk = a.x - lastAccelX
            if abs(jerk) > 0.045 {
                jerkImpulse = jerk * 4.5 * s
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

    // MARK: - Apple SPU accelerometer (AppleSPUHIDDevice, usage 0xFF00/3)

    private func startHIDAccelerometer() {
        wakeSPUDrivers()
        attachAccelDevice()
    }

    private func wakeSPUDrivers() {
        guard let matching = IOServiceMatching("AppleSPUHIDDriver") else { return }
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &it) == KERN_SUCCESS else { return }
        while true {
            let svc = IOIteratorNext(it)
            if svc == 0 { break }
            for (k, v) in [
                ("SensorPropertyReportingState", Int32(1)),
                ("SensorPropertyPowerState", Int32(1)),
                ("ReportInterval", Int32(1000))
            ] {
                IORegistryEntrySetCFProperty(svc, k as CFString, v as CFNumber)
            }
            IOObjectRelease(svc)
        }
        IOObjectRelease(it)
    }

    private func attachAccelDevice() {
        guard let matching = IOServiceMatching("AppleSPUHIDDevice") else { return }
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &it) == KERN_SUCCESS else { return }
        while true {
            let svc = IOIteratorNext(it)
            if svc == 0 { break }
            let up = hidPropUInt32(svc, "PrimaryUsagePage")
            let u = hidPropUInt32(svc, "PrimaryUsage")
            if up == 0xFF00 && u == 3, let hid = IOHIDDeviceCreate(kCFAllocatorDefault, svc) {
                if IOHIDDeviceOpen(hid, 0) == kIOReturnSuccess {
                    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                    buf.initialize(repeating: 0, count: 4096)
                    hidBuffers.append(buf)
                    hidDevices.append(hid)
                    accelerometerAvailable = true
                    let ctx = Unmanaged.passUnretained(self).toOpaque()
                    IOHIDDeviceRegisterInputReportWithTimeStampCallback(hid, buf, 4096, { context, _, _, _, _, report, len, _ in
                        Unmanaged<MotionHub>.fromOpaque(context!).takeUnretainedValue()
                            .handleAccelReport(report, length: Int(len))
                    }, ctx)
                    IOHIDDeviceScheduleWithRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
                }
            }
            IOObjectRelease(svc)
        }
        IOObjectRelease(it)
    }

    private func hidPropUInt32(_ svc: io_object_t, _ key: String) -> UInt32 {
        guard let unmanaged = IORegistryEntryCreateCFProperty(svc, key as CFString, kCFAllocatorDefault, 0) else { return 0 }
        let value = unmanaged.takeRetainedValue()
        return (value as? NSNumber)?.uint32Value ?? 0
    }

    /// 22-byte BMI286 report: int32le xyz at bytes 6,10,14; divide by 65536 → g.
    private func handleAccelReport(_ report: UnsafePointer<UInt8>, length: Int) {
        guard length >= 22 else { return }
        hidSkip += 1
        if hidSkip < 8 { return }
        hidSkip = 0
        hidReports &+= 1
        func i32(_ o: Int) -> Int32 {
            Int32(bitPattern:
                UInt32(report[o]) |
                UInt32(report[o + 1]) << 8 |
                UInt32(report[o + 2]) << 16 |
                UInt32(report[o + 3]) << 24)
        }
        hidAccel = (
            Double(i32(6)) / 65536.0,
            Double(i32(10)) / 65536.0,
            Double(i32(14)) / 65536.0
        )
        hidHaveSample = true
    }

    func writeStatus() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NewtonsCradle")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var payload: [String: Any] = [
            "accelerometerAvailable": accelerometerAvailable,
            "hidStreaming": hidHaveSample,
            "hidReports": hidReports,
            "headphonesAvailable": headphonesAvailable,
            "controllerAvailable": controllerAvailable,
            "source": sourceName,
            "mode": mode.rawValue,
            "paused": paused,
            "autoDemo": autoDemo,
            "sensitivity": sensitivity,
            "gravityX": gravityX,
            "gravityY": gravityY
        ]
        if let a = hidAccel {
            payload["gX"] = a.x
            payload["gY"] = a.y
            payload["gZ"] = a.z
        }
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
            try? data.write(to: dir.appendingPathComponent("status.json"))
        }
    }
}
