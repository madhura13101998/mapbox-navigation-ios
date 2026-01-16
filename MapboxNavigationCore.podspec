Pod::Spec.new do |s|
  s.name             = "MapboxNavigationCore"
  s.version          = "3.18.0-beta.1"
  s.summary          = "Core navigation logic for Mapbox Navigation SDK (CocoaPods unofficial support)"
  s.description      = <<-DESC
    MapboxNavigationCore provides the core navigation functionality for the Mapbox Navigation SDK, 
    including routing, navigation, and location tracking without UI components.
    
    This is an unofficial CocoaPods podspec for use with Flutter apps. The official SDK uses Swift Package Manager.
  DESC
  s.homepage         = "https://github.com/mapbox/mapbox-navigation-ios"
  s.license          = { :type => "Mapbox Terms of Service", :file => "LICENSE.md" }
  s.author           = { "Mapbox" => "mobile@mapbox.com" }
  s.source           = { :git => "https://github.com/<your-fork>/mapbox-navigation-ios.git", :tag => "v#{s.version}" }
  
  s.platform         = :ios, "14.0"
  s.swift_version    = "5.8"
  s.requires_arc     = true
  s.static_framework = true
  
  s.module_name      = "MapboxNavigationCore"
  
  # All source files - MapboxNavigationCore + internal helpers
  # Exclude UIColor++.swift from MapboxNavigationCore to avoid conflict with helpers
  s.source_files = [
    "Sources/MapboxNavigationCore/**/*.{swift,h}",
    "Sources/_MapboxNavigationHelpers/**/*.swift",
    "Sources/_MapboxNavigationLocalization/**/*.swift"
  ]
  s.exclude_files = [
    "Sources/MapboxNavigationCore/Map/Other/UIColor++.swift"
  ]
  
  # Resources - use resource_bundles to avoid Assets.car conflicts
  s.resource_bundles = {
    'MapboxNavigationCore' => ['Sources/MapboxNavigationCore/Resources/**/*']
  }
  
  # Dependencies - EXACT versions (no ranges) as required
  s.dependency "MapboxDirections", "#{s.version}"
  s.dependency "MapboxMaps", "11.18.0-beta.1"
  s.dependency "MapboxNavigationNative", "324.18.0-beta.1"
  s.dependency "MapboxCommon"
  s.dependency "Turf", "4.0.0"
  
  # System frameworks
  s.frameworks = [
    "UIKit",
    "Foundation", 
    "CoreLocation",
    "AVFoundation",
    "CoreGraphics",
    "UserNotifications"
  ]
  
  # Ensure module is properly defined
  s.pod_target_xcconfig = {
    "DEFINES_MODULE" => "YES",
    "SWIFT_VERSION" => "5.8"
  }
  
  # Fix module imports for CocoaPods compatibility
  # In CocoaPods, all source files are in the same module, so these imports fail
  # We use prepare_command to comment them out before build
  s.prepare_command = <<-CMD
    # Comment out module imports that don't work in CocoaPods (same module)
    # Use | as delimiter to avoid conflicts with / in replacement string
    if [ -d "Sources/MapboxNavigationCore" ]; then
      find Sources/MapboxNavigationCore -name "*.swift" -type f -exec sed -i.bak 's|^import _MapboxNavigationHelpers$|// import _MapboxNavigationHelpers // CocoaPods: same module|g' {} +
      find Sources/MapboxNavigationCore -name "*.swift" -type f -exec sed -i.bak 's|^import _MapboxNavigationLocalization$|// import _MapboxNavigationLocalization // CocoaPods: same module|g' {} +
      find Sources/MapboxNavigationCore -name "*.swift" -type f -exec sed -i.bak -e 's|^@_exported import _MapboxNavigationLocalization$|// @_exported import _MapboxNavigationLocalization // CocoaPods: same module|g' {} +
    fi
    if [ -d "Sources/_MapboxNavigationLocalization" ]; then
      find Sources/_MapboxNavigationLocalization -name "*.swift" -type f -exec sed -i.bak 's|^import _MapboxNavigationHelpers$|// import _MapboxNavigationHelpers // CocoaPods: same module|g' {} +
    fi
    # Clean up backup files
    find Sources -name "*.bak" -type f -delete 2>/dev/null || true
  CMD
  
  # Note: MapboxNavigationNative and MapboxMaps require private access tokens
  # Users must configure .netrc file with DOWNLOADS:READ scope token
end
