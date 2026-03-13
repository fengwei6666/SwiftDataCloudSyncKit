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
    /// Phase-based estimate derived from CloudKit event lifecycle.
    @Published public private(set) var syncProgress: Double = 0.0

    private var cloudEventObserver: NSObjectProtocol?
    private var acceptsCloudEvents: Bool = false
    private var activeEventPhases: [String: SyncPhase] = [:]
    private var completedPhasesInCycle: Set<SyncPhase> = []
    private let logger: ((String) -> Void)?
    private let cloudEventFilter: ((String) -> Bool)?

    private enum SyncPhase: Int {
        case setup = 0
        case importData = 1
        case exportData = 2

        var inFlightFloor: Double {
            switch self {
            case .setup:
                return 0.10
            case .importData:
                return 0.45
            case .exportData:
                return 0.75
            }
        }

        var completionValue: Double {
            switch self {
            case .setup:
                return 0.25
            case .importData:
                return 0.65
            case .exportData:
                return 0.90
            }
        }
    }

    public init(
        logger: ((String) -> Void)? = nil,
        cloudEventFilter: ((String) -> Bool)? = nil
    ) {
        self.logger = logger
        self.cloudEventFilter = cloudEventFilter
    }

    public func setContainer(_ container: ModelContainer) {
        resetActiveSyncState()
        log("SyncMonitor bind container")
    }

    public func setAcceptsCloudEvents(_ enabled: Bool) {
        acceptsCloudEvents = enabled
        if !enabled {
            resetActiveSyncState()
        }
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
        if let cloudEventFilter, !cloudEventFilter(event.storeIdentifier) { return }
        guard let phase = phase(for: event.type) else { return }

        let eventKey = event.identifier.uuidString
        if event.endDate == nil {
            if activeEventPhases.isEmpty {
                completedPhasesInCycle.removeAll()
                syncError = nil
            }
            activeEventPhases[eventKey] = phase
            isSyncing = true
            syncProgress = estimatedInFlightProgress()
            return
        }

        activeEventPhases.removeValue(forKey: eventKey)
        completedPhasesInCycle.insert(phase)

        if event.succeeded {
            lastSyncDate = event.endDate ?? Date()
        } else if let error = event.error {
            syncError = error
            log("sync failed: \(error.localizedDescription)")
        }

        if activeEventPhases.isEmpty {
            isSyncing = false
            syncProgress = event.succeeded ? 1.0 : max(0.0, estimatedCompletedProgress() - 0.25)
            completedPhasesInCycle.removeAll()
        } else {
            syncProgress = estimatedInFlightProgress()
        }
    }

    private func phase(for type: NSPersistentCloudKitContainer.EventType) -> SyncPhase? {
        switch type {
        case .setup:
            return .setup
        case .import:
            return .importData
        case .export:
            return .exportData
        @unknown default:
            return nil
        }
    }

    private func estimatedInFlightProgress() -> Double {
        var progress = estimatedCompletedProgress()
        for phase in activeEventPhases.values {
            progress = max(progress, phase.inFlightFloor)
        }
        return min(progress, 0.95)
    }

    private func estimatedCompletedProgress() -> Double {
        var progress = 0.0
        for phase in completedPhasesInCycle {
            progress = max(progress, phase.completionValue)
        }
        return progress
    }

    private func resetActiveSyncState() {
        activeEventPhases.removeAll()
        completedPhasesInCycle.removeAll()
        isSyncing = false
        syncProgress = 0.0
    }

    private func log(_ message: String) {
        logger?(message)
    }
}
