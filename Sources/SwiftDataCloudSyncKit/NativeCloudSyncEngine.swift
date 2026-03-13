import Foundation
import SwiftData
import Combine

// MARK: - Error

public enum CloudSyncEngineError: LocalizedError {
    case cloudSyncNotAvailable

    public var errorDescription: String? {
        switch self {
        case .cloudSyncNotAvailable:
            return "Cloud sync is not available in current configuration"
        }
    }
}

// MARK: - Configuration

/// Configuration for NativeCloudSyncEngine's single-container strategy.
/// CloudKit sync is managed natively by the system; no manual sync handler is needed.
///
/// **All models sync (simple case):**
/// ```swift
/// NativeCloudSyncConfiguration(
///     syncedTypes: [Post.self, UserProfile.self],
///     settingsStore: settingsStore
/// )
/// ```
///
/// **Partial sync — `Draft` stays on-device:**
/// ```swift
/// NativeCloudSyncConfiguration(
///     syncedTypes: [Post.self, UserProfile.self],
///     localOnlyTypes: [Draft.self],
///     settingsStore: settingsStore
/// )
/// ```
/// Both type groups share one `ModelContext`; routing to the correct SQLite store is
/// handled transparently by SwiftData.
public struct NativeCloudSyncConfiguration {
    /// Model types that participate in CloudKit sync.
    public var syncedTypes: [any PersistentModel.Type]
    /// Store file name for synced models.
    public var cloudStoreName: String
    /// `.disabled` or `.enabled(cloudKitDatabase:)`.
    public var cloudSyncMode: CloudSyncMode
    /// Model types stored on-device only, never uploaded to CloudKit. Defaults to empty.
    public var localOnlyTypes: [any PersistentModel.Type]
    /// Store file name for local-only models. Only used when `localOnlyTypes` is non-empty.
    public var localStoreName: String
    /// Persists the cloud-sync toggle across app launches.
    public var settingsStore: CloudSyncSettingsStore
    /// Optional logger for engine lifecycle messages.
    public var logger: ((String) -> Void)?
    /// Optional CloudKit event filter by `storeIdentifier`.
    /// Use this when your app has multiple CloudKit-backed containers in-process.
    public var cloudEventFilter: ((String) -> Bool)?

    public init(
        syncedTypes: [any PersistentModel.Type],
        cloudStoreName: String = "NativeCloudStore",
        cloudSyncMode: CloudSyncMode = .enabled(cloudKitDatabase: .automatic),
        localOnlyTypes: [any PersistentModel.Type] = [],
        localStoreName: String = "NativeLocalStore",
        settingsStore: CloudSyncSettingsStore,
        logger: ((String) -> Void)? = nil,
        cloudEventFilter: ((String) -> Bool)? = nil
    ) {
        self.syncedTypes = syncedTypes
        self.cloudStoreName = cloudStoreName
        self.cloudSyncMode = cloudSyncMode
        self.localOnlyTypes = localOnlyTypes
        self.localStoreName = localStoreName
        self.settingsStore = settingsStore
        self.logger = logger
        self.cloudEventFilter = cloudEventFilter
    }
}

// MARK: - Engine

/// Single-container sync engine that leverages SwiftData's native CloudKit integration.
///
/// **How toggling works:** CloudKit sync is activated at container creation time via
/// `cloudKitDatabase: .automatic`. There is no public API to pause it on an existing
/// container. Toggling therefore recreates the container pointing at the same SQLite
/// file — data is fully preserved, and CloudKit performs an incremental diff on next
/// sync rather than a full re-upload.
///
/// **SwiftUI integration:**
/// ```swift
/// @StateObject var engine = NativeCloudSyncEngine(configuration: ...)
///
/// var body: some Scene {
///     WindowGroup {
///         Group {
///             if let container = engine.container {
///                 ContentView()
///                     .modelContainer(container)
///                     .id(ObjectIdentifier(container))  // force subtree rebuild on swap
///             } else {
///                 ProgressView()
///             }
///         }
///         .environmentObject(engine)
///         .task { try? engine.setup() }
///     }
/// }
/// ```
///
/// **UIKit integration:**
/// ```swift
/// engine.containerPublisher
///     .receive(on: DispatchQueue.main)
///     .sink { [weak self] container in self?.didSwapContainer(container) }
///     .store(in: &cancellables)
/// ```
@MainActor
public final class NativeCloudSyncEngine: ObservableObject, CloudSyncEngine {

