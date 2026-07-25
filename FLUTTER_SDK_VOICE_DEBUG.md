# SDK Voice Instructions Debugging Guide

## Problem
The SDK's native voice instruction system isn't emitting events even though:
- ✅ Route has instructions
- ✅ Location updates are working
- ✅ Navigation is active

## Root Cause Analysis

The SDK emits voice instructions when `NavigationStatus.voiceInstruction` is set by the native engine. This requires:

1. **Session State**: Must be `.activeGuidance`
2. **Billing Session**: Must be active
3. **Route Set**: Routes must be properly set in native navigator
4. **Location Updates**: Native navigator must receive location updates
5. **activeGuidanceInfo**: `NavigationStatus.activeGuidanceInfo` must not be nil
6. **voiceInstruction**: `NavigationStatus.voiceInstruction` must be set by native engine

## Complete Debugging Code

Add this comprehensive debugging to your Flutter bridge:

```swift
@MainActor
public class MapboxNavigationBridge: NSObject, FlutterPlugin, FlutterStreamHandler {
    
    // ... existing properties ...
    
    private var sessionSubscription: AnyCancellable?
    private var navigatorVoiceSubscription: AnyCancellable?
    private var routeProgressSubscription: AnyCancellable?
    private var locationSubscription: AnyCancellable?
    private var errorsSubscription: AnyCancellable?
    
    // ... existing code ...
    
    func startActiveNavigation(call: FlutterMethodCall, result: @escaping FlutterResult) {
        Task {
            print("🚀 Starting active navigation...")
            
            // 1. Verify route has instructions
            if let route = currentRoutes?.mainRoute.route {
                var totalInstructions = 0
                for leg in route.legs {
                    for step in leg.steps {
                        totalInstructions += step.instructionsSpokenAlongStep?.count ?? 0
                    }
                }
                print("📍 Route has \(totalInstructions) total spoken instructions")
                
                if totalInstructions == 0 {
                    print("⚠️ ERROR: Route has NO spoken instructions!")
                    result(FlutterError(
                        code: "NO_INSTRUCTIONS",
                        message: "Route has no spoken instructions. Check route options.",
                        details: nil
                    ))
                    return
                }
            }
            
            // 2. Start active guidance
            sessionController.startActiveGuidance(with: currentRoutes!, startLegIndex: 0)
            
            // 3. Wait for initialization
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            // 4. Subscribe to everything for debugging
            subscribeToSessionState()
            subscribeToNavigatorVoiceInstructions()
            subscribeToRouteProgress()
            subscribeToLocationUpdates()
            subscribeToErrors()
            
            // 5. Verify session state
            let sessionState = await sessionController.state
            print("🔍 Session state: \(sessionState)")
            
            if case .activeGuidance = sessionState {
                print("✅ Session is in activeGuidance state")
            } else {
                print("❌ ERROR: Session is NOT in activeGuidance state: \(sessionState)")
            }
            
            // 6. Ensure synthesizer is not muted
            routeVoiceController.speechSynthesizer.muted = false
            print("🔊 Synthesizer muted: \(routeVoiceController.speechSynthesizer.muted)")
            
            result(["success": true, "message": "Navigation started"])
        }
    }
    
    // Monitor session state changes
    private func subscribeToSessionState() {
        sessionSubscription?.cancel()
        
        sessionSubscription = sessionController.session
            .sink { [weak self] session in
                print("🔍 Session state changed: \(session.state)")
                
                switch session.state {
                case .idle:
                    print("⚠️ Session is IDLE - voice instructions won't work")
                case .freeDrive:
                    print("⚠️ Session is FREE DRIVE - voice instructions won't work")
                case .activeGuidance(let state):
                    print("✅ Session is ACTIVE GUIDANCE")
                    print("   Route state: \(state.routeState)")
                }
            }
    }
    
    // Subscribe to navigator's voice instructions (primary)
    private func subscribeToNavigatorVoiceInstructions() {
        navigatorVoiceSubscription?.cancel()
        
        print("🎤 Subscribing to navigator voice instructions...")
        
        navigatorVoiceSubscription = navigationController.voiceInstructions
            .sink(
                receiveCompletion: { completion in
                    print("🎤 Navigator voice stream completed: \(completion)")
                },
                receiveValue: { [weak self] spokenInstructionState in
                    guard let self = self else { return }
                    
                    let instruction = spokenInstructionState.spokenInstruction
                    print("🎤 ✅✅✅ NAVIGATOR VOICE INSTRUCTION RECEIVED: \(instruction.text)")
                    print("   Distance: \(instruction.distanceAlongStep)m")
                    print("   SSML: \(instruction.ssmlText ?? "none")")
                    
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
        
        print("🎤 Navigator voice subscription created: \(navigatorVoiceSubscription != nil)")
    }
    
    // Enhanced route progress subscription with detailed debugging
    private func subscribeToRouteProgress() {
        routeProgressSubscription?.cancel()
        
        routeProgressSubscription = navigationController.routeProgress
            .sink { [weak self] state in
                guard let self = self else {
                    print("📍 Route progress state is nil")
                    return
                }
                
                guard let routeProgress = state?.routeProgress else {
                    print("📍 Route progress is nil")
                    return
                }
                
                let stepProgress = routeProgress.currentLegProgress.currentStepProgress
                let instruction = stepProgress.currentSpokenInstruction
                
                // Detailed debugging
                print("📍 Route progress update:")
                print("   Total distance traveled: \(routeProgress.distanceTraveled)m")
                print("   Step distance traveled: \(stepProgress.distanceTraveled)m")
                print("   Step distance remaining: \(stepProgress.distanceRemaining)m")
                print("   Current instruction: \(instruction?.text ?? "NONE")")
                print("   Spoken instruction index: \(stepProgress.spokenInstructionIndex?.description ?? "nil")")
                
                // Check if step has instructions
                if let allInstructions = stepProgress.step.instructionsSpokenAlongStep {
                    print("   Step has \(allInstructions.count) total instructions")
                    for (idx, inst) in allInstructions.enumerated() {
                        let distanceToInst = inst.distanceAlongStep - stepProgress.distanceTraveled
                        print("     [\(idx)] \(inst.text) (at \(inst.distanceAlongStep)m, \(distanceToInst)m away)")
                    }
                } else {
                    print("   ⚠️ Step has NO instructions")
                }
                
                // Check remaining instructions
                if let remaining = stepProgress.remainingSpokenInstructions {
                    print("   Remaining instructions: \(remaining.count)")
                    if let next = remaining.first {
                        let distanceToNext = next.distanceAlongStep - stepProgress.distanceTraveled
                        print("   Next instruction in \(distanceToNext)m: \(next.text)")
                    }
                }
                
                // CRITICAL: If instruction exists but wasn't emitted, something is wrong
                if instruction != nil {
                    print("   ✅ currentSpokenInstruction EXISTS but may not have been emitted yet")
                } else {
                    print("   ❌ currentSpokenInstruction is NIL")
                }
            }
    }
    
    // Monitor location updates
    private func subscribeToLocationUpdates() {
        locationSubscription?.cancel()
        
        locationSubscription = navigationController.locationMatching
            .sink { [weak self] locationMatching in
                guard let self = self else { return }
                
                let matchedLocation = locationMatching.location
                print("📍 Location update:")
                print("   Coordinate: \(matchedLocation.coordinate.latitude), \(matchedLocation.coordinate.longitude)")
                print("   Speed: \(matchedLocation.speed) m/s")
                print("   Accuracy: \(matchedLocation.horizontalAccuracy)m")
                print("   Course: \(matchedLocation.course)°")
                
                // Send to Flutter
                self.sendLocationUpdate(
                    latitude: matchedLocation.coordinate.latitude,
                    longitude: matchedLocation.coordinate.longitude,
                    accuracy: matchedLocation.horizontalAccuracy,
                    heading: matchedLocation.course,
                    speed: matchedLocation.speed
                )
            }
    }
    
    // Monitor errors
    private func subscribeToErrors() {
        errorsSubscription?.cancel()
        
        errorsSubscription = navigationController.errors
            .sink { [weak self] error in
                print("❌ Navigator error: \(error)")
                
                // Check for specific errors that might prevent voice instructions
                if let navError = error as? NavigatorErrors.UnexpectedNavigationStatus {
                    print("❌ CRITICAL: Received NavigationStatus while session is idle")
                }
            }
    }
    
    private func handleStopNavigation(call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Cancel all subscriptions
        sessionSubscription?.cancel()
        navigatorVoiceSubscription?.cancel()
        routeProgressSubscription?.cancel()
        locationSubscription?.cancel()
        errorsSubscription?.cancel()
        
        sessionSubscription = nil
        navigatorVoiceSubscription = nil
        routeProgressSubscription = nil
        locationSubscription = nil
        errorsSubscription = nil
        
        sessionController.stop()
        
        result(["success": true, "message": "Navigation stopped"])
    }
}
```

