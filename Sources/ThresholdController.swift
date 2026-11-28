import Foundation
import Combine

/// Koordinator threshold: intent pengguna, pemilihan adapter, dan pelaporan jujur.
final class ThresholdController: ObservableObject {
    @Published var startPercent: Int
    @Published var stopPercent: Int
    @Published var selectedAdapterID: String
    @Published private(set) var lastResult: ThresholdOperationResult?
    @Published private(set) var confirmedConfiguration: ThresholdConfiguration?
    @Published private(set) var isApplying = false

    let adapters: [any ThresholdAdapting] = [
        ThinkVPCAdapter(), VirtualSMCAdapter(), ExternalHelperAdapter(),
    ]

    private let preferences: PreferencesStore
    private var isReapplying = false
    private var cancellables = Set<AnyCancellable>()

    init(preferences: PreferencesStore) {
        self.preferences = preferences
        self.startPercent = preferences.thresholdStart
        self.stopPercent = preferences.thresholdStop
        self.selectedAdapterID = preferences.selectedAdapterID

        $startPercent
            .dropFirst()
            .sink { [weak self] in self?.preferences.thresholdStart = $0 }
            .store(in: &cancellables)
        $stopPercent
            .dropFirst()
            .sink { [weak self] in self?.preferences.thresholdStop = $0 }
            .store(in: &cancellables)
        $selectedAdapterID
            .dropFirst()
            .sink { [weak self] in self?.preferences.selectedAdapterID = $0 }
            .store(in: &cancellables)
    }

    var selectedAdapter: (any ThresholdAdapting)? {
        adapters.first { $0.id == selectedAdapterID }
    }

    var validationMessage: String? {
        ThresholdValidation.message(start: startPercent, stop: stopPercent)
    }

    /// @MainActor: semua @Published diubah di main thread (sebelumnya diubah
    /// dari thread latar setelah `await` → "Publishing changes from background
    /// threads" dan UI bisa tidak ter-update). NSLock di konteks async juga
    /// dilarang di Swift 6, jadi flag `isApplying` cukup dijaga oleh main actor.
    @MainActor
    func apply() async {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        guard let adapter = selectedAdapter else {
            lastResult = ThresholdOperationResult(success: false, message: "Tidak ada adapter dipilih.")
            return
        }
        let result = await adapter.write(start: startPercent, stop: stopPercent, preferences: preferences)
        var confirmed: ThresholdConfiguration?
        if result.success, let readBack = await adapter.read(preferences: preferences) {
            confirmed = readBack
        }
        lastResult = result
        confirmedConfiguration = confirmed
        // Reapply otomatis baru aktif setelah pengguna sendiri berhasil menerapkan.
        if result.success && adapter.id == "thinkVPC" {
            preferences.thresholdAutoReapply = true
        }
    }

    /// Apakah timer/observer charger boleh menulis ulang threshold.
    var canAutoReapply: Bool {
        selectedAdapterID == "thinkVPC" && preferences.thresholdAutoReapply && !isApplying
    }

    /// Reapply periodik / setelah charger dicolok. Tidak menyentuh UI state,
    /// dan hanya untuk jalur ThinkVPC (helper eksternal tidak dipanggil berulang).
    ///
    /// @MainActor supaya state (@Published / preferences) dibaca di main thread;
    /// penulisan ke hardware tetap dijalankan di task latar. `isReapplying`
    /// mencegah tulisan menumpuk bila satu panggilan SMI/ACPI lebih lama dari
    /// interval timer (default 3 detik).
    @MainActor
    func reapply(start: Int, stop: Int) async {
        guard !isReapplying, canAutoReapply, let adapter = selectedAdapter else { return }
        isReapplying = true
        defer { isReapplying = false }
        let prefs = preferences
        await Task.detached(priority: .utility) {
            _ = await adapter.write(start: start, stop: stop, preferences: prefs)
        }.value
    }

    @MainActor
    func readFromAdapter() async {
        guard let adapter = selectedAdapter else {
            lastResult = ThresholdOperationResult(success: false, message: "Tidak ada adapter dipilih.")
            return
        }
        if let config = await adapter.read(preferences: preferences) {
            confirmedConfiguration = config
            lastResult = ThresholdOperationResult(
                success: true, verified: config.confirmedByAdapter,
                message: "Nilai threshold berhasil dibaca dari adapter.",
                details: ["Start \(config.startPercent)% · Stop \(config.stopPercent)%"]
            )
            return
        }
        if let description = await adapter.statusDescription(preferences: preferences) {
            lastResult = ThresholdOperationResult(
                success: true,
                message: "Status adapter terbaca (bukan konfirmasi persentase).",
                details: [description]
            )
            return
        }
        confirmedConfiguration = nil
        lastResult = ThresholdOperationResult(
            success: false,
            message: "Adapter tidak bisa membaca nilai threshold.",
            details: ["GUI menampilkan nilai yang diinginkan, bukan keadaan hardware yang terkonfirmasi."]
        )
    }
}