    // MARK: Published state

    @Published public private(set) var isCloudSyncEnabled: Bool
    /// Current model container. `nil` until `setup()` completes.
    @Published public private(set) var container: ModelContainer?

    // MARK: CloudSyncEngine

    public let syncMonitor: CloudSyncMonitor

    public var isReady: Bool { container != nil }

    public var modelContext: ModelContext? {
        if let ctx = _modelContext { return ctx }
        guard let container else { return nil }
        let ctx = ModelContext(container)
        _modelContext = ctx
        return ctx
    }

    public var containerPublisher: AnyPublisher<ModelContainer, Never> {
        $container.compactMap { $0 }.eraseToAnyPublisher()
    }

    public var isCloudSyncEnabledPublisher: AnyPublisher<Bool, Never> {
        $isCloudSyncEnabled.eraseToAnyPublisher()
    }

    // MARK: Private state

    private var configuration: NativeCloudSyncConfiguration
    private var _modelContext: ModelContext?

    // MARK: Init

    public init(configuration: NativeCloudSyncConfiguration) {
        self.configuration = configuration
        self.syncMonitor = CloudSyncMonitor(
            logger: configuration.logger,
            cloudEventFilter: configuration.cloudEventFilter
        )
        self.isCloudSyncEnabled = configuration.settingsStore.isCloudSyncEnabled
        syncMonitor.startMonitoring()
    }

    // MARK: Setup

    public func setup() throws {
        container = try Self.makeContainer(configuration: configuration,
                                           cloudEnabled: isCloudSyncEnabled)
        _modelContext = nil
        refreshSyncMonitorBinding()
        log("setup complete, cloudEnabled=\(isCloudSyncEnabled)")
    }

    // MARK: Toggle

    public func setCloudSyncEnabled(_ enabled: Bool) throws {
        guard enabled != isCloudSyncEnabled else { return }
        if enabled, configuration.cloudSyncMode.cloudKitDatabase == nil {
            throw CloudSyncEngineError.cloudSyncNotAvailable
        }
        container = try Self.makeContainer(configuration: configuration, cloudEnabled: enabled)
        _modelContext = nil
        configuration.settingsStore.isCloudSyncEnabled = enabled
        isCloudSyncEnabled = enabled
        refreshSyncMonitorBinding()
        log("cloud sync \(enabled ? "enabled" : "disabled"), container recreated")
    }

    // MARK: Stop

    public func stopMonitoring() {
        syncMonitor.stopMonitoring()
    }

    // MARK: Private helpers

    private static func makeContainer(
        configuration: NativeCloudSyncConfiguration,
        cloudEnabled: Bool
    ) throws -> ModelContainer {
        let cloudDB: ModelConfiguration.CloudKitDatabase = cloudEnabled
            ? (configuration.cloudSyncMode.cloudKitDatabase ?? .none)
            : .none
        let cloudConfig = ModelConfiguration(
            configuration.cloudStoreName,
            schema: Schema(configuration.syncedTypes),
            isStoredInMemoryOnly: false,
            cloudKitDatabase: cloudDB
        )

        let allTypes = configuration.syncedTypes + configuration.localOnlyTypes

        guard !configuration.localOnlyTypes.isEmpty else {
            return try ModelContainer(for: Schema(allTypes), configurations: [cloudConfig])
        }

        let localConfig = ModelConfiguration(
            configuration.localStoreName,
            schema: Schema(configuration.localOnlyTypes),
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: Schema(allTypes), configurations: [cloudConfig, localConfig])
    }

    private func refreshSyncMonitorBinding() {
        guard let container else { return }
        syncMonitor.setContainer(container)
        syncMonitor.setAcceptsCloudEvents(isCloudSyncEnabled && configuration.cloudSyncMode.cloudKitDatabase != nil)
    }

    private func log(_ message: String) {
        configuration.logger?(message)
    }
}
