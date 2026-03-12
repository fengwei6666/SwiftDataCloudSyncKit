# SwiftDataCloudSyncKit

[English README](./README.md)

一个解耦的 SwiftData 同步工具库，支持可选 CloudKit。

## 功能特性

- 纯本地模式（`CloudSyncMode.disabled`）
- 可选 CloudKit 模式（`CloudSyncMode.enabled(cloudKitDatabase:)`）
- 运行时开关云同步（`setCloudSyncEnabled`）
- 同步事件监控（`CloudSyncMonitor`）
- 重试执行器（`RetryExecutor`）
- 离线操作队列（`OfflineOperationQueue`）
- 同步问题诊断（`SyncDiagnosticsAdvisor`）

## 环境要求

- iOS 17.0+
- Swift 5.9+
- Xcode 15+

## 安装方式

### Swift Package Manager

#### 本地包接入

Xcode 中：

1. `File` -> `Add Package Dependencies...`
2. 选择 `Add Local...`
3. 选择本目录（`SwiftDataCloudSyncKit`）

#### Package.swift 方式

```swift
.package(path: "../SwiftDataCloudSyncKit")
```

### CocoaPods

```ruby
platform :ios, '17.0'
use_frameworks!

pod 'SwiftDataCloudSyncKit', :path => '../SwiftDataCloudSyncKit'
```

然后执行：

```bash
pod install
```

## 快速开始

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
    settingsStore: settingsStore,
    localToCloudSyncHandler: { localContainer, cloudContainer in
        // 在这里实现本地到云端的 upsert 逻辑
    }
)

let engine = SwiftDataCloudSyncEngine(configuration: configuration)
try engine.setup()

let context = engine.modelContext
let monitor = engine.syncMonitor
```

## 纯本地模式

```swift
let configuration = SwiftDataCloudSyncConfiguration(
    schema: Schema([Work.self, ThumbnailAsset.self]),
    cloudSyncMode: .disabled,
    settingsStore: InMemoryCloudSyncSettingsStore(isCloudSyncEnabled: false)
)
```

该模式下不会创建 CloudKit 容器。

## 运行时切换云同步

```swift
Task {
    do {
        try await engine.setCloudSyncEnabled(true)
    } catch {
        print(error.localizedDescription)
    }
}
```

如果配置是 `.disabled`，启用时会抛出 `SwiftDataCloudSyncEngineError.cloudSyncNotAvailable`。

## 监控与诊断

```swift
let monitor = engine.syncMonitor
monitor.triggerSync()

if let error = monitor.syncError {
    let issue = SyncDiagnosticsAdvisor.classify(error: error)
    let advice = SyncDiagnosticsAdvisor.recommendation(for: issue)
    print(advice)
}
```

## 核心公开类型

- `SwiftDataCloudSyncEngine`
- `SwiftDataCloudSyncConfiguration`
- `CloudSyncMode`
- `CloudSyncMonitor`
- `CloudSyncSettingsStore`
- `UserDefaultsCloudSyncSettingsStore`
- `InMemoryCloudSyncSettingsStore`
- `RetryExecutor`
- `OfflineOperationQueue`
- `SyncDiagnosticsAdvisor`

## 许可证

MIT，见 [LICENSE](./LICENSE)。
