import AppKit
import QuartzCore
import ServiceManagement

@MainActor
final class AppController: NSObject, NSMenuDelegate {
    private let renderer: GlassRenderer
    private let preview: PreviewWindow
    private let sensor = LidSensor()
    private var hotKey: PauseHotKey?
    private var statusItem: NSStatusItem?
    private var effectMenuItem: NSMenuItem?
    private var statusMenuItem: NSMenuItem?
    private var loginMenuItem: NSMenuItem?
    private var loginApprovalItem: NSMenuItem?
    private let defaults = UserDefaults.standard
    private static let requestedKey = "DuoLid.desktopEffectRequested"
    private static let setupKey = "DuoLid.didShowSetup"
    private static let triggerKey = "DuoLid.triggerAngle"
    private var background = BackgroundState()
    private var nextResumeTime = 0.0
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var sensorTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var sensorSession: UUID?
    private var captureGeneration = UUID()
    private var maintenanceTimer: Timer?
    private var demoPlaying = false
    private var demoStarted = 0.0
    private var lastReading: LidSensor.Reading?
    private var lastHealthyTime = 0.0
    private var lastLabelTime = 0.0
    private var filteredAngle = 120.0
    private var angleFilter = AngleFilter()
    private var gesture = GestureTracker()
    private var trigger: LidTrigger { gesture.trigger }
    private var effect = EffectState()
    private var connected = false
    private var enabled = false
    private var activeSince: Double?
    private var overlay: OverlayWindow?
    private var overlayRenderer: GlassRenderer?
    private var captureReady = false
    private var showingDesktop = false
    private var shuttingDown = false

