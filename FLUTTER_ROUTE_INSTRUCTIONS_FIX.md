# Fix: Route Has 0 Instructions

## Problem
Your route has 0 spoken instructions, so voice events will never fire.

## Root Cause
The `NavigationRouteOptions` needs to explicitly enable `includesSpokenInstructions = true`. While it should be set by default via `optimizeForNavigation()`, you should verify it's enabled.

## Solution: Update Route Calculation

Update your `handleCalculateRoute` method to ensure spoken instructions are included:

```swift
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
    
    // Create route options with spoken instructions ENABLED
    let options = NavigationRouteOptions(
        coordinates: [startCoord, endCoord],
        profileIdentifier: profile
    )
    
    // CRITICAL: Ensure spoken instructions are included
    options.includesSpokenInstructions = true
    options.includesVisualInstructions = true
    options.includesSteps = true
    options.locale = Locale.current // or Locale(identifier: "en-US")
    
    // Debug: Verify options
    print("📍 Route options:")
    print("   includesSpokenInstructions: \(options.includesSpokenInstructions)")
    print("   includesVisualInstructions: \(options.includesVisualInstructions)")
    print("   includesSteps: \(options.includesSteps)")
    print("   locale: \(options.locale.identifier)")
    
    Task {
        do {
            let routes = try await self.calculateRoute(options: options)
            self.currentRoutes = routes
            
            // DEBUG: Verify route has instructions
            if let route = routes.mainRoute.route {
                print("📍 Route calculated:")
                print("   Legs: \(route.legs.count)")
                for (legIndex, leg) in route.legs.enumerated() {
                    print("   Leg \(legIndex): \(leg.steps.count) steps")
                    for (stepIndex, step) in leg.steps.enumerated() {
                        let instructions = step.instructionsSpokenAlongStep ?? []
                        print("     Step \(stepIndex): \(instructions.count) spoken instructions")
                        if instructions.isEmpty {
                            print("     ⚠️ WARNING: Step has NO spoken instructions!")
                        } else {
                            for (idx, instruction) in instructions.enumerated() {
                                print("       \(idx): \(instruction.text) (at \(instruction.distanceAlongStep)m)")
                            }
                        }
                    }
                }
            }
            
            // Convert routes to dictionary for Flutter
            let routeData = self.convertRoutesToDictionary(routes)
            result(routeData)
        } catch {
            result(FlutterError(
                code: "ROUTE_ERROR",
                message: error.localizedDescription,
                details: nil
            ))
        }
    }
}
```

## Additional Checks

### 1. Verify Route Response Includes Instructions

After calculating the route, check if the raw route response has instructions:

```swift
// After calculating route
if let route = currentRoutes?.mainRoute.route {
    let firstStep = route.legs.first?.steps.first
    print("📍 First step has instructions: \(firstStep?.instructionsSpokenAlongStep?.count ?? 0)")
    
    // Check if step has any instructions at all
    if let step = firstStep {
        print("📍 Step maneuver: \(step.maneuverType)")
        print("📍 Step instructions: \(step.instructionsSpokenAlongStep?.count ?? 0)")
        print("📍 Step visual instructions: \(step.instructionsDisplayedAlongStep?.count ?? 0)")
    }
}
```

### 2. Check Route Distance

Very short routes might not have instructions. Check the route distance:

```swift
if let route = currentRoutes?.mainRoute.route {
    let totalDistance = route.distance
    print("📍 Route distance: \(totalDistance)m")
    
    if totalDistance < 50 {
        print("⚠️ Route is very short (\(totalDistance)m) - might not have instructions")
    }
}
```

### 3. Ensure Locale is Set

The API needs a locale to generate instructions:

```swift
let options = NavigationRouteOptions(
    coordinates: [startCoord, endCoord],
    profileIdentifier: profile
)
options.locale = Locale(identifier: "en-US") // or Locale.current
options.includesSpokenInstructions = true
```

## Common Issues

1. **Route too short** - Routes under ~50m might not have instructions
2. **Locale not set** - API needs locale to generate instructions
3. **Profile doesn't support instructions** - Some profiles might not generate instructions
4. **API response doesn't include instructions** - Check the raw response

## Test Route

Try with a longer route that definitely has turns:

```swift
// Example: Route with multiple turns
let startCoord = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194) // San Francisco
let endCoord = CLLocationCoordinate2D(latitude: 37.7849, longitude: -122.4094) // Different location

let options = NavigationRouteOptions(
    coordinates: [startCoord, endCoord],
    profileIdentifier: .automobile
)
options.includesSpokenInstructions = true
options.locale = Locale(identifier: "en-US")
```

## Expected Output After Fix

You should see:
```
📍 Route options:
   includesSpokenInstructions: true
📍 Route calculated:
   Legs: 1
   Leg 0: 5 steps
     Step 0: 1 spoken instructions
       0: Head north on Market Street (at 0.0m)
     Step 1: 1 spoken instructions
       0: Turn right on Mission Street (at 150.0m)
```

If you still see 0 instructions after this fix, the issue is with the API response, not your code.
