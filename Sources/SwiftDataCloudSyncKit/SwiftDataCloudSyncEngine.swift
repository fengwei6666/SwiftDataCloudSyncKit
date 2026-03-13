import Foundation
import CoreData
import SwiftData
import Combine

public protocol CloudSyncSettingsStore: AnyObject {
    var isCloudSyncEnabled: Bool { get set }
}

public final class UserDefaultsCloudSyncSettingsStore: CloudSyncSettingsStore {
    private let defaults: UserDefaults
    private let key: String
    private let defaultValue: Bool

    public init(
        defaults: UserDefaults = .standard,
        key: String = "swiftDataCloudSyncEnabled",
        defaultValue: Bool = true
    ) {
        self.defaults = defaults
        self.key = key
        self.defaultValue = defaultValue
    }

    public var isCloudSyncEnabled: Bool {
        get {
            if defaults.object(forKey: key) == nil {
                return defaultValue
            }
            return defaults.bool(forKey: key)
        }
        set {
            defaults.set(newValue, forKey: key)
        }
    }
}

public final class InMemoryCloudSyncSettingsStore: CloudSyncSettingsStore {
    public var isCloudSyncEnabled: Bool

    public init(isCloudSyncEnabled: Bool) {
        self.isCloudSyncEnabled = isCloudSyncEnabled
    }
}

public enum CloudSyncMode {
    case disabled
    case enabled(cloudKitDatabase: ModelConfiguration.CloudKitDatabase)

    var cloudKitDatabase: ModelConfiguration.CloudKitDatabase? {
        switch self {
        case .disabled:
            return nil
        case .enabled(let database):
            return database
        }
    }
}

// Controls where business read/write context points to.
public enum DataAccessMode {
    // Recommended: business context always local; cloud is sync-only.
    case localOnly
    // Compatibility mode: business context switches to cloud when enabled.
    case switchWithCloudSync
}

public struct SwiftDataCloudSyncConfiguration {
    public typealias LocalToCloudSyncHandler = @Sendable (_ local: ModelContainer, _ cloud: ModelContainer) async throws -> Void

    public var schema: Schema
    public var localStoreName: String
    public var cloudStoreName: String
    public var cloudSyncMode: CloudSyncMode
    public var dataAccessMode: DataAccessMode
    public var settingsStore: CloudSyncSettingsStore
    public var localToCloudSyncHandler: LocalToCloudSyncHandler?
    public var logger: ((String) -> Void)?

    public init(
        schema: Schema,
        localStoreName: String = "LocalStore",
        cloudStoreName: String = "CloudStore",
        cloudSyncMode: CloudSyncMode = .enabled(cloudKitDatabase: .automatic),
        dataAccessMode: DataAccessMode = .localOnly,
        settingsStore: CloudSyncSettingsStore,
        localToCloudSyncHandler: LocalToCloudSyncHandler? = nil,
        logger: ((String) -> Void)? = nil
    ) {
        self.schema = schema
        self.localStoreName = localStoreName
        self.cloudStoreName = cloudStoreName
        self.cloudSyncMode = cloudSyncMode
        self.dataAccessMode = dataAccessMode
        self.settingsStore = settingsStore
        self.localToCloudSyncHandler = localToCloudSyncHandler
        self.logger = logger
    }
}

public final class SwiftDataCloudSyncEngine: ObservableObject {

    @Published public private(set) var isCloudSyncEnabled: Bool = false

    public let syncMonitor: CloudSyncMonitor

    private var configuration: SwiftDataCloudSyncConfiguration
    private var localContainer: ModelContainer?
    private var cloudContainer: ModelContainer?

    public init(configuration: SwiftDataCloudSyncConfiguration) {
        self.configuration = configuration
        self.syncMonitor = CloudSyncMonitor(logger: configuration.logger)
        self.isCloudSyncEnabled = configuration.settingsStore.isCloudSyncEnabled
        syncMonitor.startMonitoring()
        syncMonitor.setManualSyncHandler { [weak self] in
            guard let self else {
                throw SwiftDataCloudSyncEngineError.containerNotReady
            }
            try await self.performManualSync()
        }
    }

    public var isReady: Bool {
        localContainer != nil
    }

    // Business-facing context. In localOnly mode this is always local.
    public var modelContext: ModelContext {
        ModelContext(primaryReadWriteContainer)
    }

    // Explicit contexts for advanced scenarios.
    public var localModelContext: ModelContext {
        guard let localContainer else {
            fatalError("local container not ready")
        }
        return ModelContext(localContainer)
    }

    public var cloudModelContext: ModelContext? {
        guard let cloudContainer else { return nil }
        return ModelContext(cloudContainer)
    }

