import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ConnectionSettings()
                .tabItem { Label("Verbindung", systemImage: "network") }
            ScheduleSettings()
                .tabItem { Label("Zeitsteuerung", systemImage: "clock") }
        }
        .frame(width: 520, height: 460)
    }
}

// MARK: - Verbindung

struct ConnectionSettings: View {
    @EnvironmentObject var store: LightStore
    @State private var hostDraft = ""
    @State private var portDraft = ""
    @State private var testing = false

    var body: some View {
        Form {
            Section("Elgato Key Light") {
                TextField("IP-Adresse", text: $hostDraft, prompt: Text("z. B. 192.168.1.50"))
                    .onSubmit(save)
                TextField("Port", text: $portDraft, prompt: Text("9123"))
                    .onSubmit(save)
                HStack {
                    Button("Speichern & testen") { save() }
                        .keyboardShortcut(.defaultAction)
                    if testing { ProgressView().controlSize(.small) }
                    Spacer()
                    status
                }
                Text("Die IP-Adresse findest du in der Elgato Control Center App unter den Geräteeinstellungen oder in deinem Router. Am besten im Router eine feste IP vergeben.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Allgemein") {
                Toggle("Bei Anmeldung starten", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.launchAtLogin = $0 }))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            hostDraft = store.host
            portDraft = String(store.port)
        }
    }

    @ViewBuilder private var status: some View {
        if store.host.isEmpty {
            EmptyView()
        } else if store.reachable {
            Label("Verbunden", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Label(store.lastError ?? "Nicht erreichbar", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    private func save() {
        store.host = hostDraft.trimmingCharacters(in: .whitespaces)
        store.port = Int(portDraft) ?? 9123
        portDraft = String(store.port)
        testing = true
        Task {
            await store.refresh()
            testing = false
        }
    }
}

// MARK: - Zeitsteuerung

struct ScheduleSettings: View {
    @EnvironmentObject var store: LightStore

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle("Zeitsteuerung aktiv", isOn: $store.scheduleEnabled)
                }
                Section("Regeln") {
                    if store.schedules.isEmpty {
                        Text("Noch keine Regeln. Füge z. B. „Mo–Fr 08:00 einschalten“ hinzu.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach($store.schedules) { $entry in
                        ScheduleRow(entry: $entry) {
                            store.removeSchedule(entry.id)
                        } runNow: {
                            store.execute(entry)
                        }
                    }
                }
                .disabled(!store.scheduleEnabled)
            }
            .formStyle(.grouped)

            HStack {
                if let ev = store.lastScheduleEvent {
                    Text("Zuletzt ausgeführt: \(ev)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    store.addSchedule()
                } label: {
                    Label("Regel hinzufügen", systemImage: "plus")
                }
            }
            .padding([.horizontal, .bottom], 16)
        }
    }
}

struct ScheduleRow: View {
    @Binding var entry: ScheduleEntry
    var delete: () -> Void
    var runNow: () -> Void

    private var time: Binding<Date> {
        Binding {
            Calendar.current.date(from: DateComponents(hour: entry.hour, minute: entry.minute)) ?? Date()
        } set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            entry.hour = c.hour ?? 0
            entry.minute = c.minute ?? 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("", isOn: $entry.enabled).labelsHidden()
                DatePicker("", selection: time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .frame(width: 80)
                Picker("", selection: $entry.action) {
                    ForEach(ScheduleEntry.Action.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 130)
                Spacer()
                Button(action: runNow) { Image(systemName: "play.fill") }
                    .buttonStyle(.borderless)
                    .help("Jetzt ausführen")
                Button(role: .destructive, action: delete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Regel löschen")
            }

            HStack(spacing: 4) {
                ForEach(Weekday.ordered, id: \.id) { day in
                    let selected = entry.weekdays.contains(day.id)
                    Button(day.short) {
                        if selected { entry.weekdays.remove(day.id) } else { entry.weekdays.insert(day.id) }
                    }
                    .buttonStyle(.bordered)
                    .tint(selected ? .accentColor : nil)
                    .controlSize(.small)
                    .background(selected ? Color.accentColor.opacity(0.25) : .clear,
                                in: RoundedRectangle(cornerRadius: 5))
                }
            }

            if entry.action == .on {
                HStack {
                    Toggle("Helligkeit setzen", isOn: $entry.setBrightness)
                    Slider(value: Binding(get: { Double(entry.brightness) },
                                          set: { entry.brightness = Int($0) }),
                           in: 3...100, step: 1)
                        .disabled(!entry.setBrightness)
                    Text("\(entry.brightness) %")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(entry.enabled ? 1 : 0.55)
    }
}
