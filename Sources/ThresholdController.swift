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
    private let applyLock = NSLock()
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

    func apply() async {
        applyLock.lock()
        guard !isApplying else { applyLock.unlock(); return }
        isApplying = true
        applyLock.unlock()
        defer {
            applyLock.lock()
            isApplying = false
            applyLock.unlock()
        }
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
    }

    /// Reapply periodik / setelah charger dicolok. Tidak menyentuh UI state,
    /// dan hanya untuk jalur ThinkVPC (helper eksternal tidak dipanggil berulang).
    func reapply(start: Int, stop: Int) async {
        guard selectedAdapterID == "thinkVPC", let adapter = selectedAdapter else { return }
        let prefs = preferences
        await Task.detached(priority: .utility) {
            _ = await adapter.write(start: start, stop: stop, preferences: prefs)
        }.value
    }

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
