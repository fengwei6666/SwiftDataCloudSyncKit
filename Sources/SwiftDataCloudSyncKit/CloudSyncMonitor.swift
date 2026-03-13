import Foundation
import CoreData
import SwiftData
import CloudKit
import Combine

@MainActor
public final class CloudSyncMonitor: ObservableObject {

    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastSyncDate: Date?
    @Published public private(set) var syncError: Error?
    @Published public private(set) var syncProgress: Double = 0.0

    private var cloudEventObserver: NSObjectProtocol?
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
    }

    private func handleSyncEvent(_ notification: Notification) {
        guard acceptsCloudEvents else { return }
        guard let event = notification.userInfo?[
            NSPersistentCloudKitContainer.eventNotificationUserInfoKey
        ] as? NSPersistentCloudKitContainer.Event else { return }

        if !activeStoreIdentifiers.isEmpty,
           !activeStoreIdentifiers.contains(event.storeIdentifier) {
            return
        }

        switch event.type {
        case .setup:
            break
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

    private func log(_ message: String) {
        logger?(message)
    }
}
