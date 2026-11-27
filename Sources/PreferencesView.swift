import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var appState: AppState

    private var preferences: PreferencesStore { appState.preferences }
    private var snapshot: TelemetrySnapshot { appState.telemetry.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                previewCard
                behaviorCard
                assetsCard
                advancedCard
            }
            .padding(20)
        }
    }

    // MARK: - Menu bar preview

    private var previewCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Menu bar preview", systemImage: "menubar.rectangle", subtitle: "Rendered from current telemetry in forced modes — not mock data")
                HStack(spacing: 16) {
                    previewTile(
                        title: "AC plugged in",
                        text: snapshot.menuBarText(mode: .ac, compact: preferences.compactMenuBar),
                        color: .green,
                        symbol: "bolt.fill"
                    )
                    previewTile(
                        title: "On battery",
                        text: snapshot.menuBarText(mode: .battery, compact: preferences.compactMenuBar),
                        color: .orange,
                        symbol: "battery.75"
                    )
                }
                Picker("Menu bar mode", selection: modeBinding) {
                    ForEach(MenuBarMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Compact text (omit CPU/RAM labels)", isOn: compactBinding)
                    .toggleStyle(.switch)
                Toggle("Show menu bar icon", isOn: iconBinding)
                    .toggleStyle(.switch)
                Text("Unavailable sensors render as “—”. The status item updates on the selected polling interval without blocking the main thread.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func previewTile(title: String, text: String, color: Color, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: symbol).foregroundStyle(color)
                Text(title).font(.caption.weight(.semibold))
                Spacer()
            }
            Text(text.isEmpty ? "—" : text)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Behavior

    private var behaviorCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Behavior", systemImage: "gearshape.2")
                HStack {
                    Text("Polling interval").font(.caption)
                    Spacer()
                    Text("\(preferences.pollInterval, specifier: "%.1f") s")
                        .font(.caption.weight(.bold).monospacedDigit())
                }
                Slider(value: intervalBinding, in: 1...10, step: 0.5)
                HStack {
                    Text("Threshold reapply").font(.caption)
                    Spacer()
                    Text("\(preferences.thresholdReapplyInterval, specifier: "%.1f") s")
                        .font(.caption.weight(.bold).monospacedDigit())
                }
                Slider(value: reapplyBinding, in: 1...30, step: 1)
                Toggle("Hide Dock icon (menu bar only)", isOn: dockBinding)
                    .toggleStyle(.switch)
                Toggle("Launch at login", isOn: loginBinding)
                    .toggleStyle(.switch)
                Button("Rescan EFI folder") { appState.scanEFI() }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Assets

    private var assetsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Assets", systemImage: "photo", subtitle: "Bundled defaults come from icon.png and menu_bar.png at the project root")
                assetRow(
                    title: "Application icon (icon.png)",
                    path: pathBinding(\.appIconAssetPath),
                    placeholder: "Bundled AppIcon"
                ) { if let url = FilePickers.chooseFile() { preferences.appIconAssetPath = url.path } }
                assetRow(
                    title: "Menu bar icon (menu_bar.png)",
                    path: pathBinding(\.menuBarAssetPath),
                    placeholder: "Bundled MenuBarIcon (template)"
                ) { if let url = FilePickers.chooseFile() { preferences.menuBarAssetPath = url.path } }
                Text("Menu bar images are forced to template rendering (monochrome) for sharp macOS rendering at any scale.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func assetRow(title: String, path: Binding<String>, placeholder: String, choose: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold))
            HStack {
                TextField(placeholder, text: path)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…", action: choose)
                Button("Reset") { path.wrappedValue = "" }
                    .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Advanced adapters

    private var advancedCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Advanced — YogaSMC / ThinkVPC", systemImage: "wrench.and.screwdriver", subtitle: "BCCS/BCSS via properti IOUserClient, bukan SMC key")
                HStack {
                    Text("Battery index").font(.caption)
                    Picker("", selection: batteryIndexBinding) {
                        Text("ANY (0)").tag(0)
                        Text("PRIMARY (1)").tag(1)
                        Text("SECONDARY (2)").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                }
                Toggle("Direct EC (ACPI WE1B + RE1B read-back)", isOn: ecDirectBinding)
                    .toggleStyle(.switch)
                HStack {
                    Text("Offset Start").font(.caption)
                    TextField("0x00", text: offsetBinding(\.ecStartOffset)).textFieldStyle(.roundedBorder).frame(maxWidth: 90)
                    Text("Stop").font(.caption)
                    TextField("0x00", text: offsetBinding(\.ecStopOffset)).textFieldStyle(.roundedBorder).frame(maxWidth: 90)
                    Text("Inhibit").font(.caption)
                    TextField("0x00", text: offsetBinding(\.ecInhibitOffset)).textFieldStyle(.roundedBorder).frame(maxWidth: 90)
                }
                Text("Direct EC default MATI. Isi offset hex 0x01–0x99 HANYA yang sudah diverifikasi di mesin Anda; kosongkan untuk tidak menulis byte EC. Salah offset dapat mengubah fan/LED/sleep. Setiap penulisan diverifikasi dengan RE1B.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Divider()
                HStack {
                    Text("Helper executable (opsional)").font(.caption)
                    TextField("/usr/local/bin/ectool", text: helperBinding)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") {
                        if let url = FilePickers.chooseFile() { preferences.helperCommandPath = url.path }
                    }
                }
                Text("Helper dipanggil: <path> <start%> <stop%>. Exit bukan 0 = gagal. Jalur ini tidak dipanggil berulang oleh timer reapply.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button("Reset all preferences") {
                    let domain = Bundle.main.bundleIdentifier ?? "com.systats.app"
                    UserDefaults.standard.removePersistentDomain(forName: domain)
                    appState.preferences.efiFolderPath = ""
                    appState.preferences.pollInterval = 2.0
                    appState.preferences.menuBarMode = .automatic
                    appState.preferences.compactMenuBar = false
                    appState.preferences.showMenuBarIcon = true
                    appState.preferences.thresholdEnabled = true
                    appState.preferences.batteryIndex = 1
                    appState.preferences.ecDirectEnabled = false
                    appState.preferences.ecStartOffset = 0
                    appState.preferences.ecStopOffset = 0
                    appState.preferences.ecInhibitOffset = 0
                    appState.preferences.thresholdReapplyInterval = 3.0
                    appState.preferences.thresholdAutoReapply = false
                    appState.preferences.helperCommandPath = ""
                    appState.scanEFI()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Bindings

    private var modeBinding: Binding<String> {
        Binding(get: { preferences.menuBarModeRaw }, set: { preferences.menuBarModeRaw = $0 })
    }
    private var compactBinding: Binding<Bool> {
        Binding(get: { preferences.compactMenuBar }, set: { preferences.compactMenuBar = $0 })
    }
    private var iconBinding: Binding<Bool> {
        Binding(get: { preferences.showMenuBarIcon }, set: { preferences.showMenuBarIcon = $0 })
    }
    private var intervalBinding: Binding<Double> {
        Binding(get: { preferences.pollInterval }, set: { preferences.pollInterval = $0 })
    }
    private var dockBinding: Binding<Bool> {
        Binding(get: { preferences.hideDockIcon }, set: { preferences.hideDockIcon = $0 })
    }
    private var loginBinding: Binding<Bool> {
        Binding(get: { preferences.launchAtLogin }, set: { preferences.launchAtLogin = $0 })
    }
    private var reapplyBinding: Binding<Double> {
        Binding(get: { preferences.thresholdReapplyInterval }, set: { preferences.thresholdReapplyInterval = $0 })
    }
    private var batteryIndexBinding: Binding<Int> {
        Binding(get: { preferences.batteryIndex },
                set: { preferences.batteryIndex = min(max($0, 0), 2) })
    }
    private var ecDirectBinding: Binding<Bool> {
        Binding(get: { preferences.ecDirectEnabled }, set: { preferences.ecDirectEnabled = $0 })
    }
    private var helperBinding: Binding<String> {
        Binding(get: { preferences.helperCommandPath }, set: { preferences.helperCommandPath = $0 })
    }
    private func pathBinding(_ keyPath: ReferenceWritableKeyPath<PreferencesStore, String>) -> Binding<String> {
        Binding(get: { preferences[keyPath: keyPath] }, set: { preferences[keyPath: keyPath] = $0 })
    }
    private func offsetBinding(_ keyPath: ReferenceWritableKeyPath<PreferencesStore, Int>) -> Binding<String> {
        Binding(
            get: {
                let value = preferences[keyPath: keyPath]
                return value == 0 ? "" : String(format: "0x%02X", value)
            },
            set: { raw in
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let hex = (text.hasPrefix("0x") || text.hasPrefix("0X"))
                    ? String(text.dropFirst(2)) : text
                let parsed = hex.isEmpty ? 0 : (Int(hex, radix: 16) ?? 0)
                preferences[keyPath: keyPath] = (1...0x99).contains(parsed) ? parsed : 0
            }
        )
    }
}
