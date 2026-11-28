import SwiftUI

/// Tab "Tentang": identitas aplikasi, versi, cek update, dan repo GitHub.
struct AboutView: View {
    @EnvironmentObject private var preferences: PreferencesStore

    private let repoURL = "https://github.com/Syuhadak27/SyStats"
    private let releaseURL = "https://github.com/Syuhadak27/SyStats/releases"

    private var version: String { UpdateController.shared.currentVersion }
    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                hero
                versionCard
                linksCard
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            if let icon = AppBranding.icon(preferences: preferences) {
                icon
                    .resizable()
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            Text("SyStats")
                .font(.largeTitle.weight(.bold))
            Text("Hackintosh power telemetry & charge threshold tooling")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private var versionCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Version", systemImage: "info.circle")

                HStack {
                    Text("App version").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(version).font(.body.weight(.semibold).monospacedDigit())
                }
                HStack {
                    Text("Build").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(buildNumber).font(.body.weight(.semibold).monospacedDigit())
                }
                HStack {
                    Text("Update feed").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("GitHub Releases · Sparkle 2")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Divider()

                Button {
                    UpdateController.shared.checkForUpdates()
                } label: {
                    Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Text("Update otomatis juga berjalan setiap 24 jam. Rilis terbaru diunduh dari GitHub Releases dan diverifikasi dengan tanda tangan Ed25519.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var linksCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Repository", systemImage: "link.circle")

                Link(destination: URL(string: repoURL)!) {
                    HStack {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("github.com/Syuhadak27/SyStats")
                                .font(.body.weight(.semibold))
                            Text("Source, issues, dan dokumentasi")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color(nsColor: .windowBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                Link(destination: URL(string: releaseURL)!) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Releases & changelog")
                                .font(.body.weight(.semibold))
                            Text("Unduh DMG/ZIP dan catatan versi")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color(nsColor: .windowBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                Text("MIT License with Attribution Requirement — © 2026 Syuhadak27. Modifikasi wajib mencantumkan repo ini.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
