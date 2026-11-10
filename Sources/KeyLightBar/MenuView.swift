import SwiftUI
import AppKit

struct MenuView: View {
    @EnvironmentObject var store: LightStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if store.host.isEmpty {
                Text("Bitte zuerst die IP-Adresse des Key Light in den Einstellungen eintragen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                controls
            }

            scheduleInfo

            Divider()

            HStack {
                Button("Einstellungen …") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Beenden") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 300)
        .task { await store.refresh() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: store.isOn ? "lightbulb.fill" : "lightbulb")
                .font(.title2)
                .foregroundStyle(store.isOn ? .yellow : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Elgato Key Light").font(.headline)
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

    private var statusText: String {
        if store.host.isEmpty { return "Nicht konfiguriert" }
        if store.reachable { return "Verbunden · \(store.host)" }
        return store.lastError ?? "Nicht erreichbar"
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledSlider(title: "Helligkeit",
                          valueText: "\(Int(store.brightness)) %",
                          minIcon: "sun.min", maxIcon: "sun.max.fill") {
                Slider(value: $store.brightness, in: 3...100, step: 1)
                    .onChange(of: store.brightness) { store.valuesChanged() }
            }
            LabeledSlider(title: "Farbtemperatur",
                          valueText: "\(Int(store.kelvin)) K",
                          minIcon: "flame", maxIcon: "snowflake") {
                Slider(value: $store.kelvin, in: ColorTemp.kelvinRange, step: 50)
                    .onChange(of: store.kelvin) { store.valuesChanged() }
            }
            HStack {
                ForEach([10, 25, 50, 75, 100], id: \.self) { v in
                    Button("\(v)%") {
                        store.brightness = Double(v)
                        if !store.isOn { store.setOn(true) }
                    }
                    .controlSize(.small)
                }
            }
        }
        .disabled(!store.isOn)
        .opacity(store.isOn ? 1 : 0.5)
    }

    @ViewBuilder
    private var scheduleInfo: some View {
        if store.scheduleEnabled, let (entry, date) = store.nextScheduled {
            Label {
                Text("Nächste Aktion: \(entry.action.label) \(date.formatted(.relative(presentation: .named)))")
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
