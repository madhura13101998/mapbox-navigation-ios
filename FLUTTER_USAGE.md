# Flutter Usage - Quick Guide

## 1. Update Podspecs with Your Fork URL

Replace `<your-fork>` in both files:
- `MapboxNavigationCore.podspec` line 14
- `MapboxDirections.podspec` line 14

Change:
```ruby
s.source = { :git => "https://github.com/<your-fork>/mapbox-navigation-ios.git", :tag => "v#{s.version}" }
```

To:
```ruby
s.source = { :git => "https://github.com/YOUR_USERNAME/mapbox-navigation-ios.git", :tag => "v#{s.version}" }
```

## 2. Add to Flutter iOS Podfile

Edit `ios/Podfile`:

```ruby
platform :ios, '14.0'
use_frameworks! :linkage => :static

target 'Runner' do
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
  
  # Add these two lines (replace YOUR_USERNAME and BRANCH_NAME)
  pod 'MapboxDirections', :git => 'https://github.com/YOUR_USERNAME/mapbox-navigation-ios.git', :branch => 'BRANCH_NAME'
  pod 'MapboxNavigationCore', :git => 'https://github.com/YOUR_USERNAME/mapbox-navigation-ios.git', :branch => 'BRANCH_NAME'
end
```

## 3. Configure .netrc (Required)

Create/edit `~/.netrc`:
```
machine api.mapbox.com
  login mapbox
  password YOUR_PRIVATE_MAPBOX_TOKEN
```

## 4. Install

```bash
cd ios
pod install
cd ..
flutter clean
flutter pub get
```

## 5. Use in Dart

```dart
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
// MapboxNavigationCore is available via platform channels or native code
```

Done! ✅
