#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint verify_local_purchase.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'verify_local_purchase'
  s.version          = '1.1.0'
  s.summary          = 'Verify in-app purchases and subscriptions locally on device.'
  s.description      = <<-DESC
A Flutter package for verifying in-app purchases and subscriptions locally on device with Apple App Store and Google Play Store.
                       DESC
  s.homepage         = 'https://github.com/andrelucassvt/verify_local_purchase'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'André Lucas' => 'andrelucassvt99@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'verify_local_purchase/Sources/verify_local_purchase/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # Privacy manifest is bundled so CocoaPods matches the Swift Package Manager
  # setup (see verify_local_purchase/Package.swift). For more information, see
  # https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  s.resource_bundles = {'verify_local_purchase_privacy' => ['verify_local_purchase/Sources/verify_local_purchase/PrivacyInfo.xcprivacy']}
end
