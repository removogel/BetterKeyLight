import Foundation
import SwiftUI
import AppKit
import ServiceManagement

@MainActor
final class LightStore: ObservableObject {
    // MARK: Settings (persisted)
    @Published var host: String { didSet { defaults.set(host, forKey: "host"); addressChanged() } }
    @Published var port: Int { didSet { defaults.set(port, forKey: "port"); addressChanged() } }
    /// Bonjour name of the selected light; lets the app follow it when its IP changes.
    @Published var serviceName: String { didSet { defaults.set(serviceName, forKey: "serviceName") } }
    @Published var scheduleEnabled: Bool { didSet { defaults.set(scheduleEnabled, forKey: "scheduleEnabled") } }
    @Published var schedules: [ScheduleEntry] { didSet { nextCache = nil; save(schedules, key: "schedules") } }
    @Published var presets: [Preset] { didSet { save(presets, key: "presets") } }
    @Published var fadeEnabled: Bool { didSet { defaults.set(fadeEnabled, forKey: "fadeEnabled") } }
    @Published var cameraEnabled: Bool { didSet { defaults.set(cameraEnabled, forKey: "cameraEnabled"); updateCameraTimer() } }
    /// UUID string of the preset applied when the camera starts; empty = keep last settings.
    @Published var cameraPresetID: String { didSet { defaults.set(cameraPresetID, forKey: "cameraPresetID") } }
    @Published var sleepOffEnabled: Bool { didSet { defaults.set(sleepOffEnabled, forKey: "sleepOffEnabled") } }
    @Published var wakeRestoreEnabled: Bool { didSet { defaults.set(wakeRestoreEnabled, forKey: "wakeRestoreEnabled") } }
    @Published var idleOffEnabled: Bool { didSet { defaults.set(idleOffEnabled, forKey: "idleOffEnabled"); updateIdleTimer() } }
    @Published var idleMinutes: Int { didSet { defaults.set(idleMinutes, forKey: "idleMinutes") } }
    @Published var dayCycleEnabled: Bool {
        didSet { defaults.set(dayCycleEnabled, forKey: "dayCycleEnabled"); dayCycleOverride = false; applyDayCycle() }
    }
    @Published var dayKelvin: Int { didSet { defaults.set(dayKelvin, forKey: "dayKelvin"); applyDayCycle() } }
    @Published var nightKelvin: Int { didSet { defaults.set(nightKelvin, forKey: "nightKelvin"); applyDayCycle() } }
    /// Minute of the day at which the light is fully cool / fully warm.
    @Published var dayStartMinutes: Int { didSet { defaults.set(dayStartMinutes, forKey: "dayStartMinutes"); applyDayCycle() } }
    @Published var nightStartMinutes: Int { didSet { defaults.set(nightStartMinutes, forKey: "nightStartMinutes"); applyDayCycle() } }

    // MARK: Light state
    @Published var isOn = false
    @Published var brightness: Double = 50
    @Published var kelvin: Double = 4500
    @Published var reachable = false
    @Published var lastError: String?
    @Published var lastScheduleEvent: String?
    @Published var info: AccessoryInfo?
    @Published var discovered: [DiscoveredLight] = []
    @Published var cameraActive = false

    private let defaults = UserDefaults.standard
    private let discovery: Discovery
    let usage: UsageStats
    private var pollTimer: Timer?
    private var cameraTimer: Timer?
    private var idleTimer: Timer?
    private var sendTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var wakeTask: Task<Void, Never>?
    private var lastScheduleCheck = Date()
    private var nextCache: (validUntil: Date, value: (ScheduleEntry, Date)?)?
    /// Keeps a poll from resetting the sliders while the user is dragging them.
    private var suppressPollUntil = Date.distantPast
    /// Last state known to match the light; avoids sending it back unchanged.
    private var lastKnown: LightState?
    /// True once the real state has been read from the light at least once.
    private var stateLoaded = false
    private var infoRequested = false

    // Camera coupling
    private var cameraIdleCount = 0
    private var cameraTurnedOn = false
    private var cameraCheckRunning = false

