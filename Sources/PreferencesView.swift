import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var preferences: PreferencesStore

    // TIDAK menyimpan/mengamati snapshot telemetri di sini. Live preview
    // dipindah ke subview tersendiri yang mengamati TelemetryStore, supaya
    // polling 2 detik tidak merender ulang seluruh halaman Preferences
    // (terutama TextField label yang sedang diketik).

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

    // MARK: - Menu bar editor

    private var previewCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "Menu bar items",
                    systemImage: "menubar.rectangle",
                    subtitle: "Pilih, ubah label bebas, dan atur urutan item menu bar atas"
                )

                // Preset cepat. Mengubah preset menimpa daftar item saat ini.
                Picker("Preset", selection: Binding(
                    get: { preferences.menuBarModeRaw },
                    set: { raw in
                        preferences.applyMenuBarPreset(MenuBarMode(rawValue: raw) ?? .automatic)
                    }
                )) {
                    ForEach(MenuBarMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                if preferences.menuBarItemsAreCustom {
                    Label("Custom items aktif — memilih preset akan menimpanya.", systemImage: "hand.draw")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                // Live preview diisolasi di subview agar update 2 detik tidak
                // merender ulang TextField/List di halaman ini.
                MenuBarPreviewView()

                HStack {
                    Text("Separator").font(.caption)
                    TextField("(spasi)", text: separatorBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 120)
                    Text("Label kosong = nilai saja (item tetap aktif).")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Daftar item: checkbox aktif, label bebas, drag untuk urutan.
                List {
                    ForEach(Array(preferences.menuBarItems.indices), id: \.self) { index in
                        let item = preferences.menuBarItems[index]
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.arrow.down.circle")
                                .foregroundStyle(.tertiary)
                                .help("Tarik baris untuk mengubah urutan")
                            Toggle("", isOn: itemBinding(at: index).enabled)
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                            Image(systemName: item.kind.symbol)
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            TextField("Label (kosong = sembunyikan)", text: itemBinding(at: index).label)
                                .textFieldStyle(.roundedBorder)
                            Spacer(minLength: 4)
                            LiveItemValue(kind: item.kind, enabled: item.enabled)
                            Button {
                                removeItem(item.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .help("Hapus item")
                        }
                        .opacity(item.enabled ? 1 : 0.55)
                    }
                    .onMove { indices, newOffset in
                        var items = preferences.menuBarItems
                        items.move(fromOffsets: indices, toOffset: newOffset)
                        preferences.menuBarItems = items
                        preferences.markMenuBarItemsCustom()
                    }
                    .onDelete { indices in
                        var items = preferences.menuBarItems
                        items.remove(atOffsets: indices)
                        preferences.menuBarItems = items
                        preferences.markMenuBarItemsCustom()
                    }
                }
                .listStyle(.plain)
                .frame(height: 210)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                }

                HStack {
                    Text("Tarik baris untuk mengubah urutan.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Menu {
                        ForEach(MenuBarItem.Kind.allCases) { kind in
                            Button {
                                addItem(kind)
                            } label: {
                                Label(kind.displayName, systemImage: kind.symbol)
                            }
                        }
                    } label: {
                        Label("Tambah item", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    Button("Reset ke preset") {
                        preferences.applyMenuBarPreset(preferences.menuBarMode)
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }

                Toggle("Compact text (sembunyikan semua label)", isOn: compactBinding)
                    .toggleStyle(.switch)
                Toggle("Show menu bar icon", isOn: iconBinding)
                    .toggleStyle(.switch)
                Text("Unavailable sensors render as “—”. The status item updates on the selected polling interval without blocking the main thread.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func addItem(_ kind: MenuBarItem.Kind) {
        var items = preferences.menuBarItems
        items.append(MenuBarItem(kind: kind))
        preferences.menuBarItems = items
        preferences.markMenuBarItemsCustom()
    }

    private func removeItem(_ id: UUID) {
        var items = preferences.menuBarItems
        items.removeAll { $0.id == id }
        preferences.menuBarItems = items
        preferences.markMenuBarItemsCustom()
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
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(
                        title: "Lokasi EFI",
                        systemImage: "folder.badge.gearshape",
                        subtitle: "Dipakai untuk pemeriksaan otomatis. File hanya dibaca, tidak diubah."
                    )
                    HStack {
                        TextField("Otomatis (/Volumes/EFI/EFI)", text: efiPathBinding)
                            .textFieldStyle(.roundedBorder)
                        Button("Choose…") {
                            if let url = FilePickers.chooseDirectory() {
                                preferences.efiFolderPath = url.path
                            }
                        }
                        Button("Periksa") { appState.scanEFI() }
                            .buttonStyle(.borderless)
                    }
                    if let root = appState.inspection.efiRoot {
                        Text("Terdeteksi: \(root.path)")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else {
                        Text("Belum terdeteksi otomatis. Pilih folder EFI bila perlu.")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Button("Reset all preferences") {
                    let domain = Bundle.main.bundleIdentifier ?? "com.systats.app"
                    UserDefaults.standard.removePersistentDomain(forName: domain)
                    appState.preferences.efiFolderPath = ""
                    appState.preferences.pollInterval = 2.0
                    appState.preferences.menuBarMode = .automatic
                    appState.preferences.menuBarItems = MenuBarItem.preset(for: .automatic)
                    appState.preferences.menuBarSeparator = " "
                    appState.preferences.menuBarItemsAreCustom = false
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
    private var separatorBinding: Binding<String> {
        Binding(
            get: { preferences.menuBarSeparator },
            set: {
                preferences.menuBarSeparator = $0
                preferences.markMenuBarItemsCustom()
            }
        )
    }

    /// Binding aman untuk satu item berdasarkan index. Perubahan langsung
    /// ditulis balik ke JSON preferences dan ditandai sebagai custom.
    private func itemBinding(at index: Int) -> (enabled: Binding<Bool>, label: Binding<String>) {
        let enabled = Binding<Bool>(
            get: { preferences.menuBarItems[index].enabled },
            set: { value in
                var items = preferences.menuBarItems
                guard items.indices.contains(index) else { return }
                items[index].enabled = value
                preferences.menuBarItems = items
                preferences.markMenuBarItemsCustom()
            }
        )
        let label = Binding<String>(
            get: { preferences.menuBarItems[index].label },
            set: { value in
                var items = preferences.menuBarItems
                guard items.indices.contains(index) else { return }
                items[index].label = value
                preferences.menuBarItems = items
                preferences.markMenuBarItemsCustom()
            }
        )
        return (enabled, label)
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
    private var efiPathBinding: Binding<String> {
        Binding(get: { preferences.efiFolderPath }, set: { preferences.efiFolderPath = $0 })
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

/// Live preview diisolasi supaya hanya tile ini yang render ulang tiap poll
/// 2 detik — bukan seluruh halaman Preferences yang sedang diedit user.
private struct MenuBarPreviewView: View {
    @EnvironmentObject private var telemetry: TelemetryStore
    @EnvironmentObject private var preferences: PreferencesStore

    var body: some View {
        let text = telemetry.snapshot.menuBarText(
            items: preferences.menuBarItems,
            separator: preferences.menuBarSeparator,
            compact: preferences.compactMenuBar
        )
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform.path.ecg").foregroundStyle(Color.accentColor)
                Text("Live preview").font(.caption.weight(.semibold))
                Spacer()
            }
            Text(text.isEmpty ? "—" : text)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                // Solid fill, bukan material: jauh lebih murah saat dirender
                // ulang tiap 2 detik.
                .background(Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Nilai live per kind. Dipisah supaya perubahan telemetri tidak merender
/// ulang baris TextField/checkbox di PreferencesView.
private struct LiveItemValue: View {
    @EnvironmentObject private var telemetry: TelemetryStore
    let kind: MenuBarItem.Kind
    let enabled: Bool

    var body: some View {
        Text(telemetry.snapshot.valueText(for: kind))
            .font(.caption.monospacedDigit())
            .foregroundStyle(enabled ? .primary : .secondary)
    }
}
