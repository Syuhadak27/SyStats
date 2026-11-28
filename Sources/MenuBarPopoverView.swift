import SwiftUI

struct MenuBarPopoverView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var telemetry: TelemetryStore
    @EnvironmentObject private var thresholds: ThresholdController
    @EnvironmentObject private var preferences: PreferencesStore

    private var snapshot: TelemetrySnapshot { telemetry.snapshot }

    private var startBinding: Binding<Int> {
        Binding(get: { thresholds.startPercent }, set: { thresholds.startPercent = $0 })
    }
    private var stopBinding: Binding<Int> {
        Binding(get: { thresholds.stopPercent }, set: { thresholds.stopPercent = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            quickTelemetry
            Divider()
            thresholdControls
            Divider()
            statusFooter
            Button {
                appState.openFullGUI()
            } label: {
                Label("Open Full GUI", systemImage: "macwindow")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button {
                UpdateController.shared.checkForUpdates()
            } label: {
                Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .help("Cek rilis terbaru di GitHub Releases (v\(UpdateController.shared.currentVersion))")
        }
        .padding(14)
        .frame(width: 330)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let icon = AppBranding.icon(preferences: preferences) {
                icon.resizable().frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("SyStats").font(.headline)
                Text(snapshot.powerSource.label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(
                title: snapshot.batteryText,
                color: snapshot.powerSource == .ac ? .green : .orange,
                symbol: "battery.75"
            )
        }
    }

    private var quickTelemetry: some View {
        let mode = snapshot.resolvedMode(preferred: preferences.menuBarMode)
        return VStack(spacing: 8) {
            if mode == .ac {
                compactRow(symbol: "bolt", label: "Voltage", value: snapshot.voltageText)
                compactRow(symbol: "arrow.left.arrow.right", label: "Current", value: snapshot.currentText)
                compactRow(symbol: "bolt.batteryblock", label: "Power", value: snapshot.powerText)
            } else {
                compactRow(symbol: "cpu", label: "CPU", value: snapshot.cpuText)
                compactRow(symbol: "memorychip", label: "RAM", value: snapshot.ramText)
                compactRow(symbol: "wind", label: "Fan", value: snapshot.fanText)
                compactRow(symbol: "thermometer", label: "Temp", value: snapshot.temperatureText)
            }
        }
    }

    private func compactRow(symbol: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
        }
    }

    private var thresholdControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Charge threshold").font(.caption.weight(.semibold))
                Spacer()
                Text("\(startBinding.wrappedValue)% → \(stopBinding.wrappedValue)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tint)
            }
            HStack(spacing: 12) {
                Text("Start").font(.caption2).foregroundStyle(.secondary)
                Slider(value: Binding(get: { Double(startBinding.wrappedValue) },
                                      set: { startBinding.wrappedValue = Int($0.rounded()) }), in: 0...100, step: 1)
                Text("Stop").font(.caption2).foregroundStyle(.secondary)
                Slider(value: Binding(get: { Double(stopBinding.wrappedValue) },
                                      set: { stopBinding.wrappedValue = Int($0.rounded()) }), in: 0...100, step: 1)
            }
            if let message = thresholds.validationMessage {
                Text(message).font(.caption2).foregroundStyle(.orange)
            }
            HStack {
                Button {
                    Task { await thresholds.apply() }
                } label: {
                    Label("Apply", systemImage: "bolt.badge.clock")
                }
                .buttonStyle(.borderedProminent)
                .disabled(thresholds.validationMessage != nil || thresholds.isApplying)
                if let result = thresholds.lastResult {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(result.success ? .green : .red)
                    Text(result.statusLabel)
                        .font(.caption2)
                        .foregroundStyle(result.success ? .green : .red)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
    }

    private var statusFooter: some View {
        let capability = appState.inspection.capability
        let ok = capability.status == .available
        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "info.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text("Batas cas: \(capability.humanTitle.lowercased())")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }
}
