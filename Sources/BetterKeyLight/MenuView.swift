import SwiftUI
import AppKit

struct MenuView: View {
    @EnvironmentObject var store: LightStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if store.host.isEmpty {
                Text("Searching for Key Lights on your network … You can also enter the address manually in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                controls
                presets
            }

            statusInfo

            Divider()

            HStack {
                Button("Settings …") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 320)
        .task { await store.refresh() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: MenuBarIcon.header(on: store.isOn))
                .renderingMode(.template)
                .foregroundStyle(store.isOn ? .yellow : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(1)
                HStack(spacing: 4) {
                    Circle()
                        .fill(store.reachable ? .green : .red)
                        .frame(width: 7, height: 7)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { store.isOn }, set: { store.setOn($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(store.host.isEmpty)
        }
    }

    private var title: String {
        if let name = store.info?.displayName, !name.isEmpty { return name }
        if let product = store.info?.productName, !product.isEmpty { return product }
        return "Elgato Key Light"
    }

    private var statusText: String {
        if store.host.isEmpty { return "Not configured" }
        if store.reachable { return "Connected" }
        return store.lastError ?? "Not reachable"
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledSlider(title: "Brightness",
                          valueText: "\(Int(store.brightness)) %",
                          minIcon: "sun.min", maxIcon: "sun.max.fill") {
                // No `step:` here: macOS would draw a tick mark for every step, which is slow.
                Slider(value: Binding(get: { store.brightness },
                                      set: { store.brightness = $0.rounded() }),
                       in: 3...100)
                    .onChange(of: store.brightness) { store.valuesChanged() }
            }
            HStack(spacing: 4) {
                ForEach([5, 10, 25, 50, 75, 100], id: \.self) { level in
                    Button {
                        store.switchLight(on: true, brightness: Double(level))
                    } label: {
                        Text("\(level)%")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.small)
                }
            }
            .padding(.bottom, 4)
            LabeledSlider(title: "Color temperature",
                          valueText: "\(Int(store.kelvin)) K",
                          minIcon: "flame", maxIcon: "snowflake") {
                Slider(value: Binding(get: { store.kelvin },
                                      set: { store.kelvin = ($0 / 50).rounded() * 50 }),
                       in: ColorTemp.kelvinRange)
                    .onChange(of: store.kelvin) { store.valuesChanged() }
            }
        }
        .disabled(!store.isOn)
        .opacity(store.isOn ? 1 : 0.5)
    }

    @ViewBuilder
    private var presets: some View {
        if !store.presets.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Presets").font(.subheadline)
                let all = store.presets
                let rows = stride(from: 0, to: all.count, by: 3).map { start in
                    Array(all[start..<min(start + 3, all.count)])
                }
                VStack(spacing: 6) {
                    ForEach(rows.indices, id: \.self) { index in
                        HStack(spacing: 6) {
                            ForEach(rows[index]) { preset in
                                presetButton(preset)
                            }
                        }
                    }
                }
            }
        }
    }

    private func presetButton(_ preset: Preset) -> some View {
        let active = store.isActive(preset)
        return Button {
            store.applyPreset(preset)
        } label: {
            Text(preset.name)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.small)
        .background(active ? Color.accentColor.opacity(0.3) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5))
        .help("\(preset.brightness) % · \(preset.kelvin) K")
    }

    @ViewBuilder
    private var statusInfo: some View {
        if store.cameraEnabled && store.cameraActive {
            Label("Camera in use", systemImage: "video.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if store.scheduleEnabled, let (entry, date) = store.nextScheduled {
            Label {
                Text("Next: \(entry.action.label) \(date.formatted(.relative(presentation: .named).locale(Locale(identifier: "en"))))")
            } icon: {
                Image(systemName: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct LabeledSlider<S: View>: View {
    let title: String
    let valueText: String
    let minIcon: String
    let maxIcon: String
    @ViewBuilder let slider: () -> S

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(valueText).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Image(systemName: minIcon).foregroundStyle(.secondary).font(.caption)
                slider()
                Image(systemName: maxIcon).foregroundStyle(.secondary).font(.caption)
            }
        }
    }
}
