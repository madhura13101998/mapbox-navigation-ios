Pod::Spec.new do |s|
  s.name             = "MapboxDirections"
  s.version          = "3.18.0-beta.1"
  s.summary          = "Mapbox Directions API wrapper for Swift"
  s.description      = <<-DESC
    MapboxDirections makes it easy to connect your iOS, macOS, tvOS, or watchOS application to the Mapbox Directions API. 
    Quickly get driving, cycling, or walking directions, whether the trip is nonstop or it has multiple stopping points, 
    all using a simple interface reminiscent of MapKit's MKDirections API.
  DESC
  s.homepage         = "https://github.com/mapbox/mapbox-navigation-ios"
  s.license          = { :type => "Mapbox Terms of Service", :file => "LICENSE.md" }
  s.author           = { "Mapbox" => "mobile@mapbox.com" }
  s.source           = { :git => "https://github.com/<your-fork>/mapbox-navigation-ios.git", :tag => "v#{s.version}" }
  
  s.platform         = :ios, "14.0"
  s.swift_version    = "5.8"
  s.requires_arc     = true
  s.static_framework = true
  
  s.module_name      = "MapboxDirections"
  
  s.source_files = "Sources/MapboxDirections/**/*.{swift,h}"
  s.public_header_files = "Sources/MapboxDirections/**/*.h"
  
  # Dependencies - EXACT versions (no ranges) as required
  s.dependency "Turf", "4.0.0"
  
  s.frameworks = "CoreLocation", "Foundation"
  
  s.pod_target_xcconfig = {
    "DEFINES_MODULE" => "YES",
    "SWIFT_VERSION" => "5.8"
  }
end