    init(renderer: GlassRenderer) throws {
        self.renderer = renderer
        try renderer.prepare(SampleDesktop.make())
        preview = PreviewWindow(renderer: renderer)
        super.init()
        let savedTrigger = defaults.object(forKey: Self.triggerKey) == nil
            ? LidTrigger() : LidTrigger(angle: defaults.double(forKey: Self.triggerKey))
        gesture.configure(trigger: savedTrigger)
        effect.referenceAngle = Float(trigger.angle)
        effect.angle = Float(max(120, trigger.approachUpperAngle))
        preview.setTriggerAngle(trigger)
        background.requested = defaults.bool(forKey: Self.requestedKey)
        if defaults.object(forKey: "DuoLid.depth") != nil {
            effect.perspective = min(1, max(0, defaults.float(forKey: "DuoLid.depth")))
            effect.softness = min(1.4, max(0, defaults.float(forKey: "DuoLid.softness")))
            effect.shade = min(1, max(0, defaults.float(forKey: "DuoLid.shade")))
        }
        preview.setAppearance(depth: effect.perspective, softness: effect.softness, shade: effect.shade)
        updatePreview()
        preview.glass.onFrame = { [weak self] in self?.presentationState(previewing: true) ?? EffectState() }
        wireControls()
        makeMenu()
        hotKey = PauseHotKey { [weak self] in self?.pauseEffect("Paused. Your desktop is back to normal.", clearRequest: true) }
        observeSession()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.maintainSafety() }
        }
        RunLoop.main.add(timer, forMode: .common)
        maintenanceTimer = timer
    }

    func start() {
        if !defaults.bool(forKey: Self.setupKey) { showWindow() }
        refreshMenu()
        resumeIfPossible()
    }

    func showWindow() {
        defaults.set(true, forKey: Self.setupKey)
        preview.showWindow(nil)
        preview.window?.deminiaturize(nil)
        preview.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        updateDrawingActivity()
    }

    private func wireControls() {
        preview.onAngle = { [weak self] angle in
            guard let self else { return }
            self.stopDemo()
            self.effect.angle = Float(angle)
            self.effect.referenceAngle = Float(self.trigger.angle)
            self.updatePreview()
        }
        preview.onAppearance = { [weak self] depth, softness, shade in
            guard let self else { return }
            self.effect.perspective = depth
            self.effect.softness = softness
            self.effect.shade = shade
            self.defaults.set(depth, forKey: "DuoLid.depth")
            self.defaults.set(softness, forKey: "DuoLid.softness")
            self.defaults.set(shade, forKey: "DuoLid.shade")
            self.updatePreview()
            self.updateOverlay()
        }
        preview.onTrigger = { [weak self] value in self?.changeTrigger(value) }
        preview.onPlay = { [weak self] in self?.toggleDemo() }
        preview.onDesktop = { [weak self] in self?.previewDesktop() }
        preview.onSample = { [weak self] in self?.useSample() }
        preview.onSensor = { [weak self] in self?.toggleSensor() }
        preview.onEnable = { [weak self] value in
            if value { self?.requestEnable() } else { self?.pauseEffect("Desktop effect is off.", clearRequest: true) }
        }
        preview.onPause = { [weak self] in self?.pauseEffect("Paused. Your desktop is back to normal.", clearRequest: true) }
        preview.onHide = { [weak self] in self?.stopDemo() }
    }

    private func changeTrigger(_ angle: Double) {
        let value = LidTrigger(angle: angle)
        guard value != trigger else { return }
        // Tear down the old gesture/capture before changing its reference.
        // Preserve the user's enabled choice, but require the new open angle
        // before arming another real-desktop gesture.
        pauseEffect(background.requested
            ? "Trigger set to \(value.degrees)°. Open to this angle to rearm."
            : "Trigger set to \(value.degrees)°. Starts below this angle when enabled.")
        gesture.configure(trigger: value)
        defaults.set(value.angle, forKey: Self.triggerKey)
        preview.setTriggerAngle(value)
        effect.referenceAngle = Float(value.angle)
        angleFilter.reset()
        if connected, let reading = lastReading {
            filteredAngle = min(value.angle, reading.angle)
            angleFilter.ingest(filteredAngle, time: reading.time)
            effect.angle = Float(filteredAngle)
        }
        nextResumeTime = 0
        updatePreview()
        updateDrawingActivity()
        refreshMenu()
        resumeIfPossible()
    }

    private func makeMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "macbook", accessibilityDescription: "Duo Lid")
        statusItem?.button?.image?.isTemplate = true
        statusItem?.button?.toolTip = "Duo Lid — effect off"
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        let status = NSMenuItem(title: "Desktop effect off", action: nil, keyEquivalent: "")
        status.isEnabled = false
        statusMenuItem = status
        menu.addItem(status)
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Settings and preview…", action: #selector(openPreview), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let enable = NSMenuItem(title: "Enable desktop effect", action: #selector(toggleFromMenu), keyEquivalent: "")
        enable.target = self
        effectMenuItem = enable
        menu.addItem(enable)
        let pause = NSMenuItem(title: "Pause desktop effect", action: #selector(pauseFromMenu), keyEquivalent: "d")
        pause.keyEquivalentModifierMask = [.control, .option, .command]
        pause.target = self
        menu.addItem(pause)
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        loginMenuItem = login
        menu.addItem(login)
        let approval = NSMenuItem(title: "Approve login item in System Settings…", action: #selector(openLoginSettings), keyEquivalent: "")
        approval.target = self
        loginApprovalItem = approval
        menu.addItem(approval)
        menu.addItem(.separator())
        let about = NSMenuItem(title: "About Duo Lid…", action: #selector(aboutFromMenu), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let terms = NSMenuItem(title: "Licence and risk notice…", action: #selector(termsFromMenu), keyEquivalent: "")
        terms.target = self
        menu.addItem(terms)
        menu.addItem(NSMenuItem(title: "Quit Duo Lid", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        refreshMenu()
    }

    func menuWillOpen(_ menu: NSMenu) { refreshMenu() }
    @objc private func aboutFromMenu() { AppBrand.showAbout() }
    @objc private func termsFromMenu() {
        if let url = Bundle.main.url(forResource: "EULA", withExtension: "md") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshMenu() {
        let message: String
        if enabled { message = "Desktop effect enabled · below \(trigger.degrees)°" }
        else if !background.requested { message = "Desktop effect off" }
        else if background.suspended { message = "Waiting for wake or unlock" }
        else if !DesktopSnapshot.sessionIsActive { message = "Waiting for active desktop session" }
        else if !DesktopSnapshot.hasPermission { message = "Screen Recording permission required" }
        else if hotKey?.registered != true { message = "Pause shortcut unavailable" }
        else if !connected { message = sensorSession == nil ? "Waiting for lid sensor" : "Connecting lid sensor…" }
        else if DesktopSnapshot.builtInScreen() == nil { message = "Waiting for built-in display" }
        else if (lastReading?.angle ?? 0) < trigger.angle { message = "Waiting for lid to open to \(trigger.degrees)°" }
        else { message = "Preparing desktop effect…" }
        statusMenuItem?.title = message
        statusItem?.button?.toolTip = "Duo Lid — \(message.lowercased())"
        effectMenuItem?.title = background.requested ? "Disable desktop effect" : "Enable desktop effect"
        effectMenuItem?.state = background.requested ? .on : .off
        preview.setEnabled(enabled, requested: background.requested)
        let login = SMAppService.mainApp.status
        loginMenuItem?.state = login == .enabled ? .on : login == .requiresApproval ? .mixed : .off
        loginApprovalItem?.isHidden = login != .requiresApproval
    }

    @objc private func toggleLogin() {
        do {
            let service = SMAppService.mainApp
            if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            } else {
                let path = Bundle.main.bundleURL.standardizedFileURL.path
                guard path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/") else {
                    showError("Move Duo Lid to Applications first", message: "Quit this copy, move Duo Lid.app to Applications, reopen it, then select Launch at login.")
                    return
                }
                try service.register()
            }
        } catch { showError("Launch at login couldn't be changed", message: error.localizedDescription) }
        refreshMenu()
    }

    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }

    private func showError(_ title: String, message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private func observeSession() {
        let center = NSWorkspace.shared.notificationCenter
        let events: [(Notification.Name, BackgroundState.Event)] = [
            (NSWorkspace.willSleepNotification, .sleep), (NSWorkspace.didWakeNotification, .wake),
            (NSWorkspace.screensDidSleepNotification, .displaySleep), (NSWorkspace.screensDidWakeNotification, .displayWake),
            (NSWorkspace.sessionDidResignActiveNotification, .resignSession), (NSWorkspace.sessionDidBecomeActiveNotification, .activateSession),
        ]
        for (name, event) in events {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspendSession(event) }
            }
            observers.append((center, token))
        }
        let displays = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.suspendSession(nil) }
        }
        observers.append((NotificationCenter.default, displays))
        // Extra fail-closed signal for a lock that doesn't put the display to sleep.
        // No secure-space manipulation or private framework is used.
        let distributed = DistributedNotificationCenter.default()
        for (name, event) in [("com.apple.screenIsLocked", BackgroundState.Event.lock),
                              ("com.apple.screenIsUnlocked", BackgroundState.Event.unlock)] {
            let token = distributed.addObserver(forName: Notification.Name(name),
                                                object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspendSession(event) }
            }
            observers.append((distributed, token))
        }
    }

    private func updatePreview() {
        var state = effect
        state.preview = true
        preview.glass.effect = state
        // Image replacement and session resets also need a frame when the
        // angle/style did not change and display-paced drawing is paused.
        preview.glass.refreshPausedFrame()
        preview.setAngle(Double(effect.angle))
    }

    private func presentationState(previewing: Bool) -> EffectState {
        if !connected && demoPlaying { demoTick() }
        if connected, let reading = lastReading {
            let now = CACurrentMediaTime()
            let target = min(trigger.angle, reading.angle)
            if let angle = angleFilter.sample(at: now) {
                filteredAngle = trigger.isOpen(reading.angle) ? max(trigger.angle, angle) : min(trigger.angle - 0.001, angle)
                effect.angle = Float(filteredAngle)
                effect.referenceAngle = Float(trigger.angle)
                if now - lastLabelTime >= 0.1 {
                    preview.setAngle(reading.angle)
                    lastLabelTime = now
                }
                if angleFilter.isSettled && angle == target { updateDrawingActivity(settled: true) }
            }
        }
        var state = effect
        state.preview = previewing
        return state
    }

    private func updateDrawingActivity(settled: Bool = false) {
        let desktopVisible = overlay?.isVisible == true
        let target = min(trigger.angle, lastReading?.angle ?? trigger.angle)
        let moving = connected && !settled && (!angleFilter.isSettled || angleFilter.value != target)
        preview.glass.setAnimating((moving || demoPlaying) && !desktopVisible && preview.window?.isVisible == true && preview.window?.isMiniaturized != true)
        overlay?.glass.setAnimating(moving && enabled && gesture.active && desktopVisible)
    }

    private func toggleDemo() {
        guard !connected else { return }
        if demoPlaying { stopDemo(); return }
        demoStarted = CACurrentMediaTime()
        demoPlaying = true
        preview.setPlaying(true)
        updateDrawingActivity()
    }

    private func demoTick() {
        let elapsed = CACurrentMediaTime() - demoStarted
        if elapsed >= 5.6 {
            effect.angle = Float(max(120, trigger.approachUpperAngle))
            preview.setAngle(Double(effect.angle))
            stopDemo()
            return
        }
        // Only the demonstration is timed. Hardware mode always uses sensor position.
        let phase = elapsed / 5.6
        let fold = (1 - cos(phase * 2 * .pi)) * 0.5
        let openAngle = trigger.approachUpperAngle
        effect.angle = Float(openAngle - (openAngle - LidTrigger.fadeAngle) * fold)
        effect.referenceAngle = Float(trigger.angle)
        // Keep the slider and degree value on the same presentation frame as
        // the sample fold. Sensor labels retain their separate update throttle.
        preview.setAngle(Double(effect.angle))
    }

    private func stopDemo() {
        demoPlaying = false
        preview.setPlaying(false)
        updateDrawingActivity()
    }

    private func previewDesktop() {
        guard !shuttingDown else { return }
        guard DesktopSnapshot.requestPermissionIfNeeded() else {
            preview.setStatus(DesktopSnapshot.Failure.permission.localizedDescription)
            return
        }
        guard let screen = preview.window?.screen ?? NSScreen.main else {
            preview.setStatus("No display is available for preview.")
            return
        }
        pauseEffect("Preparing a temporary desktop image…", clearRequest: true)
        let generation = captureGeneration
        preview.setBusy(true)
        captureTask = Task { [weak self] in
            do {
                let image = try await DesktopSnapshot.capture(screen: screen)
                guard let self, self.captureGeneration == generation, !Task.isCancelled else { return }
                try self.renderer.prepare(image)
                self.showingDesktop = true
                self.preview.setSource(desktop: true)
                self.preview.setStatus("Desktop snapshot · images stay in memory")
                self.preview.setBusy(false)
                self.updatePreview()
                self.captureTask = nil
            } catch is CancellationError {
                // The newer action owns UI state.
            } catch {
                guard let self, self.captureGeneration == generation else { return }
                self.preview.setBusy(false)
                self.preview.setStatus(error.localizedDescription)
                self.captureTask = nil
            }
        }
    }

    private func useSample() {
        pauseEffect("Sample image · no permissions needed", clearRequest: true)
        do {
            try renderer.prepare(SampleDesktop.make())
            showingDesktop = false
            preview.setSource(desktop: false)
            updatePreview()
        } catch { preview.setStatus(error.localizedDescription) }
    }

    private func toggleSensor() {
        if sensorSession != nil { disconnectSensor(clearRequest: true); return }
        stopDemo()
        let token = UUID()
        sensorSession = token
        preview.setSensor(connected: false, message: "Checking the lid sensor…", canEnable: false)
        let sensor = self.sensor
        sensorTask = Task { [weak self] in
            let connection = await sensor.connect(session: token)
            guard let self, self.sensorSession == token, !Task.isCancelled else {
                await sensor.disconnect(session: token)
                return
            }
            switch connection {
            case .unavailable(let message):
                self.sensorSession = nil
                self.sensorTask = nil
                self.preview.setSensor(connected: false, message: message, canEnable: false)
                self.refreshMenu()
                await sensor.disconnect(session: token)
                return
            case .ready(let reading):
                self.connected = true
                self.nextResumeTime = 0
                self.angleFilter.reset()
                self.gesture.reset(at: reading.angle)
                self.lastHealthyTime = reading.time
                self.receive(reading)
                let message = self.hotKey?.registered == true
                    ? "Read-only lid sensor connected. Move the lid to preview."
                    : "The pause shortcut is in use. Desktop mode stays off."
                self.preview.setSensor(connected: true, message: message,
                                       canEnable: self.canEnable)
                self.refreshMenu()
            }
            var failures = 0
            let clock = ContinuousClock()
            var deadline = clock.now
            while !Task.isCancelled {
                if let reading = await sensor.reading(session: token) {
                    guard self.sensorSession == token else { break }
                    failures = 0
                    self.receive(reading)
                } else {
                    failures += 1
                    if failures >= 15 {
                        if self.sensorSession == token {
                            self.disconnectSensor(message: "The sensor stopped responding. The desktop effect is off.")
                        }
                        break
                    }
                }
                // Deadline-based polling: report time no longer adds drift to every interval.
                deadline += .nanoseconds(16_666_667)
                if deadline < clock.now { deadline = clock.now }
                do { try await clock.sleep(until: deadline) } catch { break }
            }
            await sensor.disconnect(session: token)
        }
    }

    private var canEnable: Bool {
        connected && !background.suspended && DesktopSnapshot.sessionIsActive && hotKey?.registered == true && DesktopSnapshot.builtInScreen() != nil
    }

    private func disconnectSensor(message: String = "Sensor disconnected. Use the slider to preview.", clearRequest: Bool = false) {
        nextResumeTime = CACurrentMediaTime() + 5
        pauseEffect(message, clearRequest: clearRequest)
        sensorSession = nil
        sensorTask?.cancel()
        sensorTask = nil
        connected = false
        lastReading = nil
        angleFilter.reset()
        gesture.reset()
        effect.referenceAngle = Float(trigger.angle)
        effect.angle = Float(max(120, trigger.approachUpperAngle))
        preview.setSensor(connected: false, message: message, canEnable: false)
        updateDrawingActivity(settled: true)
        updatePreview()
        refreshMenu()
    }

    private func receive(_ reading: LidSensor.Reading) {
        lastReading = reading
        lastHealthyTime = reading.time
        if trigger.isOpen(reading.angle) {
            // Raw readings remove the effect immediately. Keep an open seed
            // current even when neither view draws, so the first below-trigger report
            // starts a smooth transition instead of resetting across an idle gap.
            angleFilter.reset()
            angleFilter.ingest(trigger.angle, time: reading.time)
            filteredAngle = trigger.angle
            effect.angle = Float(trigger.angle)
            var state = effect
            state.preview = true
            preview.glass.effect = state
        } else {
            angleFilter.ingest(reading.angle, time: reading.time)
        }
        let wasActive = gesture.active
        let state = gesture.update(reading.angle)
        switch state {
        case .closed, .invalid:
            if enabled { pauseEffect("Lid closed. The effect is off; normal sleep behavior applies.") }
        case .idle:
            if wasActive {
                cancelCapture()
                overlay?.orderOut(nil)
                overlayRenderer?.clear()
                captureReady = false
                activeSince = nil
            }
            if enabled {
                if reading.angle > trigger.approachUpperAngle {
                    if captureReady || captureTask != nil {
                        cancelCapture()
                        overlayRenderer?.clear()
                        captureReady = false
                    }
                } else if !captureReady && captureTask == nil {
                    // One snapshot in the 10-degree approach band, not a video stream.
                    // Avoid making capture/blur latency part of the activation boundary.
                    beginGestureCapture()
                }
            }
        case .bending:
            if enabled && !wasActive {
                activeSince = CACurrentMediaTime()
                if !captureReady && captureTask == nil { beginGestureCapture() }
            }
            updateOverlay()
        }
        updateDrawingActivity()
        resumeIfPossible()
    }

    private func requestEnable() {
        guard DesktopSnapshot.requestPermissionIfNeeded() else {
            pauseEffect(DesktopSnapshot.Failure.permission.localizedDescription, clearRequest: true)
            return
        }
        background.requested = true
        defaults.set(true, forKey: Self.requestedKey)
        nextResumeTime = 0
        resumeIfPossible()
        refreshMenu()
    }

    private func resumeIfPossible() {
        let now = CACurrentMediaTime()
        guard !shuttingDown, background.requested, !background.suspended, DesktopSnapshot.sessionIsActive,
              !enabled, captureTask == nil, now >= nextResumeTime else { return }
        if sensorSession == nil {
            nextResumeTime = now + 5
            toggleSensor()
            return
        }
        guard background.canArm(angle: lastReading?.angle, fresh: connected && now - lastHealthyTime <= 0.5,
                                permission: DesktopSnapshot.hasPermission, shortcut: hotKey?.registered == true,
                                display: DesktopSnapshot.builtInScreen() != nil, trigger: trigger) else { return }
        nextResumeTime = now + 5
        enableEffect()
    }

    private func enableEffect() {
        guard canEnable, let reading = lastReading, let screen = DesktopSnapshot.builtInScreen() else {
            preview.setEnabled(false)
            preview.setStatus("Connect a readable lid sensor and use the built-in display first.")
            return
        }
        guard trigger.isOpen(reading.angle) else {
            preview.setEnabled(false)
            preview.setStatus("Open the lid to at least \(trigger.degrees)° before enabling the effect.")
            return
        }
        // Automatic restoration never requests a privacy permission.
        guard background.requested, !background.suspended, DesktopSnapshot.hasPermission else {
            preview.setEnabled(false)
            preview.setStatus(DesktopSnapshot.Failure.permission.localizedDescription)
            return
        }
        pauseEffect("Checking desktop capture…")
        let generation = captureGeneration
        preview.setBusy(true)
        captureTask = Task { [weak self] in
            do {
                let image = try await DesktopSnapshot.capture(screen: screen)
                guard let self, self.captureGeneration == generation, !Task.isCancelled else { return }
                guard self.background.requested, self.canEnable, CACurrentMediaTime() - self.lastHealthyTime <= 0.5,
                      let latestReading = self.lastReading, self.trigger.isOpen(latestReading.angle) else {
                    self.nextResumeTime = 0
                    self.pauseEffect("Open the lid and reconnect the sensor before enabling the effect.")
                    return
                }
                let renderer = try GlassRenderer()
                if latestReading.angle <= self.trigger.approachUpperAngle { try renderer.prepare(image) }
                self.overlayRenderer = renderer
                self.overlay = OverlayWindow(screen: screen, renderer: renderer)
                self.overlay?.glass.onOverlayClick = { [weak self] in
                    self?.pauseEffect("Paused by your click. Your desktop is back to normal.", clearRequest: true)
                }
                self.overlay?.glass.onFrame = { [weak self] in
                    self?.presentationState(previewing: false) ?? EffectState()
                }
                self.enabled = true
                self.captureReady = latestReading.angle <= self.trigger.approachUpperAngle
                self.gesture.reset(at: latestReading.angle)
                self.preview.setEnabled(true)
                self.preview.setBusy(false)
                self.preview.setStatus("Enabled · starts below \(self.trigger.degrees)° · pause with ⌃⌥⌘D")
                self.statusItem?.button?.toolTip = "Duo Lid — effect enabled"
                self.captureTask = nil
                self.refreshMenu()
            } catch is CancellationError {
            } catch {
                guard let self, self.captureGeneration == generation else { return }
                self.pauseEffect(error.localizedDescription)
            }
        }
    }

    private func beginGestureCapture() {
        guard enabled, let screen = DesktopSnapshot.builtInScreen(), let overlayRenderer else {
            pauseEffect("The built-in display is unavailable. The effect is off.")
            return
        }
        cancelCapture()
        let generation = captureGeneration
        captureReady = false
        captureTask = Task { [weak self] in
            do {
                let image = try await DesktopSnapshot.capture(screen: screen)
                guard let self, self.captureGeneration == generation, self.enabled,
                      let reading = self.lastReading, reading.angle <= self.trigger.approachUpperAngle,
                      reading.angle > self.gesture.closedAngle,
                      !Task.isCancelled else { return }
                try overlayRenderer.prepare(image)
                self.captureReady = true
                self.updateOverlay()
                self.captureTask = nil
                self.updateDrawingActivity()
            } catch is CancellationError {
            } catch {
                guard let self, self.captureGeneration == generation else { return }
                self.pauseEffect(error.localizedDescription)
            }
        }
    }

    private func updateOverlay() {
        guard enabled, gesture.active, captureReady, let overlay,
              let reference = gesture.reference, DesktopSnapshot.builtInScreen() != nil else { return }
        var state = effect
        state.preview = false
        state.referenceAngle = Float(reference)
        state.angle = Float(filteredAngle)
        overlay.glass.effect = state
        if !overlay.isVisible { overlay.orderFrontRegardless() }
    }

    private func cancelCapture() {
        captureGeneration = UUID()
        captureTask?.cancel()
        captureTask = nil
        preview.setBusy(false)
    }

    private func pauseEffect(_ message: String, clearRequest: Bool = false) {
        if clearRequest {
            background.requested = false
            defaults.set(false, forKey: Self.requestedKey)
        }
        stopDemo()
        enabled = false
        cancelCapture()
        overlay?.orderOut(nil)
        overlay = nil
        overlayRenderer?.clear()
        overlayRenderer = nil
        captureReady = false
        activeSince = nil
        preview.setEnabled(false, requested: background.requested)
        preview.setStatus(message)
        statusItem?.button?.toolTip = "Duo Lid — effect off"
        updateDrawingActivity()
        refreshMenu()
    }

    private func maintainSafety() {
        let now = CACurrentMediaTime()
        if connected, let reading = lastReading, now - lastLabelTime >= 0.1 {
            preview.setAngle(reading.angle)
            lastLabelTime = now
        }
        if connected && now - lastHealthyTime > 1.0 {
            disconnectSensor(message: "The lid sensor stopped responding. The effect is off.")
            return
        }
        if enabled && (!DesktopSnapshot.hasPermission || !DesktopSnapshot.sessionIsActive || DesktopSnapshot.builtInScreen() == nil) {
            pauseEffect("Desktop capture is unavailable. The effect is off.")
        } else if enabled, let activeSince, now - activeSince >= 30 {
            pauseEffect("Paused after 30 seconds. Open the lid to rearm.")
        }
        resumeIfPossible()
    }

    private func suspendSession(_ event: BackgroundState.Event?) {
        guard !shuttingDown else { return }
        if let event { background.receive(event) }
        if background.suspended || event == nil {
            disconnectSensor(message: "Effect suspended. It resumes when the session is active and the lid is open.")
            // Release captured desktop content on lock/sleep/session transitions.
            if showingDesktop {
                do {
                    try renderer.prepare(SampleDesktop.make())
                    showingDesktop = false
                    preview.setSource(desktop: false)
                    updatePreview()
                } catch {
                    renderer.clear()
                    showingDesktop = false
                    preview.setSource(desktop: false)
                    updatePreview()
                }
            }
        }
        if !background.suspended { nextResumeTime = CACurrentMediaTime() + 0.5 }
        refreshMenu()
    }

    func shutdown() {
        shuttingDown = true
        stopDemo()
        pauseEffect("Desktop effect is off.")
        maintenanceTimer?.invalidate()
        maintenanceTimer = nil
        sensorSession = nil
        sensorTask?.cancel()
        sensorTask = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        hotKey?.stop()
        hotKey = nil
        renderer.clear()
        preview.glass.setAnimating(false)
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    @objc private func openPreview() { showWindow() }
    @objc private func toggleFromMenu() {
        if background.requested { pauseEffect("Desktop effect is off.", clearRequest: true) }
        else { requestEnable() }
    }
    @objc private func pauseFromMenu() { pauseEffect("Paused. Your desktop is back to normal.", clearRequest: true) }
}
