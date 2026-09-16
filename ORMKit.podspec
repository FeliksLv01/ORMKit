Pod::Spec.new do |s|
  s.name = 'ORMKit'
  s.version = '0.0.3'
  s.summary = 'A typed, macro-powered SQLite ORM for Swift 6.'
  s.description = 'UI-independent SQLite persistence with typed queries, async CRUD, observation, and explicit migrations.'
  s.homepage = 'https://github.com/FeliksLv01/ORMKit'
  s.license = { :type => 'MIT', :file => 'LICENSE' }
  s.author = 'FeliksLv01'
  s.source = { :git => 'https://github.com/FeliksLv01/ORMKit.git', :tag => s.version.to_s }
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.tvos.deployment_target = '15.0'
  s.watchos.deployment_target = '8.0'
  s.swift_version = '6.0'
  s.source_files = 'Sources/ORMKit/**/*.swift'
  s.preserve_paths = 'Prebuilt/ORMKitMacros', 'ThirdPartyNotices/swift-syntax-LICENSE.txt'
  s.dependency 'GRDB.swift', '~> 7.11'
  s.pod_target_xcconfig = {
    'OTHER_SWIFT_FLAGS' => '$(inherited) -load-plugin-executable ${PODS_TARGET_SRCROOT}/Prebuilt/ORMKitMacros#ORMKitMacros'
  }
  s.user_target_xcconfig = {
    'OTHER_SWIFT_FLAGS' => '$(inherited) -load-plugin-executable ${PODS_ROOT}/ORMKit/Prebuilt/ORMKitMacros#ORMKitMacros'
  }
end
