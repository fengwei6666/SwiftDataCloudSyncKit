import Foundation
import SwiftData
import Combine
import SwiftDataCloudSyncKit

@MainActor
final class DemoStore: ObservableObject {

    @Published var isEngineReady = false
    @Published var isCloudCapable = false
    @Published var isCloudSyncEnabled = false

    @Published var works: [DemoWork] = []

    @Published var isSyncing = false
    @Published var syncProgress: Double = 0
    @Published var lastSyncDate: Date?
    @Published var syncErrorMessage: String?

    @Published var diagnostics: [String] = []
    @Published var logs: [String] = []

    private var engine: NativeCloudSyncEngine?
    private var monitorCancellables = Set<AnyCancellable>()

    private let settingsStore = UserDefaultsCloudSyncSettingsStore(
        key: "demo.nativeCloudSyncEnabled",
        defaultValue: false
    )

    func setupEngine(cloudCapable: Bool) {
        do {
            engine?.stopMonitoring()
            monitorCancellables.removeAll()

            isCloudCapable = cloudCapable
            if !cloudCapable {
                settingsStore.isCloudSyncEnabled = false
            }

            let configuration = NativeCloudSyncConfiguration(
                syncedTypes: [DemoWork.self],
                cloudSyncMode: cloudCapable ? .enabled(cloudKitDatabase: .automatic) : .disabled,
                settingsStore: settingsStore,
                logger: { [weak self] message in
                    Task { @MainActor in self?.log("[Engine] \(message)") }
                }
            )

            let newEngine = NativeCloudSyncEngine(configuration: configuration)
            try newEngine.setup()
            engine = newEngine

            bindMonitor(newEngine.syncMonitor)
            isEngineReady = newEngine.isReady
            isCloudSyncEnabled = newEngine.isCloudSyncEnabled
            syncErrorMessage = nil

            reloadWorks()
            refreshDiagnostics()
            log("Engine ready. cloudCapable=\(cloudCapable), cloudEnabled=\(isCloudSyncEnabled)")
        } catch {
            isEngineReady = false
            syncErrorMessage = error.localizedDescription
            log("Engine setup failed: \(error.localizedDescription)")
        }
    }

    func setCloudSyncEnabled(_ enabled: Bool) {
        guard let engine else { log("Engine not ready"); return }
        guard !enabled || isCloudCapable else {
            log("CloudKit capability is disabled in current mode")
            return
        }
        Task {
            do {
                try await engine.setCloudSyncEnabled(enabled)
                await MainActor.run {
                    self.isCloudSyncEnabled = engine.isCloudSyncEnabled
                    self.syncErrorMessage = nil
                    self.refreshDiagnostics()
                    self.log("Cloud sync switched to \(self.isCloudSyncEnabled)")
                }
            } catch {
                await MainActor.run {
                    self.syncErrorMessage = error.localizedDescription
                    self.refreshDiagnostics()
                    self.log("Cloud switch failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func addSampleWork() {
        guard let engine else { log("Engine not ready"); return }
        let context = engine.modelContext
        let item = DemoWork(
            name: "Demo \(Int.random(in: 1000...9999))",
            notes: "Created at \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))"
        )
        do {
            context.insert(item)
            try context.save()
            reloadWorks()
            log("Inserted work: \(item.id)")
        } catch {
            syncErrorMessage = error.localizedDescription
            refreshDiagnostics()
            log("Insert failed: \(error.localizedDescription)")
        }
    }

    func reloadWorks() {
        guard let engine else { works = []; return }
        do {
            let descriptor = FetchDescriptor<DemoWork>(
                sortBy: [SortDescriptor(\DemoWork.updatedAt, order: .reverse)]
            )
            works = try engine.modelContext.fetch(descriptor)
            log("Reloaded works count=\(works.count)")
        } catch {
            syncErrorMessage = error.localizedDescription
            refreshDiagnostics()
            log("Reload failed: \(error.localizedDescription)")
        }
    }

    private func bindMonitor(_ monitor: CloudSyncMonitor) {
        monitorCancellables.removeAll()

        monitor.$isSyncing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isSyncing = $0 }
            .store(in: &monitorCancellables)

        monitor.$syncProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.syncProgress = $0 }
            .store(in: &monitorCancellables)

        monitor.$lastSyncDate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.lastSyncDate = $0 }
            .store(in: &monitorCancellables)

        monitor.$syncError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.syncErrorMessage = error?.localizedDescription
                self?.refreshDiagnostics()
                if let text = error?.localizedDescription {
                    self?.log("Sync error: \(text)")
                }
            }
            .store(in: &monitorCancellables)
    }

    private func refreshDiagnostics() {
        diagnostics = SyncDiagnosticsAdvisor.recommendations(
            syncError: engine?.syncMonitor.syncError,
            localSyncErrorMessage: syncErrorMessage,
            cloudSyncEnabled: isCloudSyncEnabled
        )
    }

    private func log(_ text: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        logs.insert("[\(timestamp)] \(text)", at: 0)
        if logs.count > 200 { logs = Array(logs.prefix(200)) }
    }
}
