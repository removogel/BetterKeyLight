import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ConnectionSettings()
                .tabItem { Label("Light", systemImage: "lightbulb") }
            PresetSettings()
                .tabItem { Label("Presets", systemImage: "slider.horizontal.3") }
            AutomationSettings()
                .tabItem { Label("Automation", systemImage: "wand.and.stars") }
            ScheduleSettings()
                .tabItem { Label("Schedule", systemImage: "clock") }
        }
        .frame(width: 540, height: 520)
    }
}

// MARK: - Light (discovery, address, device info)

struct ConnectionSettings: View {
    @EnvironmentObject var store: LightStore
    @State private var hostDraft = ""
    @State private var portDraft = ""
    @State private var testing = false

    var body: some View {
        Form {
            Section("Key Lights on your network") {
                if store.discovered.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Searching …").foregroundStyle(.secondary)
                    }
                }
                ForEach(store.discovered) { light in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(light.name)
                            Text("\(light.host):\(String(light.port))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.isCurrent(light) {
                            Label("Selected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button("Use") { store.use(light) }
                        }
                    }
                }
            }

            Section("Address") {
                TextField("IP address", text: $hostDraft, prompt: Text("e.g. 192.168.1.50"))
                    .onSubmit(save)
                TextField("Port", text: $portDraft, prompt: Text("9123"))
                    .onSubmit(save)
                HStack {
                    Button("Save & Test") { save() }
                        .keyboardShortcut(.defaultAction)
                    if testing { ProgressView().controlSize(.small) }
                    Spacer()
                    status
                }
                Text("Lights found on your network are followed automatically when their IP address changes. Enter an address by hand only if the search does not find your light.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let info = store.info {
                Section("Device") {
                    infoRow("Product", info.productName)
                    infoRow("Name", info.displayName)
                    infoRow("Serial number", info.serialNumber)
                    infoRow("Firmware", firmware(info))
                    infoRow("Board type", info.hardwareBoardType.map { String($0) })
                    infoRow("MAC address", info.macAddress)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: syncDrafts)
        .onChange(of: store.host) { syncDrafts() }
        .onChange(of: store.port) { syncDrafts() }
    }

    @ViewBuilder
    private func infoRow(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(title, value: value)
        }
    }

    private func firmware(_ info: AccessoryInfo) -> String? {
        guard let version = info.firmwareVersion else { return nil }
        if let build = info.firmwareBuildNumber { return "\(version) (build \(build))" }
        return version
    }

    @ViewBuilder private var status: some View {
        if store.host.isEmpty {
            EmptyView()
        } else if store.reachable {
            Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Label(store.lastError ?? "Not reachable", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    private func syncDrafts() {
        hostDraft = store.host
        portDraft = String(store.port)
    }

    private func save() {
        store.setManual(host: hostDraft.trimmingCharacters(in: .whitespaces),
                        port: Int(portDraft) ?? 9123)
        syncDrafts()
        testing = true
        Task {
            await store.refresh(force: true)
            testing = false
        }
    }
}

// MARK: - Presets

struct PresetSettings: View {
    @EnvironmentObject var store: LightStore

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Presets") {
                    if store.presets.isEmpty {
                        Text("No presets yet. Set up the light the way you like it, then add it here.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach($store.presets) { $preset in
                        PresetRow(preset: $preset) {
                            store.applyPreset(preset)
                        } delete: {
                            store.removePreset(preset.id)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button {
                    store.addPresetFromCurrent()
                } label: {
                    Label("Add Current Settings as Preset", systemImage: "plus")
                }
            }
            .padding([.horizontal, .bottom], 16)
        }
    }
}

struct PresetRow: View {
    @Binding var preset: Preset
    var apply: () -> Void
    var delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Name", text: $preset.name)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                Button(action: apply) { Image(systemName: "play.fill") }
                    .buttonStyle(.borderless)
                    .help("Apply now")
                Button(role: .destructive, action: delete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Delete preset")
            }
            HStack {
                Image(systemName: "sun.max").foregroundStyle(.secondary).frame(width: 18)
                Slider(value: Binding(get: { Double(preset.brightness) },
                                      set: { preset.brightness = Int($0) }),
                       in: 3...100, step: 1)
                Text("\(preset.brightness) %")
                    .monospacedDigit()
                    .frame(width: 60, alignment: .trailing)
            }
            HStack {
                Image(systemName: "thermometer.medium").foregroundStyle(.secondary).frame(width: 18)
                Slider(value: Binding(get: { Double(preset.kelvin) },
                                      set: { preset.kelvin = Int($0) }),
                       in: ColorTemp.kelvinRange, step: 50)
                Text("\(String(preset.kelvin)) K")
                    .monospacedDigit()
                    .frame(width: 60, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Automation

struct AutomationSettings: View {
    @EnvironmentObject var store: LightStore

    var body: some View {
        Form {
            Section("Switching") {
                Toggle("Fade smoothly when turning on or off", isOn: $store.fadeEnabled)
            }

            Section("Camera") {
                Toggle("Turn on while the camera is in use", isOn: $store.cameraEnabled)
                Picker("When the camera starts", selection: $store.cameraPresetID) {
                    Text("Keep last settings").tag("")
                    ForEach(store.presets) { preset in
                        Text(preset.name).tag(preset.id.uuidString)
                    }
                }
                .disabled(!store.cameraEnabled)
                Text("The light turns off again when the camera stops, unless it was already on before.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sleep") {
                Toggle("Turn off when the Mac sleeps or the screen locks", isOn: $store.sleepOffEnabled)
                Toggle("Turn back on after waking or unlocking", isOn: $store.wakeRestoreEnabled)
                    .disabled(!store.sleepOffEnabled)
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.launchAtLogin = $0 }))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Schedule

struct ScheduleSettings: View {
    @EnvironmentObject var store: LightStore

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle("Schedule enabled", isOn: $store.scheduleEnabled)
                }
                Section("Rules") {
                    if store.schedules.isEmpty {
                        Text("No rules yet. Add one such as “Mo–Fr 08:00 turn on”.")
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
                    Text("Last run: \(ev)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    store.addSchedule()
                } label: {
                    Label("Add Rule", systemImage: "plus")
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
                    .help("Run now")
                Button(role: .destructive, action: delete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Delete rule")
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
                    Toggle("Set brightness", isOn: $entry.setBrightness)
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
