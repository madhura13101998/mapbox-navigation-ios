# Flutter Bridge Code Fixes

## Issues Found

### 1. Memory Leak in `subscribeToLocationUpdates()`

You're creating a subscription to `routeProgress` but not storing it:

```swift
// ❌ WRONG - Subscription not stored, will leak
navigationController.routeProgress
    .sink { state in
        // ...
    }
```

**Fix:**
```swift
// ✅ CORRECT - Store the subscription
routeProgressSubscription = navigationController.routeProgress
    .sink { state in
        // ...
    }
```

### 2. Missing Session State Check

You should verify the session is in `.activeGuidance` state before subscribing.

### 3. Missing Synthesizer Mute Check

Ensure the synthesizer is not muted.

### 4. Missing Permissions

You need location and audio permissions in `Info.plist`.

## Fixed Code

```swift
import Flutter
import UIKit
import CoreLocation
import Combine
import MapboxNavigationCore
import MapboxDirections

@MainActor
public class MapboxNavigationBridge: NSObject, FlutterPlugin, FlutterStreamHandler {
    
    // MARK: - Flutter Channels
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?
    
    // MARK: - Voice Event Channel
    private var voiceEventChannel: FlutterEventChannel?
    private var voiceInstructionHandler: VoiceInstructionHandler?
    
    // MARK: - Mapbox Navigation Components
    private let mapboxNavigationProvider: MapboxNavigationProvider
    private var mapboxNavigation: MapboxNavigation
    private var routingProvider: RoutingProvider
    private var sessionController: SessionController
    private var navigationController: NavigationController
    private var routeVoiceController: RouteVoiceController?
    
    // MARK: - Navigation State
    private var currentRoutes: NavigationRoutes?
    private var locationSubscription: AnyCancellable?
    private var voiceSubscription: AnyCancellable?
    private var routeProgressSubscription: AnyCancellable?
    private var sessionSubscription: AnyCancellable?  // ADD THIS
    private var isNavigating: Bool = false
    
    // MARK: - Initialization
    public override init() {
        mapboxNavigationProvider = MapboxNavigationProvider(coreConfig: .init())
        mapboxNavigation = mapboxNavigationProvider.mapboxNavigation
        routingProvider = mapboxNavigation.routingProvider()
        sessionController = mapboxNavigation.tripSession()
        navigationController = mapboxNavigation.navigation()
        
        super.init()
    }
    
    // MARK: - FlutterPlugin Setup
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = MapboxNavigationBridge()
        
        // Setup method channel
        instance.methodChannel = FlutterMethodChannel(
            name: "mapbox_navigation/methods",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: instance.methodChannel!)
        
        // Setup event channel for location updates
        instance.eventChannel = FlutterEventChannel(
            name: "mapbox_navigation/events",
            binaryMessenger: registrar.messenger()
        )
        instance.eventChannel?.setStreamHandler(instance)
        
        instance.voiceEventChannel = FlutterEventChannel(
            name: "mapbox_navigation/voiceInstruction",
            binaryMessenger: registrar.messenger()
        )
        instance.voiceInstructionHandler = VoiceInstructionHandler()
        instance.voiceEventChannel?.setStreamHandler(instance.voiceInstructionHandler)
    }
    
    // MARK: - Method Channel Handler
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "calculateRoute":
            handleCalculateRoute(call: call, result: result)
        case "startNavigation":
            startActiveNavigation(call: call, result: result)
        case "stopNavigation":
            handleStopNavigation(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Calculate Route
    private func handleCalculateRoute(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let startDict = args["start"] as? [String: Any],
              let endDict = args["end"] as? [String: Any],
              let startLat = startDict["lat"] as? Double,
              let startLng = startDict["lng"] as? Double,
              let endLat = endDict["lat"] as? Double,
              let endLng = endDict["lng"] as? Double else {
            result(FlutterError(
                code: "INVALID_ARGUMENTS",
                message: "Missing or invalid start/end coordinates",
                details: nil
            ))
            return
        }
        
        let startCoord = CLLocationCoordinate2D(latitude: startLat, longitude: startLng)
        let endCoord = CLLocationCoordinate2D(latitude: endLat, longitude: endLng)
        
        // Get profile identifier (default to driving)
        let profileString = args["profile"] as? String ?? "driving"
        let profile: ProfileIdentifier = {
            switch profileString.lowercased() {
            case "walking":
                return .walking
            case "cycling":
                return .cycling
            default:
                return .automobile
            }
        }()
        
        let options = NavigationRouteOptions(
            coordinates: [startCoord, endCoord],
            profileIdentifier: profile
        )
        
        // CRITICAL: Explicitly enable spoken instructions
        options.includesSpokenInstructions = true
        options.includesVisualInstructions = true
        options.includesSteps = true
        options.locale = Locale.current
        
        print("📍 Route options - includesSpokenInstructions: \(options.includesSpokenInstructions)")
        
        Task {
            do {
                let routes = try await self.calculateRoute(options: options)
                self.currentRoutes = routes
                
                // Debug: Check if route has instructions
                if let route = routes.mainRoute.route {
                    var totalInstructions = 0
                    for leg in route.legs {
                        for step in leg.steps {
                            totalInstructions += step.instructionsSpokenAlongStep?.count ?? 0
                        }
                    }
                    print("📍 Route has \(totalInstructions) total spoken instructions")
                }
                
                let routeData = self.convertRoutesToDictionary(routes)
                result(routeData)
            } catch {
                result(FlutterError(
                    code: "CALCULATE_ROUTE_ERROR",
                    message: error.localizedDescription,
                    details: nil
                ))
            }
        }
    }
    
    private func calculateRoute(options: NavigationRouteOptions) async throws -> NavigationRoutes {
        let task = routingProvider.calculateRoutes(options: options)
        let result = await task.result
        switch result {
        case .success(let routes):
            return routes
        case .failure(let error):
            throw error
        }
    }
    
    func startActiveNavigation(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let routes = currentRoutes else {
            result(FlutterError(
                code: "NO_ROUTE",
                message: "No route calculated. Call calculateRoute first.",
                details: nil
            ))
            return
        }
        
        Task {
            print("🚀 Starting active navigation...")
            
            // Start active guidance
            sessionController.startActiveGuidance(with: routes, startLegIndex: 0)
            
            // Get route voice controller
            routeVoiceController = mapboxNavigationProvider.routeVoiceController
            
            // Wait for navigation to initialize
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            // Verify session state
            let sessionState = await sessionController.currentSession
            print("🔍 Session state: \(sessionState.state)")
            
            if case .activeGuidance = sessionState.state {
                print("✅ Session is in activeGuidance state")
            } else {
                print("⚠️ WARNING: Session is NOT in activeGuidance state: \(sessionState.state)")
            }
            
            // Ensure synthesizer is not muted
            routeVoiceController?.speechSynthesizer.muted = false
            print("🔊 Synthesizer muted: \(routeVoiceController?.speechSynthesizer.muted ?? true)")
            
            // Subscribe to everything
            subscribeToSessionState()
            subscribeToLocationUpdates()
            subscribeToNavigatorVoiceInstructions()
            subscribeToRouteProgress()
            
            result(["success": true, "message": "Navigation started"])
        }
    }
    
    // MARK: - Stop Navigation
    private func handleStopNavigation(call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Cancel all subscriptions
        locationSubscription?.cancel()
        voiceSubscription?.cancel()
        routeProgressSubscription?.cancel()
        sessionSubscription?.cancel()
        
        locationSubscription = nil
        voiceSubscription = nil
        routeProgressSubscription = nil
        sessionSubscription = nil
        
        // Stop navigation
        sessionController.setToIdle()
        
        result(["success": true, "message": "Navigation stopped"])
    }
    
    // MARK: - Session State Subscription (NEW)
    private func subscribeToSessionState() {
        sessionSubscription?.cancel()
        
        sessionSubscription = sessionController.session
            .sink { [weak self] session in
                print("🔍 Session state changed: \(session.state)")
                
                switch session.state {
                case .idle:
                    print("⚠️ Session is IDLE")
                case .freeDrive:
                    print("⚠️ Session is FREE DRIVE")
                case .activeGuidance(let state):
                    print("✅ Session is ACTIVE GUIDANCE")
                    print("   Route state: \(state.routeState)")
                }
            }
    }
    
    // MARK: - Location Updates Subscription (FIXED)
    private func subscribeToLocationUpdates() {
        locationSubscription?.cancel()
        
        // Subscribe to matched location updates (road-snapped)
        locationSubscription = navigationController.locationMatching
            .sink { [weak self] locationMatching in
                guard let self = self else { return }
                let matchedLocation = locationMatching.enhancedLocation
                let coordinate = matchedLocation.coordinate
                
                // Send location update to Flutter
                self.sendLocationUpdate(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    accuracy: matchedLocation.horizontalAccuracy,
                    heading: matchedLocation.course,
                    speed: matchedLocation.speed
                )
            }
    }
    
    // MARK: - Navigator Voice Instructions Subscription
    private func subscribeToNavigatorVoiceInstructions() {
        voiceSubscription?.cancel()
        
        print("🎤 Subscribing to navigator voice instructions...")
        
        voiceSubscription = navigationController.voiceInstructions
            .sink(
                receiveCompletion: { completion in
                    print("🎤 Navigator voice stream completed: \(completion)")
                },
                receiveValue: { [weak self] spokenInstructionState in
                    guard let self = self else { return }
                    
                    let instruction = spokenInstructionState.spokenInstruction
                    print("🎤 ✅✅✅ NAVIGATOR VOICE INSTRUCTION: \(instruction.text)")
                    print("   Distance: \(instruction.distanceAlongStep)m")
                    
                    // Send to Flutter
                    let voiceInstructionData: [String: Any] = [
                        "type": "willSpeak",
                        "instruction": instruction.text,
                        "ssmlText": instruction.ssmlText ?? "",
                        "distance": instruction.distanceAlongStep
                    ]
                    
                    self.voiceInstructionHandler?.eventSink?(voiceInstructionData)
                }
            )
        
        print("🎤 Navigator voice subscription created: \(voiceSubscription != nil)")
    }
    
    // MARK: - Route Progress Subscription (FIXED - stores subscription)
    private func subscribeToRouteProgress() {
        routeProgressSubscription?.cancel()
        
        routeProgressSubscription = navigationController.routeProgress
            .sink { [weak self] state in
                guard let self = self, let routeProgress = state?.routeProgress else { return }
                
                let stepProgress = routeProgress.currentLegProgress.currentStepProgress
                let instruction = stepProgress.currentSpokenInstruction
                
                print("📍 Route progress update:")
                print("   Distance traveled: \(routeProgress.distanceTraveled)m")
                print("   Current instruction: \(instruction?.text ?? "NONE")")
                
                // Check remaining instructions
                if let remaining = stepProgress.remainingSpokenInstructions, !remaining.isEmpty {
                    let next = remaining.first!
                    let distanceToNext = next.distanceAlongStep - stepProgress.distanceTraveled
                    print("📍 Next instruction in \(distanceToNext)m: \(next.text)")
                } else {
                    print("📍 No remaining instructions in current step")
                }
                
                // Check all instructions in the step
                if let allInstructions = stepProgress.step.instructionsSpokenAlongStep {
                    print("📍 Step has \(allInstructions.count) total instructions")
                }
            }
    }
    
    // MARK: - Send Location Update to Flutter
    private func sendLocationUpdate(
        latitude: Double,
        longitude: Double,
        accuracy: Double,
        heading: Double,
        speed: Double
    ) {
        let locationData: [String: Any] = [
            "event": "locationUpdate",
            "latitude": latitude,
            "longitude": longitude,
            "accuracy": accuracy,
            "heading": heading,
            "speed": speed,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        
        eventSink?(locationData)
    }
    
    // MARK: - Convert Routes to Dictionary
    private func convertRoutesToDictionary(_ routes: NavigationRoutes) -> [String: Any] {
        let primaryRoute = routes.mainRoute
        
        var coordinates: [[Double]] = []
        if let geometry = primaryRoute.route.shape {
            for i in 0..<geometry.coordinates.count {
                let coord = geometry.coordinates[i]
                coordinates.append([coord.longitude, coord.latitude])
            }
        }
        
        return [
            "distance": primaryRoute.route.distance,
            "duration": primaryRoute.route.expectedTravelTime,
            "geometry": coordinates,
            "routeIndex": 0
        ]
    }
    
    // MARK: - FlutterStreamHandler
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        locationSubscription?.cancel()
        voiceSubscription?.cancel()
        routeProgressSubscription?.cancel()
        sessionSubscription?.cancel()
        
        locationSubscription = nil
        voiceSubscription = nil
        routeProgressSubscription = nil
        sessionSubscription = nil
        
        return nil
    }
}
```

