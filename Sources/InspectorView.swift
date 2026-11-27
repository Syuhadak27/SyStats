import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""

    private var inspection: EFIInspection { appState.inspection }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                folderCard
                filesCard
                HStack(alignment: .top, spacing: 16) {
                    kextCard
                    capabilityCard
                }
            }
            .padding(20)
        }
        .onAppear { if inspection.files.isEmpty { appState.scanEFI() } }
    }

    private var folderCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "EFI folder", systemImage: "folder.badge.gearshape", subtitle: "Read-only inspection — no .aml/.dsl file is ever modified")
                HStack {
                    TextField("/Volumes/EFI/EFI", text: Binding(
                        get: { appState.preferences.efiFolderPath },
                        set: { appState.preferences.efiFolderPath = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Button("Choose…") {
                        if let url = FilePickers.chooseDirectory() {
                            appState.preferences.efiFolderPath = url.path
                        }
                    }
                    Button {
                        appState.scanEFI()
                    } label: {
                        Label(appState.isScanning ? "Scanning…" : "Scan", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.isScanning)
                }
                if let root = inspection.efiRoot {
                    Label("EFI root: \(root.path)", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                if !inspection.acpiDirectories.isEmpty {
                    Text("ACPI folders: \(inspection.acpiDirectories.map(\.path).joined(separator: " · "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                DiagnosticsList(messages: inspection.diagnostics, emptyMessage: "EFI/ACPI folders are readable.")
            }
        }
    }

    private var filesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "ACPI tables",
                    systemImage: "doc.text.magnifyingglass",
                    subtitle: "\(inspection.files.count) file(s) · \(inspection.totalFindings) token(s) detected"
                )
                TextField("Filter files or findings", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                let files = filteredFiles
                if files.isEmpty {
                    ContentUnavailablePlaceholder(text: "No matching ACPI files found in the selected EFI folder.")
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 8) {
                            ForEach(files) { file in fileRow(file) }
                        }
                    }
                    .frame(maxHeight: 320)
                }
            }
        }
    }

    private func fileRow(_ file: ACPIFileInfo) -> some View {
        DisclosureGroup {
            if let error = file.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if file.findings.isEmpty {
                Text("No battery / EC / thermal / fan / SMC tokens detected.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(file.findings) { finding in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: categorySymbol(finding.category))
                            .foregroundStyle(categoryColor(finding.category))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(finding.name)
                                .font(.caption.weight(.semibold))
                            Text("\(finding.origin.rawValue) · \(finding.detail)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: file.fileExtension == "aml" ? "doc.fill.badge.ellipsis" : "doc.text")
                    .foregroundStyle(file.fileExtension == "aml" ? Color.blue : Color.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.caption.weight(.semibold))
                    Text(headerSummary(for: file))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let signature = file.tableSignature {
                    StatusBadge(title: signature, color: .blue)
                }
                StatusBadge(
                    title: file.isReadable ? "Readable" : "Unreadable",
                    color: file.isReadable ? .green : .red
                )
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var kextCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Kext compatibility", systemImage: "puzzlepiece.extension", subtitle: "Enabled state read from config.plist")
                ForEach(inspection.kexts) { kext in
                    HStack(spacing: 8) {
                        Image(systemName: kext.isEnabled == true ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(kext.isEnabled == true ? Color.green : Color.secondary)
                        Text(kext.name)
                            .font(.caption.weight(.medium))
                        Spacer(minLength: 0)
                        Text(kext.stateLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if inspection.kexts.isEmpty {
                    Text("No EFI folder selected.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var capabilityCard: some View {
        let capability = inspection.capability
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Threshold write status", systemImage: "lock.shield", subtitle: "Runtime capability — separate from the read-only audit above")
                StatusBadge(
                    title: capability.status.label,
                    color: capability.status == .available ? .green : (capability.status == .restricted ? .orange : .gray),
                    symbol: capability.status == .available ? "checkmark.shield" : "lock.shield"
                )
                Text(capability.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(capability.evidence, id: \.self) { item in
                    Label(item, systemImage: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let privileges = capability.requiredPrivileges {
                    Text("Privileges: \(privileges)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Divider()
                Text("An AML method on disk only proves a definition exists. macOS blocks direct user-space ACPI EC writes; a kext user client (YogaSMC ThinkVPC → BCCS/BCSS) or a supplied helper is required. Failed writes are reported, never masked.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button("Open Dashboard") { appState.openFullGUI() }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var filteredFiles: [ACPIFileInfo] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return inspection.files }
        return inspection.files.filter { file in
            file.name.localizedCaseInsensitiveContains(needle)
                || file.findings.contains { $0.searchText.localizedCaseInsensitiveContains(needle) }
        }
    }

    private func headerSummary(for file: ACPIFileInfo) -> String {
        var parts: [String] = []
        if let signature = file.tableSignature { parts.append(signature) }
        if let length = file.tableLength { parts.append("\(length) B") }
        parts.append("\(file.sizeBytes) B on disk")
        return parts.joined(separator: " · ") + " — " + file.categorySummary
    }

    private func categoryColor(_ category: ACPICategory) -> Color {
        switch category {
        case .battery: return .green
        case .embeddedController: return .blue
        case .thermal: return .red
        case .fan: return .orange
        case .smc: return .purple
        case .power: return .cyan
        case .other: return .secondary
        }
    }

    private func categorySymbol(_ category: ACPICategory) -> String {
        category.symbolName
    }
}

struct ContentUnavailablePlaceholder: View {
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
    }
}
