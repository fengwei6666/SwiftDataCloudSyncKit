import Foundation
import CoreData
import SwiftData
import CloudKit
import Combine

public final class CloudSyncMonitor: ObservableObject {

    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastSyncDate: Date?
    @Published public private(set) var syncError: Error?
    @Published public private(set) var syncProgress: Double = 0.0

    private var cloudEventObserver: NSObjectProtocol?
    private var manualSyncTimeoutTask: Task<Void, Never>?
    private var manualSyncHandler: (() async throws -> Void)?
    private weak var container: ModelContainer?
    private var activeStoreIdentifiers: Set<String> = []
    private var acceptsCloudEvents: Bool = true
    private let logger: ((String) -> Void)?

    public init(logger: ((String) -> Void)? = nil) {
        self.logger = logger
    }

    public func setContainer(_ container: ModelContainer) {
        self.container = container
        log("SyncMonitor bind container")
    }

    public func setManualSyncHandler(_ handler: @escaping () async throws -> Void) {
        manualSyncHandler = handler
    }

    public func setActiveStoreIdentifiers(_ identifiers: Set<String>) {
        activeStoreIdentifiers = identifiers
    }

    public func setAcceptsCloudEvents(_ enabled: Bool) {
        acceptsCloudEvents = enabled
    }

    public func startMonitoring() {
        guard cloudEventObserver == nil else { return }

        cloudEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleSyncEvent(notification)
            }
        }
    }

    public func stopMonitoring() {
        if let cloudEventObserver {
            NotificationCenter.default.removeObserver(cloudEventObserver)
        }
        cloudEventObserver = nil
        manualSyncTimeoutTask?.cancel()
        manualSyncTimeoutTask = nil
    }

    public func triggerSync() {
        syncError = nil
        isSyncing = true
        syncProgress = 0.0

        guard let manualSyncHandler else {
            syncError = CloudSyncMonitorError.syncHandlerNotConfigured
            isSyncing = false
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await manualSyncHandler()
                await self.handleManualSyncTriggered()
            } catch {
                await self.handleManualSyncFailed(error)
            }
        }
    }

    private func handleSyncEvent(_ notification: Notification) {
        guard let event = notification.userInfo?[
            NSPersistentCloudKitContainer.eventNotificationUserInfoKey
        ] as? NSPersistentCloudKitContainer.Event else {
            return
        }

        if !acceptsCloudEvents {
            return
        }

        if !activeStoreIdentifiers.isEmpty,
           !activeStoreIdentifiers.contains(event.storeIdentifier) {
            return
        }

        switch event.type {
        case .setup:
            isSyncing = false
            syncProgress = 0.0
        case .import, .export:
            if event.endDate == nil {
                isSyncing = true
                syncProgress = 0.5
            } else {
                finishSync(with: event)
            }
        @unknown default:
            break
        }
    }

    private func finishSync(with event: NSPersistentCloudKitContainer.Event) {
        manualSyncTimeoutTask?.cancel()
        manualSyncTimeoutTask = nil

        isSyncing = false
        syncProgress = event.succeeded ? 1.0 : 0.0

        if event.succeeded {
            lastSyncDate = event.endDate ?? Date()
            syncError = nil
        } else if let error = event.error {
            syncError = error
            log("sync failed: \(error.localizedDescription)")
        }
    }

    private func scheduleManualSyncTimeout() {
        manualSyncTimeoutTask?.cancel()
        manualSyncTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self else { return }
            await self.handleManualSyncTimeout()
        }
    }

    @MainActor
    private func handleManualSyncTriggered() {
        syncProgress = max(syncProgress, 0.1)
        scheduleManualSyncTimeout()
    }

    @MainActor
    private func handleManualSyncFailed(_ error: Error) {
        syncError = error
        isSyncing = false
        syncProgress = 0.0
    }

    @MainActor
    private func handleManualSyncTimeout() {
        guard isSyncing else { return }
        isSyncing = false
        syncProgress = 0.0
    }

    private func log(_ message: String) {
        logger?(message)
    }
}

public enum CloudSyncMonitorError: LocalizedError {
    case syncHandlerNotConfigured

    public var errorDescription: String? {
        switch self {
        case .syncHandlerNotConfigured:
            return "Sync handler is not configured"
        }
    }
}
