import AppKit

@MainActor
final class PreviewWindow: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    var onAngle: ((Double) -> Void)?
    var onAppearance: ((Float, Float, Float) -> Void)?
    var onTrigger: ((Double) -> Void)?
    var onPlay: (() -> Void)?
    var onDesktop: (() -> Void)?
    var onSample: (() -> Void)?
    var onSensor: (() -> Void)?
    var onEnable: ((Bool) -> Void)?
    var onPause: (() -> Void)?
    var onHide: (() -> Void)?

    let glass: GlassView
    private let angle = NSSlider(value: 120, minValue: 10, maxValue: 160, target: nil, action: nil)
    private let degrees = NSTextField(labelWithString: "120°")
    private let triggerField = NSTextField(string: "90")
    private let triggerStepper = NSStepper()
    private var triggerValue = LidTrigger()
    private let depth = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let softness = NSSlider(value: 1, minValue: 0, maxValue: 1.4, target: nil, action: nil)
    private let shade = NSSlider(value: 0.55, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let sensorButton = NSButton(title: "Connect lid sensor", target: nil, action: nil)
    private let enableButton = NSButton(checkboxWithTitle: "Enable desktop lid effect", target: nil, action: nil)
    private let desktopButton = NSButton(title: "Preview my desktop", target: nil, action: nil)
    private let playButton = NSButton(title: "Play a fold", target: nil, action: nil)
    private let sensorLabel = NSTextField(wrappingLabelWithString: "Connect your MacBook to follow its lid. The preview also works with the slider.")
    private let status = NSTextField(wrappingLabelWithString: "Sample image · no permissions needed")
    private let sourceLabel = NSTextField(labelWithString: "SAMPLE DESKTOP")
    private let badge = NSTextField(labelWithString: "EFFECT OFF")
    private var sensorCanEnable = false
    private var effectRequested = false
    private var busy = false

    init(renderer: GlassRenderer) {
        glass = GlassView(renderer: renderer)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 830),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.delegate = self
        window.title = "Duo Lid"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.065, green: 0.077, blue: 0.096, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 1030, height: 810)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("DuoLidPreview")
        window.center()
        buildContent()
    }

    required init?(coder: NSCoder) { nil }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let root = stack(.vertical, spacing: 24)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 54),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
        ])

        let heading = stack(.horizontal, spacing: 18)
        let icon = NSImageView(image: AppBrand.icon)
        icon.setAccessibilityLabel("Duo Lid app icon")
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 45).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 45).isActive = true
        let titles = stack(.vertical, spacing: 5)
        titles.addArrangedSubview(label("Duo Lid", size: 29, weight: .semibold))
        let headline = stack(.horizontal, spacing: 9)
        headline.addArrangedSubview(label(AppBrand.headline, size: 14, color: .secondaryLabelColor))
        let linkedIn = NSButton(image: AppBrand.linkedInIcon, target: self, action: #selector(openLinkedIn))
        linkedIn.isBordered = false
        linkedIn.imageScaling = .scaleProportionallyUpOrDown
        linkedIn.toolTip = "Michal Stawarz on LinkedIn"
        linkedIn.setAccessibilityLabel("Open Michal Stawarz’s LinkedIn profile")
        linkedIn.widthAnchor.constraint(equalToConstant: 22).isActive = true
        linkedIn.heightAnchor.constraint(equalToConstant: 22).isActive = true
        headline.addArrangedSubview(linkedIn)
        titles.addArrangedSubview(headline)
        heading.addArrangedSubview(icon)
        heading.addArrangedSubview(titles)
        heading.addArrangedSubview(NSView())
        badge.font = .systemFont(ofSize: 10, weight: .semibold)
        badge.textColor = .secondaryLabelColor
        heading.addArrangedSubview(badge)
        root.addArrangedSubview(heading)
        heading.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let body = stack(.horizontal, spacing: 24)
        body.alignment = .top
        let preview = stack(.vertical, spacing: 12)
        sourceLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        sourceLabel.textColor = .secondaryLabelColor
        preview.addArrangedSubview(sourceLabel)
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 16
        glass.layer?.masksToBounds = true
        preview.addArrangedSubview(glass)
        let caption = label("The image holds its position as the glass moves over it.", size: 12, color: .secondaryLabelColor)
        preview.addArrangedSubview(caption)
        glass.widthAnchor.constraint(equalTo: preview.widthAnchor).isActive = true
        glass.heightAnchor.constraint(greaterThanOrEqualToConstant: 432).isActive = true
        glass.heightAnchor.constraint(equalTo: glass.widthAnchor, multiplier: 0.625).isActive = true
        preview.setHuggingPriority(.defaultLow, for: .horizontal)
        body.addArrangedSubview(preview)

        let controls = stack(.vertical, spacing: 12)
        controls.widthAnchor.constraint(equalToConstant: 272).isActive = true
        controls.addArrangedSubview(label("Try the fold", size: 20, weight: .semibold))
        let angleRow = stack(.horizontal, spacing: 8)
        angleRow.addArrangedSubview(label("Lid position", size: 13, color: .secondaryLabelColor))
        angleRow.addArrangedSubview(NSView())
        degrees.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        angleRow.addArrangedSubview(degrees)
        controls.addArrangedSubview(angleRow)
        angleRow.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
        angle.target = self
        angle.action = #selector(angleChanged)
        angle.isContinuous = true
        angle.setAccessibilityLabel("Lid angle in degrees")
        controls.addArrangedSubview(angle)
        angle.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
        configure(playButton, action: #selector(playPressed))
        controls.addArrangedSubview(playButton)
        let triggerRow = stack(.horizontal, spacing: 6)
        triggerRow.addArrangedSubview(label("Trigger angle", size: 12))
        triggerRow.addArrangedSubview(NSView())
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.allowsFloats = false
        formatter.usesGroupingSeparator = false
        formatter.minimum = NSNumber(value: LidTrigger.range.lowerBound)
        formatter.maximum = NSNumber(value: LidTrigger.range.upperBound)
        triggerField.formatter = formatter
        triggerField.delegate = self
        triggerField.alignment = .right
        triggerField.widthAnchor.constraint(equalToConstant: 42).isActive = true
        triggerField.setAccessibilityLabel("Trigger angle in degrees")
        triggerField.toolTip = "Starts below this angle; reopening to it clears the effect. Range: 30–140°."
        triggerRow.addArrangedSubview(triggerField)
        triggerRow.addArrangedSubview(label("°", size: 12))
        triggerStepper.minValue = LidTrigger.range.lowerBound
        triggerStepper.maxValue = LidTrigger.range.upperBound
        triggerStepper.increment = 1
        triggerStepper.valueWraps = false
        triggerStepper.target = self
        triggerStepper.action = #selector(triggerStepped)
        triggerStepper.setAccessibilityLabel("Adjust trigger angle")
        triggerRow.addArrangedSubview(triggerStepper)
        let resetTrigger = NSButton(title: "Reset", target: self, action: #selector(resetTriggerPressed))
        resetTrigger.bezelStyle = .rounded
        resetTrigger.toolTip = "Reset the trigger angle to 90°."
        resetTrigger.setAccessibilityLabel("Reset trigger angle to 90 degrees")
        triggerRow.addArrangedSubview(resetTrigger)
        controls.addArrangedSubview(triggerRow)
        triggerRow.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
        setTriggerAngle(triggerValue)
        controls.addArrangedSubview(separator())
        controls.addArrangedSubview(label("Appearance", size: 14, weight: .semibold))
        appearanceControl("Depth", slider: depth, in: controls)
        appearanceControl("Softness", slider: softness, in: controls)
        appearanceControl("Shade", slider: shade, in: controls)
        controls.addArrangedSubview(separator())
        configure(desktopButton, action: #selector(desktopPressed))
        controls.addArrangedSubview(desktopButton)
        let sample = NSButton(title: "Use sample image", target: self, action: #selector(samplePressed))
        sample.bezelStyle = .rounded
        controls.addArrangedSubview(sample)
        controls.addArrangedSubview(label("Desktop preview asks only for Screen Recording.", size: 11,
                                         color: .secondaryLabelColor, wraps: true))
        controls.addArrangedSubview(separator())
        configure(sensorButton, action: #selector(sensorPressed))
        controls.addArrangedSubview(sensorButton)
        sensorLabel.font = .systemFont(ofSize: 11)
        sensorLabel.textColor = .secondaryLabelColor
        controls.addArrangedSubview(sensorLabel)
        sensorLabel.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
        enableButton.target = self
        enableButton.action = #selector(enablePressed)
        enableButton.font = .systemFont(ofSize: 12, weight: .medium)
        enableButton.isEnabled = false
        enableButton.toolTip = "Click anywhere to pause without activating apps underneath. You can also reopen the lid or press Control–Option–Command–D."
        controls.addArrangedSubview(enableButton)
        body.addArrangedSubview(controls)
        root.addArrangedSubview(body)
        body.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        root.addArrangedSubview(NSView())
        let footer = stack(.horizontal, spacing: 20)
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        footer.addArrangedSubview(status)
        let pause = NSButton(title: "Pause  ⌃⌥⌘D", target: self, action: #selector(pausePressed))
        pause.bezelStyle = .rounded
        pause.setContentHuggingPriority(.required, for: .horizontal)
        footer.addArrangedSubview(pause)
        root.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        root.addArrangedSubview(label("Close this window to keep Duo Lid in the menu bar. Pause turns the effect off until you enable it again.",
                                     size: 11, color: .tertiaryLabelColor))
    }

    private func appearanceControl(_ title: String, slider: NSSlider, in parent: NSStackView) {
        let row = stack(.horizontal, spacing: 12)
        let name = label(title, size: 12, color: .secondaryLabelColor)
        name.widthAnchor.constraint(equalToConstant: 64).isActive = true
        row.addArrangedSubview(name)
        slider.target = self
        slider.action = #selector(appearanceChanged)
        slider.isContinuous = true
        slider.setAccessibilityLabel(title)
        row.addArrangedSubview(slider)
        parent.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: parent.widthAnchor).isActive = true
    }

    private func configure(_ button: NSButton, action: Selector) {
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.widthAnchor.constraint(equalToConstant: 272).isActive = true
    }

    private func stack(_ orientation: NSUserInterfaceLayoutOrientation, spacing: CGFloat) -> NSStackView {
        let view = NSStackView()
        view.orientation = orientation
        view.spacing = spacing
        view.alignment = orientation == .vertical ? .leading : .centerY
        view.distribution = .fill
        return view
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                       color: NSColor = .labelColor, wraps: Bool = false) -> NSTextField {
        let field = wraps ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        if wraps { field.preferredMaxLayoutWidth = 272 }
        return field
    }

    private func separator() -> NSBox {
        let line = NSBox()
        line.boxType = .separator
        line.widthAnchor.constraint(equalToConstant: 272).isActive = true
        return line
    }

    func setAngle(_ value: Double) {
        if angle.doubleValue != value { angle.doubleValue = value }
        let text = "\(Int(value.rounded()))°"
        if degrees.stringValue != text { degrees.stringValue = text }
    }
    func setStatus(_ message: String) { status.stringValue = message }
    func setSource(desktop: Bool) { sourceLabel.stringValue = desktop ? "YOUR DESKTOP · TEMPORARY SNAPSHOT" : "SAMPLE DESKTOP" }
    func setPlaying(_ value: Bool) { playButton.title = value ? "Stop preview" : "Play a fold" }
    func setAppearance(depth: Float, softness: Float, shade: Float) {
        self.depth.floatValue = depth; self.softness.floatValue = softness; self.shade.floatValue = shade
    }
    func setTriggerAngle(_ value: LidTrigger) {
        triggerValue = value
        triggerField.integerValue = value.degrees
        triggerStepper.doubleValue = value.angle
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        guard notification.object as? NSTextField === triggerField else { return }
        let value = LidTrigger(angle: triggerField.doubleValue)
        setTriggerAngle(value)
        onTrigger?(value.angle)
    }
    func setSensor(connected: Bool, message: String, canEnable: Bool) {
        sensorCanEnable = canEnable
        sensorLabel.stringValue = message
        sensorButton.title = connected ? "Disconnect sensor" : "Connect lid sensor"
        angle.isEnabled = !connected
        playButton.isEnabled = !connected
        enableButton.isEnabled = !busy && (canEnable || effectRequested)
    }
    func setBusy(_ value: Bool) { busy = value; desktopButton.isEnabled = !value; enableButton.isEnabled = !value && (sensorCanEnable || effectRequested) }
    func setEnabled(_ value: Bool, requested: Bool = false) {
        effectRequested = value || requested
        enableButton.state = effectRequested ? .on : .off
        enableButton.isEnabled = !busy && (sensorCanEnable || effectRequested)
        badge.stringValue = value ? "EFFECT ON" : requested ? "WAITING" : "EFFECT OFF"
        badge.textColor = value ? NSColor.systemGreen : .secondaryLabelColor
    }

    func windowWillClose(_ notification: Notification) { onHide?(); glass.setAnimating(false) }
    func windowDidMiniaturize(_ notification: Notification) { onHide?(); glass.setAnimating(false) }

    @objc private func angleChanged() { onAngle?(angle.doubleValue) }
    @objc private func appearanceChanged() { onAppearance?(depth.floatValue, softness.floatValue, shade.floatValue) }
    @objc private func triggerStepped() {
        // Commit a typed value before using a stepper; otherwise an older
        // edit-end notification could overwrite the newly stepped setting.
        let step = triggerStepper.doubleValue - triggerValue.angle
        window?.makeFirstResponder(nil)
        let value = LidTrigger(angle: triggerValue.angle + step)
        setTriggerAngle(value)
        onTrigger?(value.angle)
    }
    @objc private func resetTriggerPressed() {
        window?.makeFirstResponder(nil)
        setTriggerAngle(LidTrigger())
        onTrigger?(LidTrigger.defaultAngle)
    }
    @objc private func playPressed() { onPlay?() }
    @objc private func desktopPressed() { onDesktop?() }
    @objc private func samplePressed() { onSample?() }
    @objc private func openLinkedIn() { AppBrand.openLinkedIn() }
    @objc private func sensorPressed() { onSensor?() }
    @objc private func enablePressed() { onEnable?(enableButton.state == .on) }
    @objc private func pausePressed() { onPause?() }
}
