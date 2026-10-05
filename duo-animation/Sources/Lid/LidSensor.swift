import Foundation
import IOKit.hid
import QuartzCore

// All HID handles live on this actor. No device writes, exclusive access,
// keyboard matching, private frameworks or privileged helper are used.
actor LidSensor {
    struct Reading: Sendable { let angle: Double; let time: Double }
    enum Connection: Sendable {
        case ready(Reading)
        case unavailable(String)
    }

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var session: UUID?
    private let options = IOOptionBits(kIOHIDOptionsTypeNone)

    func connect(session token: UUID) -> Connection {
        closeHandles()
        session = token
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, options)
        // Match first, then open, so unrelated input devices are never opened.
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x05AC,
            kIOHIDProductIDKey as String: 0x8104,
            kIOHIDPrimaryUsagePageKey as String: 0x0020,
            kIOHIDPrimaryUsageKey as String: 0x008A,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard IOHIDManagerOpen(manager, options) == kIOReturnSuccess else {
            return .unavailable("The lid sensor could not be opened. The sample preview still works.")
        }
        self.manager = manager
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            closeHandles()
            return .unavailable("No readable lid sensor on this Mac. You can still use the preview.")
        }
        for candidate in devices {
            guard IOHIDDeviceOpen(candidate, options) == kIOReturnSuccess else { continue }
            if let reading = read(candidate) {
                device = candidate
                return .ready(reading)
            }
            IOHIDDeviceClose(candidate, options)
        }
        closeHandles()
        return .unavailable("No readable lid sensor on this Mac. You can still use the preview.")
    }

    func reading(session token: UUID) -> Reading? {
        guard session == token, let device else { return nil }
        return read(device)
    }

    func disconnect(session token: UUID) {
        guard session == token else { return }
        closeHandles()
        session = nil
    }

    private func read(_ device: IOHIDDevice) -> Reading? {
        var bytes = [UInt8](repeating: 0, count: 8)
        var length = CFIndex(bytes.count)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &bytes, &length)
        guard result == kIOReturnSuccess,
              let angle = LidReport.angle(bytes: bytes, length: length) else { return nil }
        return Reading(angle: angle, time: CACurrentMediaTime())
    }

    private func closeHandles() {
        if let device { IOHIDDeviceClose(device, options) }
        device = nil
        if let manager { IOHIDManagerClose(manager, options) }
        manager = nil
    }
}