## What to Look For

After adding this debugging code, check your console logs for:

### ✅ Good Signs:
- `✅ Session is ACTIVE GUIDANCE`
- `📍 Route has X total spoken instructions` (where X > 0)
- `📍 Location update:` (regular updates)
- `📍 Route progress update:` (regular updates)
- `✅ currentSpokenInstruction EXISTS`

### ❌ Problem Signs:
- `❌ Session is NOT in activeGuidance state`
- `⚠️ Route has NO spoken instructions`
- `📍 Route progress is nil`
- `❌ currentSpokenInstruction is NIL` (always)
- `❌ CRITICAL: Received NavigationStatus while session is idle`
- No location updates
- No route progress updates

## Common Issues and Fixes

### Issue 1: Session Not in Active Guidance
**Symptom**: `Session is NOT in activeGuidance state`

**Fix**: Ensure you're calling `sessionController.startActiveGuidance()` and waiting for it to complete:

```swift
sessionController.startActiveGuidance(with: currentRoutes!, startLegIndex: 0)

// Wait longer if needed
try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
```

### Issue 2: No Location Updates
**Symptom**: No `📍 Location update:` logs

**Fix**: Ensure location permissions are granted and location is being simulated/updated.

### Issue 3: Route Progress Always Nil
**Symptom**: `📍 Route progress is nil` always

**Fix**: The route might not be properly set. Verify:
- Route is calculated correctly
- `currentRoutes` is not nil
- Route has valid steps

### Issue 4: currentSpokenInstruction Always Nil
**Symptom**: `❌ currentSpokenInstruction is NIL` always, even when moving

**Fix**: This means `NavigationStatus.voiceInstruction` is nil. Possible causes:
- Native engine hasn't processed location yet
- You're not close enough to any instruction
- Route format issue

**Try**: Wait longer, move further along the route, or check if the route format is correct.

## Expected Behavior

When everything works correctly, you should see:
1. Session transitions to `.activeGuidance`
2. Location updates start flowing
3. Route progress updates start
4. `currentSpokenInstruction` becomes non-nil when approaching a turn
5. `🎤 ✅✅✅ NAVIGATOR VOICE INSTRUCTION RECEIVED` appears

If you see all of these but still no voice events, the issue is in the subscription or event sink.
