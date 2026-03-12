Pod::Spec.new do |s|
  s.name             = 'SwiftDataCloudSyncKit'
  s.version          = '0.1.0'
  s.summary          = 'Decoupled SwiftData + CloudKit sync status library.'
  s.description      = <<-DESC
A reusable SwiftData sync library with optional CloudKit support, sync monitoring,
retry execution and offline operation queue.
  DESC
  s.homepage         = 'https://github.com/fengwei6666/SwiftDataCloudSyncKit'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Maintainers' => 'maintainers@example.com' }
  s.source           = { :git => 'https://github.com/fengwei6666/SwiftDataCloudSyncKit.git', :tag => s.version.to_s }

  s.platform         = :ios, '17.0'
  s.swift_versions   = ['5.9']
  s.requires_arc     = true

  s.source_files     = 'Sources/SwiftDataCloudSyncKit/**/*.swift'
  s.frameworks       = 'Foundation', 'CoreData', 'SwiftData', 'CloudKit', 'Network', 'Combine'
end
