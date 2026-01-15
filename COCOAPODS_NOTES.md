# CocoaPods Support for MapboxNavigationCore 3.18.0-beta.1

## Overview

This is an **unofficial** CocoaPods podspec for MapboxNavigationCore, created to enable usage in Flutter apps that use `mapbox_maps_flutter: 2.18.0-beta.1` with MapboxMaps iOS 11.18.0-beta.1.

The official Mapbox Navigation SDK uses Swift Package Manager (SPM) only. This podspec provides CocoaPods compatibility.

## Files Created/Modified

### Created Files
- `MapboxNavigationCore.podspec` - CocoaPods podspec file for core navigation
- `MapboxDirections.podspec` - CocoaPods podspec file for directions API

### Modified Files
- `Sources/MapboxNavigationCore/Extensions/Bundle.swift` - Fixed Bundle.module usage for CocoaPods
- `Sources/MapboxNavigationCore/Map/Style/MapFeatures/RouteCalloutView.swift` - Fixed Bundle.module usage for CocoaPods

## Key Changes Made

### 1. Bundle.module Compatibility

**Issue**: SPM provides `Bundle.module` automatically, but CocoaPods does not.

**Fix**: Modified code to use `Bundle(for: BundleToken.self)` when not using SPM:

```swift
#if SWIFT_PACKAGE
    public static let mapboxNavigationUXCore: Bundle = .module
#else
    private static let module: Bundle = .init(for: BundleToken.self)
    public static let mapboxNavigationUXCore: Bundle = .init(for: BundleToken.self)
#endif
```

### 2. Source File Inclusion

The podspec includes:
- `MapboxNavigationCore` sources
- `_MapboxNavigationHelpers` (internal helper module)
- `_MapboxNavigationLocalization` (internal localization module)

MapboxDirections is provided as a separate podspec dependency (not bundled).

### 3. Dependencies

Exact version pins (no ranges) as required:
- `MapboxMaps`: 11.18.0-beta.1
- `MapboxNavigationNative`: 324.18.0-beta.1
- `MapboxCommon`: (no version specified - uses latest compatible)
- `Turf`: 4.0.0

## Usage

### In Flutter Podfile

```ruby
platform :ios, '14.0'
use_frameworks! :linkage => :static

target 'Runner' do
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
  
  # MapboxDirections (from your fork) - required by MapboxNavigationCore
  pod 'MapboxDirections',
      :git => 'https://github.com/<your-fork>/mapbox-navigation-ios.git',
      :branch => 'release/mapbox-navigation-ios/3.18.0-beta.1'
  
  # MapboxNavigationCore (from your fork)
  pod 'MapboxNavigationCore',
      :git => 'https://github.com/<your-fork>/mapbox-navigation-ios.git',
      :branch => 'release/mapbox-navigation-ios/3.18.0-beta.1'
end
```

### Prerequisites

1. **Private Access Token**: MapboxNavigationNative and MapboxMaps require a private access token with `DOWNLOADS:READ` scope. Create a `.netrc` file in your home directory:

   ```
   machine api.mapbox.com
     login mapbox
     password YOUR_PRIVATE_MAPBOX_API_TOKEN
   ```

2. **Version Compatibility**: Ensure `mapbox_maps_flutter` uses MapboxMaps 11.18.0-beta.1 to avoid conflicts.

## Known Issues & Pitfalls

### 1. MapboxDirections Dependency

**Solution**: MapboxDirections is provided as a separate podspec (`MapboxDirections.podspec`) that must be included in your Podfile.

**Usage**: Both podspecs reference the same git repository, so CocoaPods will resolve them correctly when both are specified in the Podfile.

### 2. MapboxCommon Version

**Issue**: MapboxCommon dependency has no version specified.

**Reason**: MapboxCommon is typically a transitive dependency from MapboxMaps or MapboxNavigationNative. However, it's explicitly declared to ensure it's available.

**Note**: If you encounter version conflicts, you may need to specify an exact version that matches your MapboxMaps version.

### 3. Static Framework

**Issue**: `static_framework = true` is set to avoid dynamic framework issues with Flutter.

**Impact**: All dependencies must also be static frameworks or compatible with static linking.

### 4. Module Name

The pod name is `MapboxNavigationCore` but the module name is also `MapboxNavigationCore`. This should work correctly, but if you need to avoid naming conflicts, you can rename the pod to `MapboxNavigationCoreUnofficial` while keeping the module name unchanged.

### 5. Resource Bundle Access

Resources are included using `s.resources` (not `s.resource_bundles`). This means resources are added directly to the main bundle, which should work with the `Bundle(for:)` approach we're using.

## Validation Checklist

- [x] Bundle.module usage fixed for CocoaPods
- [x] #if SWIFT_PACKAGE conditionals handled
- [x] No @_implementationOnly imports in core module (only in test helpers)
- [x] static_framework = true set
- [x] DEFINES_MODULE = YES configured
- [x] Exact version pins (no ranges)
- [x] MapboxDirections bundled (to avoid dependency issues)
- [x] All required dependencies declared

## Testing

To validate the podspec:

```bash
# Install CocoaPods if not already installed
sudo gem install cocoapods

# Validate podspec syntax
pod spec lint MapboxNavigationCore.podspec --allow-warnings

# Test installation in a sample project
pod install
```

## Dependency Resolution

The podspec should resolve dependencies correctly with:
- `mapbox_maps_flutter: 2.18.0-beta.1` → MapboxMaps 11.18.0-beta.1
- `MapboxNavigationCore` → MapboxMaps 11.18.0-beta.1 (same version, no conflict)
- `MapboxNavigationCore` → MapboxNavigationNative 324.18.0-beta.1
- `MapboxNavigationCore` → MapboxCommon (transitive or explicit)
- `MapboxNavigationCore` → Turf 4.0.0

## Troubleshooting

### Build Errors

1. **"Module 'MapboxDirections' not found"**: Ensure both `MapboxDirections` and `MapboxNavigationCore` pods are included in your Podfile. MapboxDirections must be listed before MapboxNavigationCore.

2. **"Bundle.module is unavailable"**: The Bundle.swift fix should handle this. If you see this error, check that the #if SWIFT_PACKAGE conditional is working.

3. **"Duplicate symbol"**: Ensure only one instance of MapboxCommon is linked. Check your Podfile for duplicate dependencies.

4. **"MapboxMaps version conflict"**: Ensure `mapbox_maps_flutter` uses MapboxMaps 11.18.0-beta.1, not v10 or a different v11 version.

### Dependency Conflicts

If you see dependency conflicts:
1. Run `pod deintegrate` then `pod install` to clean up
2. Check `Podfile.lock` for version mismatches
3. Ensure all Mapbox dependencies use compatible versions

## Notes

- This is beta software - expect potential issues
- CocoaPods support is manual and unofficial
- The official SDK uses SPM - this podspec is for Flutter compatibility only
- Prioritize correctness and compatibility over elegance (as requested)

## Future Improvements

1. If MapboxDirections becomes available as a CocoaPod, split it into a separate dependency
2. Consider creating `MapboxNavigationCoreUnofficial` pod name to avoid naming conflicts
3. Add version validation to ensure MapboxMaps compatibility
4. Document any additional SPM-only patterns that need fixing