    // Sleep / lock handling
    private enum AwayReason { case systemSleep, screenSleep, locked, idle }
    private var awayReasons: Set<AwayReason> = []
    private var sleepTurnedOff = false
    private var idleCheckRunning = false

    // Day cycle
    /// Set when the user picks a color temperature by hand; cleared when the light is next switched on.
    private var dayCycleOverride = false
    private var fadingUntil = Date.distantPast

    init() {
        let d = UserDefaults.standard
        host = d.string(forKey: "host") ?? ""
        let p = d.integer(forKey: "port")
        port = p == 0 ? 9123 : p
        serviceName = d.string(forKey: "serviceName") ?? ""
        scheduleEnabled = d.object(forKey: "scheduleEnabled") as? Bool ?? true
        if let data = d.data(forKey: "schedules"),
           let list = try? JSONDecoder().decode([ScheduleEntry].self, from: data) {
            schedules = list
        } else {
            schedules = []
        }
        if let data = d.data(forKey: "presets"),
           let list = try? JSONDecoder().decode([Preset].self, from: data) {
            presets = list
        } else {
            presets = Preset.defaults
        }
        fadeEnabled = d.object(forKey: "fadeEnabled") as? Bool ?? true
        cameraEnabled = d.bool(forKey: "cameraEnabled")
        cameraPresetID = d.string(forKey: "cameraPresetID") ?? ""
        sleepOffEnabled = d.bool(forKey: "sleepOffEnabled")
        wakeRestoreEnabled = d.object(forKey: "wakeRestoreEnabled") as? Bool ?? true
        idleOffEnabled = d.bool(forKey: "idleOffEnabled")
        let idle = d.integer(forKey: "idleMinutes")
        idleMinutes = idle == 0 ? 10 : idle
        dayCycleEnabled = d.bool(forKey: "dayCycleEnabled")
        dayKelvin = d.object(forKey: "dayKelvin") as? Int ?? 5600
        nightKelvin = d.object(forKey: "nightKelvin") as? Int ?? 3200
        dayStartMinutes = d.object(forKey: "dayStartMinutes") as? Int ?? 9 * 60
        nightStartMinutes = d.object(forKey: "nightStartMinutes") as? Int ?? 21 * 60
        discovery = Discovery()
        usage = UsageStats()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        pollTimer?.tolerance = 2

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setAway(.systemSleep, true) }
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.setAway(.systemSleep, false)
                self?.setAway(.screenSleep, false)
                self?.tick()
            }
        }
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setAway(.screenSleep, true) }
        }
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setAway(.screenSleep, false) }
        }
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setAway(.locked, true) }
        }
        distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setAway(.locked, false) }
        }

        discovery.onChange = { [weak self] lights in
            self?.discoveryChanged(lights)
        }
        discovery.start()
        updateCameraTimer()
        updateIdleTimer()

        Task { await refresh() }
    }

    private var client: KeyLightClient { KeyLightClient(host: host, port: port) }

    private var currentState: LightState {
        LightState(on: isOn ? 1 : 0,
                   brightness: Int(brightness.rounded()),
                   temperature: ColorTemp.toAPI(kelvin: kelvin))
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    // MARK: Discovery

    private func discoveryChanged(_ lights: [DiscoveredLight]) {
        discovered = lights
        if host.isEmpty {
            // Nothing configured yet: adopt the first light that shows up.
            if let first = lights.first { use(first) }
        } else if serviceName.isEmpty {
            // Manually configured light that we now recognise by name.
            if let match = lights.first(where: { $0.host == host && $0.port == port }) {
                serviceName = match.name
            }
        } else if let match = lights.first(where: { $0.name == serviceName }),
                  match.host != host || match.port != port {
            // The selected light got a new address: follow it.
            host = match.host
            port = match.port
        }
    }

    func use(_ light: DiscoveredLight) {
        serviceName = light.name
        if host != light.host { host = light.host }
        if port != light.port { port = light.port }
    }

    func isCurrent(_ light: DiscoveredLight) -> Bool {
        light.host == host && light.port == port
    }

    /// Sets an address typed in by hand.
    func setManual(host newHost: String, port newPort: Int) {
        serviceName = discovered.first { $0.host == newHost && $0.port == newPort }?.name ?? ""
        if host != newHost { host = newHost }
        if port != newPort { port = newPort }
    }

    private func addressChanged() {
        stateLoaded = false
        lastKnown = nil
        info = nil
        infoRequested = false
        refreshSoon()
    }

    // MARK: Reading

    func refresh(force: Bool = false) async {
        guard force || Date() >= suppressPollUntil else { return }
        let c = client
        do {
            let s = try await c.fetch()
            guard c.host == host, c.port == port else { return }
            // Skip the result if the user changed something while we were waiting.
            guard force || Date() >= suppressPollUntil else { return }
            apply(s)
        } catch {
            guard c.host == host, c.port == port else { return }
            fail(error)
            return
        }
        if info == nil && !infoRequested {
            infoRequested = true
            let loaded = try? await c.fetchInfo()
            if c.host == host, c.port == port { info = loaded }
        }
    }

    private func refreshSoon() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await refresh(force: true)
        }
    }

    /// Assigns only when the value differs, so views are not redrawn for nothing.
    private func set<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<LightStore, T>, _ value: T) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    private func apply(_ s: LightState) {
        set(\.isOn, s.on == 1)
        set(\.brightness, Double(s.brightness))
        set(\.kelvin, Double(ColorTemp.toKelvin(s.temperature)))
        lastKnown = currentState
        stateLoaded = true
        markReachable()
        usage.record(isOn: isOn)
    }

    private func markReachable() {
        set(\.reachable, true)
        set(\.lastError, nil)
    }

    private func fail(_ error: Error) {
        set(\.reachable, false)
        set(\.lastError, error.localizedDescription)
        usage.record(isOn: false)
    }

    // MARK: Control

    func setOn(_ on: Bool) { switchLight(on: on) }

    func toggle() { setOn(!isOn) }

    /// Switches the light and optionally sets brightness and color temperature.
    /// Values that are not given are left as the light has them.
    func switchLight(on: Bool, brightness newBrightness: Double? = nil,
                     kelvin newKelvin: Double? = nil, animated: Bool = true) {
        let wasOn = isOn
        let known = stateLoaded
        if let newBrightness { brightness = newBrightness }
        if let newKelvin {
            kelvin = newKelvin
            dayCycleOverride = true
        } else if on && !wasOn && dayCycleEnabled {
            // Switching on starts with the color temperature for the current time of day.
            dayCycleOverride = false
            if known { kelvin = Double(cycleKelvin) }
        }
        isOn = on
        usage.record(isOn: on)

        if known {
            if fadeEnabled && animated && wasOn != on {
                fade(on: on)
            } else {
                push(debounce: false)
            }
        } else if newBrightness != nil && newKelvin != nil {
            push(debounce: false)
        } else {
            // The light's real settings are unknown, so only send what was asked for.
            sendPatch(LightPatch(on: on ? 1 : 0,
                                 brightness: newBrightness.map { Int($0.rounded()) },
                                 temperature: newKelvin.map { ColorTemp.toAPI(kelvin: $0) }))
        }
    }

    /// Called by the sliders; sends with a short debounce.
    func valuesChanged() {
        let state = currentState
        guard state != lastKnown else { return }
        // A color temperature chosen by hand pauses the day cycle.
        if let last = lastKnown, last.temperature != state.temperature { dayCycleOverride = true }
        push(debounce: true)
    }

    private func push(debounce: Bool) {
        suppressPollUntil = Date().addingTimeInterval(2)
        let state = currentState
        let c = client
        lastKnown = state
        sendTask?.cancel()
        sendTask = Task {
            if debounce {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
            }
            do {
                try await c.send(state)
                markReachable()
            } catch {
                if !Task.isCancelled { fail(error) }
            }
        }
    }

    private func sendPatch(_ patch: LightPatch) {
        suppressPollUntil = Date().addingTimeInterval(2)
        let c = client
        lastKnown = currentState
        sendTask?.cancel()
        sendTask = Task {
            do {
                let result = try await c.send(patch)
                guard !Task.isCancelled else { return }
                if let result {
                    apply(result)
                } else {
                    markReachable()
                }
            } catch {
                if !Task.isCancelled { fail(error) }
            }
        }
    }

    /// Ramps the brightness up after switching on, or down before switching off.
    private func fade(on: Bool) {
        suppressPollUntil = Date().addingTimeInterval(4)
        fadingUntil = Date().addingTimeInterval(1.5)
        let target = max(3, Int(brightness.rounded()))
        let temperature = ColorTemp.toAPI(kelvin: kelvin)
        let c = client
        lastKnown = currentState
        sendTask?.cancel()
        sendTask = Task {
            let steps = 10
            do {
                for i in 1...steps {
                    let t = Double(i) / Double(steps)
                    let span = Double(target - 3)
                    let level = on ? 3 + span * t : Double(target) - span * t
                    try await c.send(LightState(on: 1, brightness: max(3, Int(level.rounded())), temperature: temperature))
                    try await Task.sleep(for: .milliseconds(35))
                }
                if !on {
                    // Switch off, but leave the brightness where it was for next time.
                    try await c.send(LightState(on: 0, brightness: target, temperature: temperature))
                }
                markReachable()
            } catch {
                if !Task.isCancelled { fail(error) }
            }
        }
    }

    // MARK: Day cycle

    /// Color temperature the day cycle asks for right now.
    var cycleKelvin: Int {
        DayCycle.kelvin(at: Date(), day: dayKelvin, night: nightKelvin,
                        dayStart: dayStartMinutes, nightStart: nightStartMinutes)
    }

    private func applyDayCycle() {
        guard dayCycleEnabled, !dayCycleOverride, isOn, stateLoaded, Date() >= fadingUntil else { return }
        let target = Double(cycleKelvin)
        guard target != kelvin else { return }
        kelvin = target
        push(debounce: true)
    }

    // MARK: Presets

    func applyPreset(_ preset: Preset) {
        switchLight(on: true, brightness: Double(preset.brightness), kelvin: Double(preset.kelvin))
    }

    func isActive(_ preset: Preset) -> Bool {
        isOn && Int(brightness.rounded()) == preset.brightness && Int(kelvin) == preset.kelvin
    }

    func addPresetFromCurrent() {
        presets.append(Preset(name: "Preset \(presets.count + 1)",
                              brightness: max(3, Int(brightness.rounded())),
                              kelvin: Int(kelvin)))
    }

    func removePreset(_ id: UUID) {
        if cameraPresetID == id.uuidString { cameraPresetID = "" }
        presets.removeAll { $0.id == id }
    }

    // MARK: Camera coupling

    private func updateCameraTimer() {
        cameraTimer?.invalidate()
        cameraTimer = nil
        cameraIdleCount = 0
        guard cameraEnabled else {
            cameraActive = false
            cameraTurnedOn = false
            return
        }
        cameraTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkCamera() }
        }
        cameraTimer?.tolerance = 0.5
        checkCamera()
    }

    /// Queries the camera state in the background; the system call can be slow.
    private func checkCamera() {
        guard !cameraCheckRunning else { return }
        cameraCheckRunning = true
        Task {
            let running = await Task.detached(priority: .utility) {
                CameraMonitor.isAnyCameraRunning()
            }.value
            cameraCheckRunning = false
            guard cameraEnabled else { return }
            cameraChanged(running)
        }
    }

    private func cameraChanged(_ running: Bool) {
        if running {
            cameraIdleCount = 0
            guard !cameraActive else { return }
            cameraActive = true
            // Leave the light alone if it is already on.
            guard !isOn else { return }
            cameraTurnedOn = true
            if let preset = presets.first(where: { $0.id.uuidString == cameraPresetID }) {
                applyPreset(preset)
            } else {
                switchLight(on: true)
            }
        } else if cameraActive {
            // Wait for two idle checks so a brief camera restart doesn't flicker the light.
            cameraIdleCount += 1
            guard cameraIdleCount >= 2 else { return }
            cameraActive = false
            if cameraTurnedOn {
                cameraTurnedOn = false
                if isOn { switchLight(on: false) }
            }
        }
    }

    // MARK: Sleep and screen lock

    private func setAway(_ reason: AwayReason, _ active: Bool) {
        let wasAway = !awayReasons.isEmpty
        if active {
            guard reason == .idle ? idleOffEnabled : sleepOffEnabled else { return }
            awayReasons.insert(reason)
        } else {
            awayReasons.remove(reason)
        }
        let isAway = !awayReasons.isEmpty
        if isAway && !wasAway {
            // No fade before sleep: the Mac may be asleep before a fade would finish.
            wentAway(animated: reason == .idle)
        } else if !isAway && wasAway {
            cameBack()
        }
    }

    private func wentAway(animated: Bool) {
        wakeTask?.cancel()
        guard isOn else { return }
        sleepTurnedOff = true
        switchLight(on: false, animated: animated)
    }

    private func cameBack() {
        guard sleepTurnedOff else { return }
        sleepTurnedOff = false
        guard wakeRestoreEnabled else { return }
        wakeTask?.cancel()
        wakeTask = Task {
            // The network may need a moment after waking up.
            for _ in 0..<8 {
                if Task.isCancelled { return }
                if (try? await client.fetch()) != nil { break }
                try? await Task.sleep(for: .seconds(2))
            }
            guard !Task.isCancelled else { return }
            switchLight(on: true)
        }
    }

    // MARK: Idle

    private func updateIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
        guard idleOffEnabled else {
            setAway(.idle, false)
            return
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIdle() }
        }
        idleTimer?.tolerance = 1
    }

    private func checkIdle() {
        // Seconds since the last keyboard or mouse input of any kind.
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                           eventType: CGEventType(rawValue: ~0)!)
        let isIdleAway = awayReasons.contains(.idle)
        if idle < Double(idleMinutes * 60) {
            if isIdleAway { setAway(.idle, false) }
        } else if !isIdleAway && isOn && !idleCheckRunning {
            // Watching or presenting on camera is not "away", even without input.
            idleCheckRunning = true
            Task {
                let cameraRunning = await Task.detached(priority: .utility) {
                    CameraMonitor.isAnyCameraRunning()
                }.value
                idleCheckRunning = false
                if !cameraRunning && idleOffEnabled { setAway(.idle, true) }
            }
        }
    }

    // MARK: Schedule

    private func tick() {
        let now = Date()
        if scheduleEnabled { runSchedules(from: lastScheduleCheck, to: now) }
        lastScheduleCheck = now
        usage.record(isOn: isOn && reachable)
        applyDayCycle()
        Task { await refresh() }
    }

    private func runSchedules(from start: Date, to end: Date) {
        // Only catch up on missed rules (e.g. during sleep) if they are less than 10 minutes old.
        let from = max(start, end.addingTimeInterval(-600))
        let due = schedules
            .compactMap { e -> (ScheduleEntry, Date)? in
                guard let d = e.nextFire(after: from.addingTimeInterval(-1)), d <= end else { return nil }
                return (e, d)
            }
            .sorted { $0.1 < $1.1 }
        // If several rules are due, the latest one wins.
        guard let (entry, _) = due.last else { return }
        execute(entry)
    }

    func execute(_ entry: ScheduleEntry) {
        switch entry.action {
        case .on:
            switchLight(on: true, brightness: entry.setBrightness ? Double(entry.brightness) : nil)
        case .off:
            switchLight(on: false)
        }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        lastScheduleEvent = "\(f.string(from: Date())): \(entry.action.label)"
    }

    /// Next rule to fire. Cached, because views ask for it on every redraw.
    var nextScheduled: (ScheduleEntry, Date)? {
        guard scheduleEnabled else { return nil }
        let now = Date()
        if let cache = nextCache, now < cache.validUntil { return cache.value }
        let value = schedules.compactMap { e in e.nextFire(after: now).map { (e, $0) } }
            .min { $0.1 < $1.1 }
        var validUntil = now.addingTimeInterval(60)
        if let fire = value?.1, fire < validUntil { validUntil = fire }
        nextCache = (validUntil, value)
        return value
    }

    func addSchedule() { schedules.append(ScheduleEntry()) }

    func removeSchedule(_ id: UUID) { schedules.removeAll { $0.id == id } }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                lastError = "Launch at login: \(error.localizedDescription)"
            }
            objectWillChange.send()
        }
    }
}
