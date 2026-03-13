# SwiftDataCloudSyncKit

[English README](./README.md)

一个基于 SwiftData 原生 CloudKit 集成的轻量同步工具库。

## 功能特性

- 纯本地模式（`CloudSyncMode.disabled`）
- 可选 CloudKit 模式（`CloudSyncMode.enabled(cloudKitDatabase:)`）
- 运行时开关云同步（`setCloudSyncEnabled`）
- 原生单容器架构，切换开关时自动重建容器
- 混合存储：`syncedTypes`（走 CloudKit）+ `localOnlyTypes`（仅本地）
- 可选云事件过滤（`cloudEventFilter`），适用于多容器场景
- 同步事件监控（`CloudSyncMonitor`）
- 同步问题诊断（`SyncDiagnosticsAdvisor`）

## 环境要求

- iOS 17.0+ / macOS 14.0+
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

## 纯本地模式

```swift
let configuration = NativeCloudSyncConfiguration(
    syncedTypes: [Work.self, UserProfile.self],
    cloudSyncMode: .disabled,
    settingsStore: InMemoryCloudSyncSettingsStore(isCloudSyncEnabled: false)
)
```

该模式下，同步库会创建不带 CloudKit 的本地存储。

## 运行时切换云同步

```swift
do {
    try engine.setCloudSyncEnabled(true)
} catch {
    print(error.localizedDescription)
}
```

如果 `cloudSyncMode` 是 `.disabled`，运行时启用会抛出 `CloudSyncEngineError.cloudSyncNotAvailable`。

## 监控与诊断

```swift
let monitor = engine.syncMonitor

if let error = monitor.syncError {
    let issue = SyncDiagnosticsAdvisor.classify(error: error)
    let advice = SyncDiagnosticsAdvisor.recommendation(for: issue)
    print(advice)
}
```

说明：本库通过系统 CloudKit 事件监听同步状态，不提供手动 `triggerSync()` API。

## SwiftUI 集成

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

## 核心公开类型

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

## 许可证

MIT，见 [LICENSE](./LICENSE)。
