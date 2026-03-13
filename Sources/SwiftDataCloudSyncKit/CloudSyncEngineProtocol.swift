import Foundation
import SwiftData
import Combine

/// Common interface for sync engine implementations.
/// Provides Combine publishers as UIKit integration points.
@MainActor
public protocol CloudSyncEngine: AnyObject {
    var isCloudSyncEnabled: Bool { get }
    var isReady: Bool { get }
    /// Business-facing context. Stable across calls; recreated after container changes.
    var modelContext: ModelContext { get }
    var syncMonitor: CloudSyncMonitor { get }
    /// Emits the current container immediately on subscription, then again on every swap.
    var containerPublisher: AnyPublisher<ModelContainer, Never> { get }
    /// Emits the current cloud-sync-enabled state immediately, then on every toggle.
    var isCloudSyncEnabledPublisher: AnyPublisher<Bool, Never> { get }

    func setup() throws
    func setCloudSyncEnabled(_ enabled: Bool) async throws
    func stopMonitoring()
}
