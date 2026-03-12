import Foundation
import CloudKit

public enum CloudSyncError: Error, LocalizedError {
    case networkUnavailable
    case quotaExceeded
    case authenticationFailed
    case serverError
    case unknown(Error)

    public var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "Network is unavailable"
        case .quotaExceeded:
            return "iCloud storage quota exceeded"
        case .authenticationFailed:
            return "iCloud account is not authenticated"
        case .serverError:
            return "Cloud service temporarily unavailable"
        case .unknown(let error):
            return "Sync failed: \(error.localizedDescription)"
        }
    }

    public static func from(_ error: Error) -> CloudSyncError {
        if let ckError = error as? CKError {
            switch ckError.code {
            case .networkUnavailable, .networkFailure:
                return .networkUnavailable
            case .quotaExceeded:
                return .quotaExceeded
            case .notAuthenticated:
                return .authenticationFailed
            case .serverResponseLost, .serviceUnavailable:
                return .serverError
            default:
                return .unknown(error)
            }
        }
        return .unknown(error)
    }
}

public enum SyncIssueKind: String {
    case network
    case quota
    case authentication
    case server
    case unknown
}

public struct SyncDiagnosticsAdvisor {

    public static func classify(error: Error) -> SyncIssueKind {
        switch CloudSyncError.from(error) {
        case .networkUnavailable:
            return .network
        case .quotaExceeded:
            return .quota
        case .authenticationFailed:
            return .authentication
        case .serverError:
            return .server
        case .unknown:
            return .unknown
        }
    }

    public static func classify(message: String) -> SyncIssueKind {
        let value = message.lowercased()
        if value.contains("network") || value.contains("offline") || value.contains("网络") {
            return .network
        }
        if value.contains("quota") || value.contains("storage") || value.contains("空间") || value.contains("存储") {
            return .quota
        }
        if value.contains("auth") || value.contains("notauthenticated") || value.contains("登录") || value.contains("账号") {
            return .authentication
        }
        if value.contains("server") || value.contains("service unavailable") || value.contains("服务") {
            return .server
        }
        return .unknown
    }

    public static func recommendation(for kind: SyncIssueKind) -> String {
        switch kind {
        case .network:
            return "Check your connection and retry sync."
        case .quota:
            return "Free up iCloud storage, then retry sync."
        case .authentication:
            return "Sign in to iCloud and verify app iCloud permission."
        case .server:
            return "Cloud service may be temporarily unavailable. Retry later."
        case .unknown:
            return "Inspect raw logs and verify network + iCloud account status."
        }
    }

    public static func recommendations(
        syncError: Error?,
        localSyncErrorMessage: String?,
        cloudSyncEnabled: Bool
    ) -> [String] {
        guard cloudSyncEnabled else {
            return ["Cloud sync is disabled; local database mode is active."]
        }

        var items: [String] = []

        if let syncError {
            items.append(recommendation(for: classify(error: syncError)))
        }

        if let localSyncErrorMessage, !localSyncErrorMessage.isEmpty {
            let text = recommendation(for: classify(message: localSyncErrorMessage))
            if !items.contains(text) {
                items.append(text)
            }
        }

        if items.isEmpty {
            items.append("No obvious sync issue detected.")
        }
        return items
    }
}