    public func setup() throws {
        let localConfig = ModelConfiguration(
            configuration.localStoreName,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        localContainer = try ModelContainer(for: configuration.schema, configurations: [localConfig])

        if shouldUseCloudContainer {
            try ensureCloudContainerReady()
        }

        refreshSyncMonitorBinding()
        log("engine setup complete")
    }

    public func setCloudSyncEnabled(_ enabled: Bool) async throws {
        guard enabled != isCloudSyncEnabled else { return }

        if enabled {
            guard configuration.cloudSyncMode.cloudKitDatabase != nil else {
                throw SwiftDataCloudSyncEngineError.cloudSyncNotAvailable
            }
            try ensureCloudContainerReady()
        }

        configuration.settingsStore.isCloudSyncEnabled = enabled
        isCloudSyncEnabled = enabled
        refreshSyncMonitorBinding()

        if enabled {
            try await performManualSync()
        }
    }

    public func updateConfiguration(_ update: (inout SwiftDataCloudSyncConfiguration) -> Void) {
        update(&configuration)
        isCloudSyncEnabled = configuration.settingsStore.isCloudSyncEnabled

        if shouldUseCloudContainer, cloudContainer == nil {
            try? ensureCloudContainerReady()
        }

        refreshSyncMonitorBinding()
    }

    public func stopMonitoring() {
        syncMonitor.stopMonitoring()
    }

    private var primaryReadWriteContainer: ModelContainer {
        switch configuration.dataAccessMode {
        case .localOnly:
            return localContainer!
        case .switchWithCloudSync:
            if shouldUseCloudContainer, let cloudContainer {
                return cloudContainer
            }
            return localContainer!
        }
    }

    private var shouldUseCloudContainer: Bool {
        isCloudSyncEnabled && configuration.cloudSyncMode.cloudKitDatabase != nil
    }

    private func ensureCloudContainerReady() throws {
        guard cloudContainer == nil else { return }
        guard let cloudDatabase = configuration.cloudSyncMode.cloudKitDatabase else {
            throw SwiftDataCloudSyncEngineError.cloudSyncNotAvailable
        }

        let cloudConfig = ModelConfiguration(
            configuration.cloudStoreName,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: cloudDatabase
        )
        cloudContainer = try ModelContainer(for: configuration.schema, configurations: [cloudConfig])
    }

    private func refreshSyncMonitorBinding() {
        guard let localContainer else { return }

        syncMonitor.setContainer(localContainer)

        if shouldUseCloudContainer, let cloudContainer {
            syncMonitor.setActiveStoreIdentifiers(storeIdentifiers(for: cloudContainer))
            syncMonitor.setAcceptsCloudEvents(true)
        } else {
            syncMonitor.setActiveStoreIdentifiers([])
            syncMonitor.setAcceptsCloudEvents(false)
        }
    }

    private func performManualSync() async throws {
        guard shouldUseCloudContainer else {
            throw SwiftDataCloudSyncEngineError.cloudSyncDisabled
        }
        guard let localContainer else {
            throw SwiftDataCloudSyncEngineError.containerNotReady
        }
        guard let cloudContainer else {
            throw SwiftDataCloudSyncEngineError.containerNotReady
        }
        guard let syncHandler = configuration.localToCloudSyncHandler else {
            throw SwiftDataCloudSyncEngineError.localToCloudSyncHandlerMissing
        }

        try await syncHandler(localContainer, cloudContainer)
    }

    private func storeIdentifiers(for container: ModelContainer) -> Set<String> {
        guard let persistentContainer = persistentContainer(from: container) else {
            return []
        }
        let stores = persistentContainer.persistentStoreCoordinator.persistentStores
        return Set(stores.map(\.identifier))
    }

    private func persistentContainer(from container: ModelContainer) -> NSPersistentContainer? {
        let mirror = Mirror(reflecting: container)
        for child in mirror.children {
            if let persistentContainer = child.value as? NSPersistentContainer {
                return persistentContainer
            }
        }
        if let superMirror = mirror.superclassMirror {
            for child in superMirror.children {
                if let persistentContainer = child.value as? NSPersistentContainer {
                    return persistentContainer
                }
            }
        }
        return nil
    }

    private func log(_ message: String) {
        configuration.logger?(message)
    }
}

public enum SwiftDataCloudSyncEngineError: LocalizedError {
    case cloudSyncNotAvailable
    case cloudSyncDisabled
    case localToCloudSyncHandlerMissing
    case containerNotReady

    public var errorDescription: String? {
        switch self {
        case .cloudSyncNotAvailable:
            return "Cloud sync is not available in current configuration"
        case .cloudSyncDisabled:
            return "Cloud sync is disabled"
        case .localToCloudSyncHandlerMissing:
            return "Local-to-cloud sync handler is not configured"
        case .containerNotReady:
            return "Container is not ready"
        }
    }
}
