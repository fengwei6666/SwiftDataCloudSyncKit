import Foundation

public actor RetryExecutor {

    public static let shared = RetryExecutor()

    private var retryCount: [String: Int] = [:]
    private let maxRetries: Int
    private let retryDelay: TimeInterval

    public init(maxRetries: Int = 3, retryDelay: TimeInterval = 5.0) {
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
    }

    public func execute<T>(
        operationId: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let currentRetry = retryCount[operationId] ?? 0

        do {
            let result = try await operation()
            retryCount.removeValue(forKey: operationId)
            return result
        } catch {
            if currentRetry < maxRetries {
                retryCount[operationId] = currentRetry + 1
                try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                return try await execute(operationId: operationId, operation: operation)
            }

            retryCount.removeValue(forKey: operationId)
            throw error
        }
    }
}
