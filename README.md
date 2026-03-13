# SwiftDataCloudSyncKit

[中文文档](./README.zh-CN.md)

A lightweight SwiftData sync toolkit built on top of native CloudKit integration.

## Features

- Local-only mode (`CloudSyncMode.disabled`)
- Optional CloudKit mode (`CloudSyncMode.enabled(cloudKitDatabase:)`)
- Runtime cloud sync on/off (`setCloudSyncEnabled`)
- Native single-container architecture with automatic container recreation on toggle
- Mixed storage support: `syncedTypes` (CloudKit) + `localOnlyTypes` (device-only)
- Optional cloud event filtering (`cloudEventFilter`) for multi-container apps
- Sync event monitoring (`CloudSyncMonitor`)
- Sync diagnostics (`SyncDiagnosticsAdvisor`)

## Requirements

- iOS 17.0+ / macOS 14.0+
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
    defaultValue: true
)

let configuration = NativeCloudSyncConfiguration(
    syncedTypes: [Work.self, UserProfile.self],
    cloudStoreName: "AppCloudStore",
    cloudSyncMode: .enabled(cloudKitDatabase: .automatic),
    localOnlyTypes: [Draft.self],
    localStoreName: "AppLocalStore",
    settingsStore: settingsStore
)

let engine = NativeCloudSyncEngine(configuration: configuration)
try engine.setup()

guard let context = engine.modelContext else { return }
let monitor = engine.syncMonitor
```

## Local-only Mode

```swift
let configuration = NativeCloudSyncConfiguration(
    syncedTypes: [Work.self, UserProfile.self],
    cloudSyncMode: .disabled,
    settingsStore: InMemoryCloudSyncSettingsStore(isCloudSyncEnabled: false)
)
```

In this mode, the synced store is created without CloudKit.

## Runtime Cloud Toggle

```swift
do {
    try engine.setCloudSyncEnabled(true)
} catch {
    print(error.localizedDescription)
}
```

If `cloudSyncMode` is `.disabled`, enabling at runtime throws `CloudSyncEngineError.cloudSyncNotAvailable`.

## Monitoring and Diagnostics

```swift
let monitor = engine.syncMonitor

if let error = monitor.syncError {
    let issue = SyncDiagnosticsAdvisor.classify(error: error)
    let advice = SyncDiagnosticsAdvisor.recommendation(for: issue)
    print(advice)
}
```

Note: this library observes system CloudKit events; there is no manual `triggerSync()` API.

## SwiftUI Integration

```swift
@StateObject private var engine = NativeCloudSyncEngine(configuration: configuration)

var body: some Scene {
    WindowGroup {
        Group {
            if let container = engine.container {
                ContentView()
                    .modelContainer(container)
                    .id(ObjectIdentifier(container))
            } else {
                ProgressView()
            }
        }
        .task { try? engine.setup() }
    }
}
```

## Public Core Types

- `CloudSyncEngine`
- `NativeCloudSyncEngine`
- `NativeCloudSyncConfiguration`
- `CloudSyncEngineError`
- `CloudSyncMode`
- `CloudSyncMonitor`
- `CloudSyncSettingsStore`
- `UserDefaultsCloudSyncSettingsStore`
- `InMemoryCloudSyncSettingsStore`
- `CloudSyncError`
- `SyncIssueKind`
- `SyncDiagnosticsAdvisor`

## License

MIT. See [LICENSE](./LICENSE).
