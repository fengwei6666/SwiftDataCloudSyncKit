# SwiftDataCloudSyncKit

[中文文档](./README.zh-CN.md)

A decoupled SwiftData synchronization toolkit with optional CloudKit support.

## Features

- Local-only mode (`CloudSyncMode.disabled`)
- Optional CloudKit mode (`CloudSyncMode.enabled(cloudKitDatabase:)`)
- Data access mode (`DataAccessMode.localOnly` recommended)
- Runtime cloud sync on/off switch (`setCloudSyncEnabled`)
- Sync event monitoring (`CloudSyncMonitor`)
- Retry utility (`RetryExecutor`)
- Offline operation queue (`OfflineOperationQueue`)
- Sync issue diagnostics (`SyncDiagnosticsAdvisor`)

## Requirements

- iOS 17.0+
- Swift 5.9+
- Xcode 15+

## Installation

### Swift Package Manager

#### Local package

In Xcode:

1. `File` -> `Add Package Dependencies...`
2. Choose `Add Local...`
3. Select this folder (`SwiftDataCloudSyncKit`)

#### Package.swift dependency

```swift
.package(path: "../SwiftDataCloudSyncKit")
```

### CocoaPods

```ruby
platform :ios, '17.0'
use_frameworks!

pod 'SwiftDataCloudSyncKit', :path => '../SwiftDataCloudSyncKit'
```

Then run:

```bash
pod install
```

## Quick Start

```swift
import SwiftData
import SwiftDataCloudSyncKit

let settingsStore = UserDefaultsCloudSyncSettingsStore(
    key: "myAppCloudSyncEnabled",
    defaultValue: false
)

let configuration = SwiftDataCloudSyncConfiguration(
    schema: Schema([Work.self, ThumbnailAsset.self]),
    cloudSyncMode: .enabled(cloudKitDatabase: .automatic),
    dataAccessMode: .localOnly,
    settingsStore: settingsStore,
    localToCloudSyncHandler: { localContainer, cloudContainer in
        // Implement your local->cloud upsert logic.
    }
)

let engine = SwiftDataCloudSyncEngine(configuration: configuration)
try engine.setup()

// Business reads/writes should use local context.
let context = engine.modelContext
let monitor = engine.syncMonitor
```

## Data Access Modes

```swift
DataAccessMode.localOnly
```

- Recommended.
- `modelContext` always points to local store.
- Cloud container is used for sync only.

```swift
DataAccessMode.switchWithCloudSync
```

- Compatibility mode.
- `modelContext` switches with cloud sync state.
- Higher risk of context-level split-brain if app logic is not carefully designed.

## Local-only Mode

```swift
let configuration = SwiftDataCloudSyncConfiguration(
    schema: Schema([Work.self, ThumbnailAsset.self]),
    cloudSyncMode: .disabled,
    dataAccessMode: .localOnly,
    settingsStore: InMemoryCloudSyncSettingsStore(isCloudSyncEnabled: false)
)
```

In this mode, no CloudKit container is created.

## Runtime Cloud Toggle

```swift
Task {
    do {
        try await engine.setCloudSyncEnabled(true)
    } catch {
        print(error.localizedDescription)
    }
}
```

If the configuration is `.disabled`, enabling throws `SwiftDataCloudSyncEngineError.cloudSyncNotAvailable`.

## Monitoring and Diagnostics

```swift
let monitor = engine.syncMonitor
monitor.triggerSync()

if let error = monitor.syncError {
    let issue = SyncDiagnosticsAdvisor.classify(error: error)
    let advice = SyncDiagnosticsAdvisor.recommendation(for: issue)
    print(advice)
}
```

## Public Core Types

- `SwiftDataCloudSyncEngine`
- `SwiftDataCloudSyncConfiguration`
- `CloudSyncMode`
- `DataAccessMode`
- `CloudSyncMonitor`
- `CloudSyncSettingsStore`
- `UserDefaultsCloudSyncSettingsStore`
- `InMemoryCloudSyncSettingsStore`
- `RetryExecutor`
- `OfflineOperationQueue`
- `SyncDiagnosticsAdvisor`

## License

MIT. See [LICENSE](./LICENSE).
