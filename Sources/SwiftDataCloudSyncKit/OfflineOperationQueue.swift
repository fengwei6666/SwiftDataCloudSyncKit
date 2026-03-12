import Foundation

public protocol OfflineOperationStorage {
    func loadData(forKey key: String) -> Data?
    func saveData(_ data: Data, forKey key: String)
}

public final class UserDefaultsOfflineOperationStorage: OfflineOperationStorage {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadData(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    public func saveData(_ data: Data, forKey key: String) {
        defaults.set(data, forKey: key)
    }
}

public struct OfflineOperation: Codable, Equatable {
    public enum OperationType: String, Codable {
        case create
        case update
        case delete
    }

    public let id: String
    public let type: OperationType
    public let entityID: String
    public let timestamp: Date
    public let payload: Data?

    public init(
        id: String = UUID().uuidString,
        type: OperationType,
        entityID: String,
        timestamp: Date = Date(),
        payload: Data? = nil
    ) {
        self.id = id
        self.type = type
        self.entityID = entityID
        self.timestamp = timestamp
        self.payload = payload
    }
}

public final class OfflineOperationQueue {

    private let storage: OfflineOperationStorage
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var pendingOperations: [OfflineOperation] = []

    public init(
        storage: OfflineOperationStorage = UserDefaultsOfflineOperationStorage(),
        storageKey: String = "offlineOperationQueue"
    ) {
        self.storage = storage
        self.storageKey = storageKey
        loadFromStorage()
    }

    public func addOperation(_ operation: OfflineOperation) {
        pendingOperations.append(operation)
        saveToStorage()
    }

    public func getPendingOperations() -> [OfflineOperation] {
        pendingOperations
    }

    public func clearOperation(id: String) {
        pendingOperations.removeAll { $0.id == id }
        saveToStorage()
    }

    public func clearAll() {
        pendingOperations.removeAll()
        saveToStorage()
    }

    private func saveToStorage() {
        guard let data = try? encoder.encode(pendingOperations) else {
            return
        }
        storage.saveData(data, forKey: storageKey)
    }

    private func loadFromStorage() {
        guard let data = storage.loadData(forKey: storageKey),
              let decoded = try? decoder.decode([OfflineOperation].self, from: data) else {
            pendingOperations = []
            return
        }
        pendingOperations = decoded
    }
}
