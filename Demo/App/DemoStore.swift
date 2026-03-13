import Foundation
import SwiftData
import Combine
import SwiftDataCloudSyncKit

actor RetryFailureCounter {
    private var remainingFailures: Int

    init(remainingFailures: Int) {
        self.remainingFailures = remainingFailures
    }

    func shouldFail() -> Bool {
        if remainingFailures > 0 {
            remainingFailures -= 1
            return true
        }
        return false
    }
}

struct DemoSyncRunStats {
    var finishedAt: Date?
    var localCount: Int
    var inserted: Int
    var updated: Int
    var skipped: Int
    var deduplicated: Int
    var injectedCloudNewer: Bool
    var injectedCloudDuplicates: Int

    static let empty = DemoSyncRunStats(
        finishedAt: nil,
        localCount: 0,
        inserted: 0,
        updated: 0,
        skipped: 0,
        deduplicated: 0,
        injectedCloudNewer: false,
        injectedCloudDuplicates: 0
    )
}

actor DemoSyncDebugState {
    static let shared = DemoSyncDebugState()

    private var pendingCloudNewerConflict = false
    private var pendingCloudDuplicateInjection = false
    private var latestStats = DemoSyncRunStats.empty

    func requestCloudNewerConflict() {
        pendingCloudNewerConflict = true
    }

    func requestCloudDuplicateInjection() {
        pendingCloudDuplicateInjection = true
    }

    func consumePendingInjections() -> (cloudNewer: Bool, cloudDuplicates: Bool) {
        let payload = (pendingCloudNewerConflict, pendingCloudDuplicateInjection)
        pendingCloudNewerConflict = false
        pendingCloudDuplicateInjection = false
        return payload
    }

    func updateLatestStats(_ stats: DemoSyncRunStats) {
        latestStats = stats
    }

    func getLatestStats() -> DemoSyncRunStats {
        latestStats
    }
}

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
    @Published var offlineQueueCount = 0
    @Published var syncStats: DemoSyncRunStats = .empty
    @Published var logs: [String] = []

    private var engine: SwiftDataCloudSyncEngine?
    private var monitorCancellables = Set<AnyCancellable>()

    private let settingsStore = UserDefaultsCloudSyncSettingsStore(
        key: "demo.swiftDataCloudSyncEnabled",
        defaultValue: false
    )

    private let offlineQueue = OfflineOperationQueue(storageKey: "demo.offlineOperationQueue")
    private let retryExecutor = RetryExecutor(maxRetries: 3, retryDelay: 1.0)

    func setupEngine(cloudCapable: Bool) {
        do {
            engine?.stopMonitoring()
            monitorCancellables.removeAll()

            isCloudCapable = cloudCapable
            if !cloudCapable {
                settingsStore.isCloudSyncEnabled = false
            }

            let configuration = SwiftDataCloudSyncConfiguration(
                schema: Schema([DemoWork.self]),
                localStoreName: "DemoLocalStore",
                cloudStoreName: "DemoCloudStore",
                cloudSyncMode: cloudCapable ? .enabled(cloudKitDatabase: .automatic) : .disabled,
                dataAccessMode: .localOnly,
                settingsStore: settingsStore,
                localToCloudSyncHandler: { localContainer, cloudContainer in
                    try await DemoStore.syncLocalToCloud(
                        localContainer: localContainer,
                        cloudContainer: cloudContainer
                    )
                },
                logger: { [weak self] message in
                    Task { @MainActor in
                        self?.log("[Engine] \(message)")
                    }
                }
            )

            let newEngine = SwiftDataCloudSyncEngine(configuration: configuration)
            try newEngine.setup()
            engine = newEngine

            bindMonitor(newEngine.syncMonitor)
            isEngineReady = newEngine.isReady
            isCloudSyncEnabled = newEngine.isCloudSyncEnabled
            syncErrorMessage = nil

            reloadWorks()
            refreshOfflineQueueCount()
            refreshDiagnostics()
            refreshLatestSyncStats()
            log("Engine ready. cloudCapable=\(cloudCapable), cloudEnabled=\(isCloudSyncEnabled)")
        } catch {
            isEngineReady = false
            syncErrorMessage = error.localizedDescription
            log("Engine setup failed: \(error.localizedDescription)")
        }
    }

    func setCloudSyncEnabled(_ enabled: Bool) {
        guard let engine else {
            log("Engine not ready")
            return
        }

        if enabled && !isCloudCapable {
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
                    self.refreshLatestSyncStats()
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

    func triggerManualSync() {
        guard let engine else {
            log("Engine not ready")
            return
        }
        engine.syncMonitor.triggerSync()
        log("Manual sync triggered")
    }

    func addSampleWork() {
        guard let engine else {
            log("Engine not ready")
            return
        }

        let context = engine.modelContext
        let item = DemoWork(
            name: "Demo \(Int.random(in: 1000...9999))",
            notes: "Created at \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))"
        )

        do {
            context.insert(item)
            try context.save()
            reloadWorks()
            log("Inserted local work: \(item.id)")
        } catch {
            syncErrorMessage = error.localizedDescription
            refreshDiagnostics()
            log("Insert failed: \(error.localizedDescription)")
        }
    }

    func injectCloudNewerConflictAndSync() {
        guard isCloudSyncEnabled else {
            log("Enable cloud sync first before conflict injection")
            return
        }

        if works.isEmpty {
            addSampleWork()
        }

        Task {
            await DemoSyncDebugState.shared.requestCloudNewerConflict()
            await MainActor.run {
                self.log("Queued conflict injection: cloud newer than local")
                self.triggerManualSync()
            }
        }
    }

    func injectCloudDuplicatesAndSync() {
        guard isCloudSyncEnabled else {
            log("Enable cloud sync first before duplicate injection")
            return
        }

        if works.isEmpty {
            addSampleWork()
        }

        Task {
            await DemoSyncDebugState.shared.requestCloudDuplicateInjection()
            await MainActor.run {
                self.log("Queued injection: cloud duplicates for one id")
                self.triggerManualSync()
            }
        }
    }

    func reloadWorks() {
        guard let engine else {
            works = []
            return
        }

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

    func addOfflineOperation() {
        let operation = OfflineOperation(type: .update, entityID: UUID().uuidString)
        offlineQueue.addOperation(operation)
        refreshOfflineQueueCount()
        log("Added offline operation: \(operation.id)")
    }

    func clearOfflineOperations() {
        offlineQueue.clearAll()
        refreshOfflineQueueCount()
        log("Cleared offline operations")
    }

    func runRetryDemo() {
        Task {
            let counter = RetryFailureCounter(remainingFailures: 2)
            do {
                let result: String = try await retryExecutor.execute(operationId: "demo.retry") {
                    if await counter.shouldFail() {
                        throw NSError(domain: "DemoRetry", code: -1, userInfo: [NSLocalizedDescriptionKey: "Simulated transient error"])
                    }
                    return "retry-success"
                }
                await MainActor.run {
                    self.log("Retry demo result: \(result)")
                }
            } catch {
                await MainActor.run {
                    self.syncErrorMessage = error.localizedDescription
                    self.refreshDiagnostics()
                    self.log("Retry demo failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func refreshLatestSyncStats() {
        Task {
            let latest = await DemoSyncDebugState.shared.getLatestStats()
            await MainActor.run {
                self.syncStats = latest
            }
        }
    }

    private func bindMonitor(_ monitor: CloudSyncMonitor) {
        monitorCancellables.removeAll()

        monitor.$isSyncing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.isSyncing = value
                if !value {
                    self?.refreshLatestSyncStats()
                }
            }
            .store(in: &monitorCancellables)

        monitor.$syncProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.syncProgress = value
            }
            .store(in: &monitorCancellables)

        monitor.$lastSyncDate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.lastSyncDate = value
            }
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

    private func refreshOfflineQueueCount() {
        offlineQueueCount = offlineQueue.getPendingOperations().count
    }

    private func refreshDiagnostics() {
        let recommendations = SyncDiagnosticsAdvisor.recommendations(
            syncError: engine?.syncMonitor.syncError,
            localSyncErrorMessage: syncErrorMessage,
            cloudSyncEnabled: isCloudSyncEnabled
        )
        diagnostics = recommendations
    }

    private func log(_ text: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        logs.insert("[\(timestamp)] \(text)", at: 0)
        if logs.count > 200 {
            logs = Array(logs.prefix(200))
        }
    }

    private static func syncLocalToCloud(
        localContainer: ModelContainer,
        cloudContainer: ModelContainer
    ) async throws {
        let localContext = ModelContext(localContainer)
        let cloudContext = ModelContext(cloudContainer)

        let localItems = try localContext.fetch(FetchDescriptor<DemoWork>())
        let injections = await DemoSyncDebugState.shared.consumePendingInjections()

        var inserted = 0
        var updated = 0
        var skipped = 0
        var deduplicated = 0
        var injectedCloudDuplicates = 0

        if injections.cloudNewer, let local = localItems.first {
            let localID = local.id
            let descriptor = FetchDescriptor<DemoWork>(
                predicate: #Predicate { $0.id == localID },
                sortBy: [SortDescriptor(\DemoWork.updatedAt, order: .reverse)]
            )
            let existing = try cloudContext.fetch(descriptor)
            if let first = existing.first {
                first.updatedAt = local.updatedAt.addingTimeInterval(180)
                first.notes = "Injected cloud newer at \(Date())"
            } else {
                cloudContext.insert(
                    DemoWork(
                        id: local.id,
                        name: "CloudNewer-\(local.name)",
                        notes: "Injected cloud newer",
                        updatedAt: local.updatedAt.addingTimeInterval(180)
                    )
                )
            }
        }

        if injections.cloudDuplicates, let local = localItems.first {
            let duplicateOne = DemoWork(
                id: local.id,
                name: "CloudDup-1",
                notes: "Injected duplicate #1",
                updatedAt: local.updatedAt.addingTimeInterval(-180)
            )
            let duplicateTwo = DemoWork(
                id: local.id,
                name: "CloudDup-2",
                notes: "Injected duplicate #2",
                updatedAt: local.updatedAt.addingTimeInterval(-120)
            )
            cloudContext.insert(duplicateOne)
            cloudContext.insert(duplicateTwo)
            injectedCloudDuplicates = 2
        }

        for local in localItems {
            let id = local.id
            let descriptor = FetchDescriptor<DemoWork>(
                predicate: #Predicate { $0.id == id },
                sortBy: [SortDescriptor(\DemoWork.updatedAt, order: .reverse)]
            )
            let cloudItems = try cloudContext.fetch(descriptor)
            let cloudItem = cloudItems.first ?? DemoWork(
                id: local.id,
                name: local.name,
                notes: local.notes,
                updatedAt: local.updatedAt
            )

            if cloudItems.count > 1 {
                cloudItems.dropFirst().forEach { cloudContext.delete($0) }
                deduplicated += cloudItems.count - 1
            }

            if let newest = cloudItems.first, newest.updatedAt > local.updatedAt {
                skipped += 1
                continue
            }

            cloudItem.name = local.name
            cloudItem.notes = local.notes
            cloudItem.updatedAt = local.updatedAt

            if cloudItem.modelContext == nil {
                cloudContext.insert(cloudItem)
                inserted += 1
            } else {
                updated += 1
            }
        }

        if cloudContext.hasChanges {
            try cloudContext.save()
        }

        let stats = DemoSyncRunStats(
            finishedAt: Date(),
            localCount: localItems.count,
            inserted: inserted,
            updated: updated,
            skipped: skipped,
            deduplicated: deduplicated,
            injectedCloudNewer: injections.cloudNewer,
            injectedCloudDuplicates: injectedCloudDuplicates
        )

        await DemoSyncDebugState.shared.updateLatestStats(stats)
    }
}
