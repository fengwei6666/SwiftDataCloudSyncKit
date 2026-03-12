# SwiftDataCloudSyncKit Demo

This demo app is used to debug and validate SwiftDataCloudSyncKit features:

- Cloud-capable vs local-only engine setup
- Runtime cloud sync toggle
- Manual sync trigger and sync monitor state
- Local SwiftData writes and reload
- RetryExecutor behavior
- OfflineOperationQueue behavior
- Sync diagnostics recommendations
- Conflict injection and stats visualization:
  - Inject cloud-newer records to verify local update skip behavior
  - Inject cloud duplicates to verify deduplication path

## Generate Xcode project

```bash
cd Demo
xcodegen generate
```

## Build

```bash
xcodebuild \
  -project Demo/SwiftDataCloudSyncKitDemo.xcodeproj \
  -scheme SwiftDataCloudSyncKitDemo \
  -configuration Debug \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/SwiftDataCloudSyncKitDemoDerivedData \
  build CODE_SIGNING_ALLOWED=NO
```
