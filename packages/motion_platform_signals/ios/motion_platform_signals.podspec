Pod::Spec.new do |s|
  s.name             = 'motion_platform_signals'
  s.version          = '0.2.0'
  s.summary          = 'Store/platform signals for the Yula Motion family.'
  s.description      = <<-DESC
App Store app transaction ID (StoreKit 2, iOS 16+) for server-signed
introductory-offer eligibility. Degrades to nil where unavailable.
                       DESC
  s.homepage         = 'https://yulalab.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Yula Lab' => 'dev@yulalab.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.resource_bundles = {
    'motion_platform_signals_privacy' => ['Resources/PrivacyInfo.xcprivacy']
  }
  s.dependency 'Flutter'
  s.frameworks = 'StoreKit'
  s.platform = :ios, '15.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
