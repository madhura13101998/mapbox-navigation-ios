# CocoaPods Support Summary

## ✅ Completed Tasks

### 1. Created Podspecs
- ✅ `MapboxNavigationCore.podspec` - Core navigation module (excludes UIKit)
- ✅ `MapboxDirections.podspec` - Directions API module

### 2. Fixed SPM-Only Code Patterns
- ✅ Fixed `Bundle.module` usage in `Sources/MapboxNavigationCore/Extensions/Bundle.swift`
- ✅ Fixed `Bundle.module` usage in `Sources/MapboxNavigationCore/Map/Style/MapFeatures/RouteCalloutView.swift`
- ✅ Handled `#if SWIFT_PACKAGE` conditionals for CocoaPods compatibility

### 3. Configured Podspec Settings
- ✅ `static_framework = true` (required for Flutter)
- ✅ `DEFINES_MODULE = YES` in pod_target_xcconfig
- ✅ Swift 5.8 support
- ✅ iOS 14.0+ platform requirement

### 4. Dependencies (Exact Versions, No Ranges)
- ✅ MapboxMaps: 11.18.0-beta.1
- ✅ MapboxNavigationNative: 324.18.0-beta.1
- ✅ MapboxCommon: (no version - uses compatible)
- ✅ MapboxDirections: 3.18.0-beta.1 (separate podspec)
- ✅ Turf: 4.0.0

### 5. Source Files Included
- ✅ MapboxNavigationCore sources
- ✅ _MapboxNavigationHelpers (internal)
- ✅ _MapboxNavigationLocalization (internal)
- ✅ Resources (localizations, images, etc.)

## 📋 Files Created/Modified

### Created
- `MapboxNavigationCore.podspec`
- `MapboxDirections.podspec`
- `COCOAPODS_NOTES.md` (detailed documentation)
- `COCOAPODS_SUMMARY.md` (this file)

### Modified
- `Sources/MapboxNavigationCore/Extensions/Bundle.swift`
- `Sources/MapboxNavigationCore/Map/Style/MapFeatures/RouteCalloutView.swift`

## 🚀 Usage

### Step 1: Update Git URLs
Replace `<your-fork>` in both podspecs with your actual fork URL:
- `MapboxNavigationCore.podspec` line 14
- `MapboxDirections.podspec` line 14

### Step 2: Flutter Podfile
```ruby
platform :ios, '14.0'
use_frameworks! :linkage => :static

target 'Runner' do
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
  
  # MapboxDirections (must come before MapboxNavigationCore)
  pod 'MapboxDirections',
      :git => 'https://github.com/<your-fork>/mapbox-navigation-ios.git',
      :branch => 'release/mapbox-navigation-ios/3.18.0-beta.1'
  
  # MapboxNavigationCore
  pod 'MapboxNavigationCore',
      :git => 'https://github.com/<your-fork>/mapbox-navigation-ios.git',
      :branch => 'release/mapbox-navigation-ios/3.18.0-beta.1'
end
```

### Step 3: Configure .netrc
Create `~/.netrc` with your private Mapbox access token:
```
machine api.mapbox.com
  login mapbox
  password YOUR_PRIVATE_MAPBOX_API_TOKEN
```

### Step 4: Install
```bash
cd ios
pod install
```

## ⚠️ Important Notes

1. **Version Compatibility**: Ensure `mapbox_maps_flutter: 2.18.0-beta.1` uses MapboxMaps 11.18.0-beta.1 to avoid conflicts.

2. **Static Framework**: Both podspecs use `static_framework = true` for Flutter compatibility.

3. **Module Name**: The pod name and module name are the same (`MapboxNavigationCore`). If you need to avoid naming conflicts, you can rename the pod to `MapboxNavigationCoreUnofficial` while keeping the module name.

4. **Dependency Order**: In your Podfile, `MapboxDirections` must be listed before `MapboxNavigationCore`.

5. **No UIKit**: MapboxNavigationUIKit is explicitly excluded as requested.

## ✅ Validation Checklist

- [x] Bundle.module usage fixed for CocoaPods
- [x] #if SWIFT_PACKAGE conditionals handled
- [x] No @_implementationOnly imports in core module
- [x] static_framework = true set
- [x] DEFINES_MODULE = YES configured
- [x] Exact version pins (no ranges)
- [x] MapboxDirections as separate dependency
- [x] All required dependencies declared
- [x] Resources included
- [x] Helper modules included

## 🔍 Known Issues & Solutions

### Issue: "Module 'MapboxDirections' not found"
**Solution**: Ensure both pods are in Podfile, with MapboxDirections listed first.

### Issue: "Bundle.module is unavailable"
**Solution**: The fixes should handle this. If you see this error, verify the #if SWIFT_PACKAGE conditionals are working.

### Issue: "Duplicate symbol" errors
**Solution**: Ensure only one instance of MapboxCommon is linked. Check Podfile for duplicates.

### Issue: Version conflicts
**Solution**: Ensure all Mapbox dependencies use compatible versions:
- MapboxMaps: 11.18.0-beta.1
- MapboxNavigationNative: 324.18.0-beta.1
- MapboxCommon: (compatible version from Maps/Native)

## 📚 Additional Documentation

See `COCOAPODS_NOTES.md` for detailed information about:
- Code changes made
- Dependency resolution
- Troubleshooting
- Future improvements

## ✨ Next Steps

1. Replace `<your-fork>` placeholders in podspecs
2. Test in a Flutter project with `mapbox_maps_flutter: 2.18.0-beta.1`
3. Verify dependency resolution works correctly
4. Test navigation functionality

## 🎯 Success Criteria

The podspecs are ready when:
- ✅ `pod install` succeeds without errors
- ✅ No duplicate symbol errors
- ✅ MapboxNavigationCore can be imported in Swift/Flutter
- ✅ Navigation functionality works with MapboxMaps 11.18.0-beta.1
- ✅ No conflicts with mapbox_maps_flutter 2.18.0-beta.1