## Required Permissions in Info.plist

Add these to your Flutter iOS app's `Info.plist` (usually at `ios/Runner/Info.plist`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Location Permissions -->
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>This app needs location access for navigation.</string>
    
    <key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
    <string>This app needs location access for navigation.</string>
    
    <!-- Audio Background Mode (REQUIRED for voice instructions) -->
    <key>UIBackgroundModes</key>
    <array>
        <string>audio</string>
        <string>location</string>
    </array>
    
    <!-- Optional: Location Always (if you need background navigation) -->
    <key>NSLocationAlwaysUsageDescription</key>
    <string>This app needs location access for navigation in the background.</string>
</dict>
</plist>
```

## Key Fixes

1. ✅ **Fixed memory leak** - Store `routeProgressSubscription` properly
2. ✅ **Added session state monitoring** - Track session state changes
3. ✅ **Added synthesizer mute check** - Ensure not muted
4. ✅ **Added route validation** - Check route exists before starting
5. ✅ **Improved error handling** - Better error messages
6. ✅ **Added cleanup** - Cancel all subscriptions properly
7. ✅ **Added debugging** - More logging to help diagnose issues

## Testing Checklist

1. ✅ Verify location permissions are granted
2. ✅ Check session transitions to `.activeGuidance`
3. ✅ Verify synthesizer is not muted
4. ✅ Check route has instructions
5. ✅ Monitor location updates are flowing
6. ✅ Watch for voice instruction events

## Expected Console Output

When working correctly, you should see:
```
🚀 Starting active navigation...
🔍 Session state: activeGuidance(...)
✅ Session is in activeGuidance state
🔊 Synthesizer muted: false
🎤 Subscribing to navigator voice instructions...
📍 Route progress update:
   Current instruction: Turn right in 200 meters
🎤 ✅✅✅ NAVIGATOR VOICE INSTRUCTION: Turn right in 200 meters
```
