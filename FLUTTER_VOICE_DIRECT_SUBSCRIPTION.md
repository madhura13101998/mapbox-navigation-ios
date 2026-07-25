# Direct Voice Instruction Subscription Fix

## Problem

Even though:
- ✅ Route has instructions
- ✅ Location updates are working
- ✅ Map matching is working

The `RouteVoiceController`'s `speechSynthesizer.voiceInstructions` isn't emitting events because `currentSpokenInstruction` is nil in route progress.

## Root Cause

The `RouteVoiceController` only triggers when `routeProgress.currentSpokenInstruction` is set, which depends on the native navigation engine's `NavigationStatus.voiceInstruction`. This may be nil even when instructions exist in the route.

## Solution: Subscribe to Navigator's Voice Instructions Directly

The `MapboxNavigator` has its own `voiceInstructions` publisher that emits `SpokenInstructionState` directly from the native engine. Subscribe to this instead of (or in addition to) the RouteVoiceController.

## Fixed Code

```swift
@MainActor
public class MapboxNavigationBridge: NSObject, FlutterPlugin, FlutterStreamHandler {
    
    // ... existing properties ...
    
    // ADD THIS - Direct subscription to navigator voice instructions
    private var navigatorVoiceSubscription: AnyCancellable?
    
    // ... existing code ...
    
    func startActiveNavigation(call: FlutterMethodCall, result: @escaping FlutterResult) {
        Task {
            sessionController.startActiveGuidance(with: currentRoutes!, startLegIndex: 0)
            
            // Wait for navigation to initialize
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Ensure synthesizer is not muted
            routeVoiceController.speechSynthesizer.muted = false
            
            // Subscribe to location updates
            subscribeToLocationUpdates()
            
            // Subscribe to route progress (for debugging)
            subscribeToRouteProgress()
            
            // CRITICAL: Subscribe to navigator's voice instructions directly
            subscribeToNavigatorVoiceInstructions()
            
            // Also subscribe to RouteVoiceController (as backup)
            subscribeToVoiceInstruction()
            
            result(["success": true, "message": "Navigation started"])
        }
    }
    
    // NEW: Subscribe to navigator's voice instructions directly
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
                    print("🎤 Navigator voice instruction: \(instruction.text)")
                    print("🎤 Distance: \(instruction.distanceAlongStep)m")
                    
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
        
        print("🎤 Navigator voice subscription stored: \(navigatorVoiceSubscription != nil)")
    }
    
    // Also subscribe to RouteVoiceController (for completeness)
    private func subscribeToVoiceInstruction() {
        voiceInstructionSubscription?.cancel()
        
        print("🎤 Subscribing to RouteVoiceController voice instructions...")
        
        voiceInstructionSubscription = routeVoiceController.speechSynthesizer.voiceInstructions
            .sink(
                receiveCompletion: { completion in
                    print("🎤 RouteVoiceController stream completed: \(completion)")
                },
                receiveValue: { [weak self] event in
                    guard let self = self else { return }
                    
                    print("🎤 RouteVoiceController event: \(type(of: event))")
                    
                    switch event {
                    case let willSpeak as VoiceInstructionEvents.WillSpeak:
                        print("🎤 RouteVoiceController WillSpeak: \(willSpeak.instruction.text)")
                        
                        let voiceInstructionData: [String: Any] = [
                            "type": "willSpeak",
                            "instruction": willSpeak.instruction.text,
                            "ssmlText": willSpeak.instruction.ssmlText ?? "",
                            "distance": willSpeak.instruction.distanceAlongStep
                        ]
                        
                        self.voiceInstructionHandler?.eventSink?(voiceInstructionData)
                        
                    case let didSpeak as VoiceInstructionEvents.DidSpeak:
                        print("🎤 RouteVoiceController DidSpeak: \(didSpeak.instruction.text)")
                        
                    default:
                        break
                    }
                }
            )
    }
    
    private func handleStopNavigation(call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Cancel all subscriptions
        locationSubscription?.cancel()
        locationSubscription = nil
        
        voiceInstructionSubscription?.cancel()
        voiceInstructionSubscription = nil
        
        navigatorVoiceSubscription?.cancel() // ADD THIS
        navigatorVoiceSubscription = nil
        
        routeProgressSubscription?.cancel()
        routeProgressSubscription = nil
        
        sessionController.stop()
        
        result(["success": true, "message": "Navigation stopped"])
    }
}
```

## Key Differences

1. **Navigator's `voiceInstructions`** - Emits `SpokenInstructionState` directly from native engine when it determines an instruction should be spoken
2. **RouteVoiceController's `voiceInstructions`** - Emits `VoiceInstructionEvent` only after it calls `speak()` on the synthesizer, which only happens when `currentSpokenInstruction` is set

## Why This Works

The navigator's `voiceInstructions` publisher is triggered by the native navigation engine's `NavigationStatus.voiceInstruction`, which is set based on:
- Your position along the route
- Distance to the next maneuver
- The engine's internal logic

This is more reliable than waiting for `currentSpokenInstruction` to be set in route progress.

## Debugging

Add this to see both streams:

```swift
// In subscribeToNavigatorVoiceInstructions
print("🎤 Navigator voice instruction received:")
print("   Text: \(instruction.text)")
print("   SSML: \(instruction.ssmlText ?? "none")")
print("   Distance: \(instruction.distanceAlongStep)m")

// In subscribeToVoiceInstruction  
print("🎤 RouteVoiceController event received:")
print("   Type: \(type(of: event))")
```

You should see events from the navigator's stream even if RouteVoiceController doesn't emit.
