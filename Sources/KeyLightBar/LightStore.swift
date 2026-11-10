import Foundation
import SwiftUI
import AppKit
import ServiceManagement

@MainActor
final class LightStore: ObservableObject {
    // MARK: Einstellungen (persistiert)
    @Published var host: String { didSet { defaults.set(host, forKey: "host"); refreshSoon() } }
    @Published var port: Int { didSet { defaults.set(port, forKey: "port"); refreshSoon() } }
    @Published var scheduleEnabled: Bool { didSet { defaults.set(scheduleEnabled, forKey: "scheduleEnabled") } }
    @Published var schedules: [ScheduleEntry] { didSet { saveSchedules() } }

    // MARK: Leuchtenzustand
    @Published var isOn = false
    @Published var brightness: Double = 50
    @Published var kelvin: Double = 4500
    @Published var reachable = false
    @Published var lastError: String?
    @Published var lastScheduleEvent: String?

    private let defaults = UserDefaults.standard
    private var pollTimer: Timer?
    private var sendTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var lastScheduleCheck = Date()
    /// Verhindert, dass ein Poll während des Schiebens die Slider zurücksetzt.
    private var suppressPollUntil = Date.distantPast
    /// Zuletzt bekannter Zustand der Leuchte – verhindert unnötiges Zurücksenden.
    private var lastKnown: LightState?

    init() {
        host = defaults.string(forKey: "host") ?? ""
        let p = defaults.integer(forKey: "port")
        port = p == 0 ? 9123 : p
        scheduleEnabled = defaults.object(forKey: "scheduleEnabled") as? Bool ?? true
        if let data = defaults.data(forKey: "schedules"),
           let list = try? JSONDecoder().decode([ScheduleEntry].self, from: data) {
            schedules = list
        } else {
            schedules = []
        }

        pollTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        pollTimer?.tolerance = 2

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }

        Task { await refresh() }
    }

    private var client: KeyLightClient { KeyLightClient(host: host, port: port) }

    private var currentState: LightState {
        LightState(on: isOn ? 1 : 0,
                   brightness: Int(brightness.rounded()),
                   temperature: ColorTemp.toAPI(kelvin: kelvin))
    }

    // MARK: Abfragen

    func refresh() async {
        guard Date() >= suppressPollUntil else { return }
        do {
            let s = try await client.fetch()
            apply(s)
        } catch {
            fail(error)
        }
    }

    private func refreshSoon() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    private func apply(_ s: LightState) {
        isOn = s.on == 1
        brightness = Double(s.brightness)
        kelvin = Double(ColorTemp.toKelvin(s.temperature))
        lastKnown = currentState
        reachable = true
        lastError = nil
    }

    private func fail(_ error: Error) {
        reachable = false
        lastError = error.localizedDescription
    }

    // MARK: Steuern

    func setOn(_ on: Bool) {
        isOn = on
        push(debounce: false)
    }

    func toggle() { setOn(!isOn) }

    /// Wird von den Slidern aufgerufen – sendet gedrosselt.
    func valuesChanged() {
        guard currentState != lastKnown else { return }
        push(debounce: true)
    }

    private func push(debounce: Bool) {
        suppressPollUntil = Date().addingTimeInterval(2)
        let state = currentState
        lastKnown = state
        sendTask?.cancel()
        sendTask = Task {
            if debounce {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
            }
            do {
                try await client.send(state)
                reachable = true
                lastError = nil
            } catch {
                if !Task.isCancelled { fail(error) }
            }
        }
    }

    // MARK: Zeitsteuerung

    private func tick() {
        let now = Date()
        if scheduleEnabled { runSchedules(from: lastScheduleCheck, to: now) }
        lastScheduleCheck = now
        Task { await refresh() }
    }

    private func runSchedules(from start: Date, to end: Date) {
        // Verpasste Ereignisse (z. B. im Ruhezustand) nur nachholen, wenn sie < 10 min her sind.
        let from = max(start, end.addingTimeInterval(-600))
        let due = schedules
            .compactMap { e -> (ScheduleEntry, Date)? in
                guard let d = e.nextFire(after: from.addingTimeInterval(-1)), d <= end else { return nil }
                return (e, d)
            }
            .sorted { $0.1 < $1.1 }
        // Bei mehreren fälligen Einträgen zählt der zuletzt fällige.
        guard let (entry, _) = due.last else { return }
        execute(entry)
    }

    func execute(_ entry: ScheduleEntry) {
        switch entry.action {
        case .on:
            isOn = true
            if entry.setBrightness { brightness = Double(entry.brightness) }
        case .off:
            isOn = false
        }
        push(debounce: false)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        lastScheduleEvent = "\(f.string(from: Date())): \(entry.action.label)"
    }

    var nextScheduled: (ScheduleEntry, Date)? {
        guard scheduleEnabled else { return nil }
        let now = Date()
        return schedules.compactMap { e in e.nextFire(after: now).map { (e, $0) } }
            .min { $0.1 < $1.1 }
    }

    func addSchedule() { schedules.append(ScheduleEntry()) }

    func removeSchedule(_ id: UUID) { schedules.removeAll { $0.id == id } }

    private func saveSchedules() {
        if let data = try? JSONEncoder().encode(schedules) {
            defaults.set(data, forKey: "schedules")
        }
    }

    // MARK: Bei Anmeldung starten

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                lastError = "Autostart: \(error.localizedDescription)"
            }
            objectWillChange.send()
        }
    }
}
