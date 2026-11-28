import SwiftUI

/// Kartu dengan latar SOLID.
///
/// Dulu memakai `NSVisualEffectView(.behindWindow)` di setiap kartu (5+ blur
/// sekaligus) + `.ultraThinMaterial`. Di Hackintosh (GPU tanpa akselerasi penuh)
/// blur "behind window" dikomposit ulang di CPU pada setiap frame scroll/resize
/// dan setiap polling — itu penyebab utama UI terasa berat dan lambat respons.
/// Warna solid + garis tepi tipis tampil hampir sama dan hampir tanpa biaya.
struct Card<Content: View>: View {
    let content: Content
    var padding: CGFloat = 16

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

struct SectionHeader: View {
    let title: String
    let systemImage: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

struct StatusBadge: View {
    let title: String
    let color: Color
    var symbol: String?

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol) }
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.16), in: Capsule())
        .foregroundStyle(color)
        .overlay {
            Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1)
        }
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var detail: String?
    var accent: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        // Kartu memakai controlBackgroundColor; tile memakai windowBackgroundColor
        // agar tetap kontras di mode terang maupun gelap.
        .background(Color(nsColor: .windowBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct DiagnosticsList: View {
    let messages: [String]
    var emptyMessage: String = "No diagnostics. All requested sensors are available."

    var body: some View {
        if messages.isEmpty {
            Label(emptyMessage, systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                // id = offset: pesan yang kembar tidak lagi membuat ID duplikat.
                ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}
