import Foundation
import SwiftData

// MARK: - Settings Store

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
            if defaults.object(forKey: key) == nil { return defaultValue }
            return defaults.bool(forKey: key)
        }
        set { defaults.set(newValue, forKey: key) }
    }
}

public final class InMemoryCloudSyncSettingsStore: CloudSyncSettingsStore {
    public var isCloudSyncEnabled: Bool

    public init(isCloudSyncEnabled: Bool) {
        self.isCloudSyncEnabled = isCloudSyncEnabled
    }
}

// MARK: - Sync Mode

public enum CloudSyncMode {
    case disabled
    case enabled(cloudKitDatabase: ModelConfiguration.CloudKitDatabase)

    var cloudKitDatabase: ModelConfiguration.CloudKitDatabase? {
        switch self {
        case .disabled: return nil
        case .enabled(let database): return database
        }
    }
}
