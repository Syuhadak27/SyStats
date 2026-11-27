import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState

    private var snapshot: TelemetrySnapshot { appState.telemetry.snapshot }
    private var thresholds: ThresholdController { appState.thresholds }

    private var startBinding: Binding<Int> {
        Binding(get: { appState.thresholds.startPercent },
                set: { appState.thresholds.startPercent = $0 })
    }
    private var stopBinding: Binding<Int> {
        Binding(get: { appState.thresholds.stopPercent },
                set: { appState.thresholds.stopPercent = $0 })
    }
    private var adapterBinding: Binding<String> {
        Binding(get: { appState.thresholds.selectedAdapterID },
                set: { appState.thresholds.selectedAdapterID = $0 })
    }
    private var enabledBinding: Binding<Bool> {
        Binding(get: { appState.preferences.thresholdEnabled },
                set: {
                    appState.preferences.thresholdEnabled = $0
                    Task { await appState.thresholds.apply() }
                })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                telemetryGrid
                HStack(alignment: .top, spacing: 16) {
                    batteryCard
                    thresholdCard
                }
                diagnosticsCard
            }
            .padding(20)
        }
    }

    private var header: some View {
        Card {
            HStack(spacing: 16) {
                if let icon = AppBranding.icon(preferences: appState.preferences) {
                    icon
                        .resizable()
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .shadow(radius: 4)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("SyStats")
                        .font(.title2.weight(.bold))
                    Text("Read-only EFI/ACPI audit · live power telemetry · modular threshold adapters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    StatusBadge(
                        title: snapshot.powerSource.label,
                        color: snapshot.powerSource == .ac ? .green : (snapshot.powerSource == .battery ? .orange : .gray),
                        symbol: snapshot.powerSource == .ac ? "bolt.fill" : "battery.75"
                    )
                    Text("Updated \(snapshot.timestamp, style: .time)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var telemetryGrid: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Live telemetry", systemImage: "waveform.path.ecg", subtitle: "Polling every \(appState.preferences.pollInterval, specifier: "%.1f") s")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    StatTile(label: "Voltage", value: snapshot.voltageText, detail: snapshot.electrical.voltageSource, accent: .cyan)
                    StatTile(label: "Current", value: snapshot.currentText, detail: snapshot.electrical.currentSource, accent: .blue)
                    StatTile(label: "Power", value: snapshot.powerText, detail: snapshot.electrical.powerSourceName, accent: .mint)
                    StatTile(label: "CPU", value: snapshot.cpuText, detail: "Mach host statistics", accent: .purple)
                    StatTile(label: "RAM", value: snapshot.ramText, detail: "Active + wired + compressed", accent: .indigo)
                    StatTile(label: "Fan", value: snapshot.fanText, detail: snapshot.fan.source, accent: .orange)
                    StatTile(label: "Temperature", value: snapshot.temperatureText, detail: snapshot.thermal.source, accent: .red)
                }
            }
        }
    }

    private var batteryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Battery", systemImage: "battery.100.bolt")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(snapshot.batteryText)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    if let charging = snapshot.battery.isCharging {
                        StatusBadge(title: charging ? "Charging" : "Discharging", color: charging ? .green : .orange, symbol: charging ? "bolt.fill" : "bolt.slash")
                    }
                }
                Divider()
                detailRow("Cycle count", value: snapshot.battery.cycleCount.map(String.init) ?? "—")
                detailRow("Health", value: snapshot.battery.health ?? "Not reported")
                detailRow("Time remaining", value: snapshot.battery.timeRemainingMinutes.map { "\($0) min" } ?? "—")
                detailRow("Data source", value: snapshot.battery.source)
                Text("Battery state is read from IOPowerSources; no writes here.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var thresholdCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Charge threshold", systemImage: "slider.horizontal.3", subtitle: "Desired values vs. adapter-confirmed state")
                Toggle("Enable charge threshold", isOn: enabledBinding)
                    .toggleStyle(.switch)
                thresholdSlider(title: "Start charging at", value: startBinding, color: .orange)
                thresholdSlider(title: "Stop charging at", value: stopBinding, color: .green)

                if let validation = thresholds.validationMessage {
                    Label(validation, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Picker("Runtime adapter", selection: adapterBinding) {
                    ForEach(Array(thresholds.adapters.indices), id: \.self) { index in
                        Text(thresholds.adapters[index].displayName)
                            .tag(thresholds.adapters[index].id)
                    }
                }
                .pickerStyle(.segmented)
                .font(.caption)

                capabilityBanner

                HStack {
                    Button {
                        Task { await thresholds.apply() }
                    } label: {
                        Label(thresholds.isApplying ? "Applying…" : "Apply threshold", systemImage: "bolt.badge.clock")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(thresholds.validationMessage != nil || thresholds.isApplying)

                    Button {
                        Task { await thresholds.readFromAdapter() }
                    } label: {
                        Label("Read back", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

                if let result = thresholds.lastResult {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(result.success ? .green : .red)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(result.message)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(result.success ? .green : .red)
                            Text(result.statusLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    ForEach(result.details, id: \.self) { detail in
                        Text("• \(detail)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let confirmed = thresholds.confirmedConfiguration {
                    Text("Confirmed by adapter: start \(confirmed.startPercent)% / stop \(confirmed.stopPercent)%")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    Text("Not confirmed by hardware. Sliders show desired values only.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var capabilityBanner: some View {
        let capability = appState.inspection.capability
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: capability.status == .available ? "checkmark.shield.fill" : "lock.shield")
                .foregroundStyle(capability.status == .available ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("Write capability: \(capability.status.label) — \(capability.displayName)")
                    .font(.caption.weight(.semibold))
                Text(capability.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var diagnosticsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Sensor & interface diagnostics", systemImage: "stethoscope")
                DiagnosticsList(messages: snapshot.diagnostics)
                DisclosureGroup("Why some values may be unavailable") {
                    Text("macOS does not expose a public API for charger voltage/current or direct ACPI EC method calls. Missing sensor keys are shown as “—” and explained rather than replaced with mock data. Prefix-only previews in the app are never presented as live readings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
                .font(.caption)
            }
        }
    }

    private func thresholdSlider(title: String, value: Binding<Int>, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(value.wrappedValue)%")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
            }
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0.rounded()) }
            ), in: 0...100, step: 5)
            .tint(color)
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.medium)).lineLimit(1)
        }
    }
}
