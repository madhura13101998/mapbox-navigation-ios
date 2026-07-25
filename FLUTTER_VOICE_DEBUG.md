# Voice Instruction Events Debugging Guide

## Common Issues & Solutions

### 1. **Subscription Not Stored (CRITICAL)**
The subscription MUST be stored, otherwise it's immediately deallocated.

```swift
// ❌ WRONG - subscription is deallocated immediately
routeVoiceController.speechSynthesizer.voiceInstructions
    .sink { event in ... }

// ✅ CORRECT - subscription is stored
private var voiceInstructionSubscription: AnyCancellable?

voiceInstructionSubscription = routeVoiceController.speechSynthesizer.voiceInstructions
    .sink { [weak self] event in
        // ...
    }
```

### 2. **Synthesizer Might Be Muted**
Check if the synthesizer is muted:

```swift
print("Synthesizer muted: \(routeVoiceController.speechSynthesizer.muted)")
routeVoiceController.speechSynthesizer.muted = false // Ensure not muted
```

### 3. **Route Progress Not Emitting**
The `RouteVoiceController` only triggers when route progress has `currentSpokenInstruction`. Verify navigation is actually progressing:

```swift
// Subscribe to route progress to debug
navigationController.routeProgress
    .sink { [weak self] state in
        if let routeProgress = state?.routeProgress {
            let instruction = routeProgress.currentLegProgress.currentStepProgress.currentSpokenInstruction
            print("Current spoken instruction: \(instruction?.text ?? "nil")")
            print("Route progress distance: \(routeProgress.distanceTraveled)")
        } else {
            print("Route progress is nil")
        }
    }
    .store(in: &subscriptions)
```

### 4. **Navigation Not Properly Started**
Ensure navigation is actually active:

```swift
// Check if navigation is active
print("Navigation state: \(navigationController.state)")
print("Is navigating: \(sessionController.isActive)")
```

### 5. **Synthesizer Type Matters**
Different synthesizers emit events differently. Check which one you're using:

```swift
print("Synthesizer type: \(type(of: routeVoiceController.speechSynthesizer))")
```

### 6. **Timing Issue - Subscribe AFTER Navigation Starts**
The voice controller might be created before navigation starts. Try subscribing AFTER starting navigation:

```swift
func startActiveNavigation(call: FlutterMethodCall, result: @escaping FlutterResult) {
    Task {
        sessionController.startActiveGuidance(with: currentRoutes!, startLegIndex: 0)
        
        // Wait a bit for navigation to initialize
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // NOW subscribe to voice instructions
        subscribeToVoiceInstruction()
        subscribeToLocationUpdates()
        
        result(["success": true, "message": "Navigation started"])
    }
}
```

## Complete Fixed Code

```swift
@MainActor
public class MapboxNavigationBridge: NSObject, FlutterPlugin, FlutterStreamHandler {
    
    // ... existing properties ...
    
    // ADD THIS
    private var voiceInstructionSubscription: AnyCancellable?
    private var routeProgressSubscription: AnyCancellable? // For debugging
    
    // ... existing code ...
    
    func startActiveNavigation(call: FlutterMethodCall, result: @escaping FlutterResult) {
        Task {
            // Start navigation first
            sessionController.startActiveGuidance(with: currentRoutes!, startLegIndex: 0)
            
            // Wait for navigation to initialize
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Ensure synthesizer is not muted
            routeVoiceController.speechSynthesizer.muted = false
            
            // Debug: Check synthesizer state
            print("🔊 Synthesizer muted: \(routeVoiceController.speechSynthesizer.muted)")
            print("🔊 Synthesizer type: \(type(of: routeVoiceController.speechSynthesizer))")
            print("🔊 Synthesizer locale: \(routeVoiceController.speechSynthesizer.locale?.identifier ?? "nil")")
            
            // Subscribe to route progress for debugging
            subscribeToRouteProgress()
            
            // Subscribe to voice instructions
            subscribeToVoiceInstruction()
            
            // Subscribe to location updates
            subscribeToLocationUpdates()
            
            result(["success": true, "message": "Navigation started"])
        }
    }
    
    // ADD THIS - Debug route progress
    private func subscribeToRouteProgress() {
        routeProgressSubscription?.cancel()
        
        routeProgressSubscription = navigationController.routeProgress
            .sink { [weak self] state in
                guard let self = self else { return }
                
                if let routeProgress = state?.routeProgress {
                    let instruction = routeProgress.currentLegProgress.currentStepProgress.currentSpokenInstruction
                    print("📍 Route progress - Distance: \(routeProgress.distanceTraveled)m")
                    print("📍 Current instruction: \(instruction?.text ?? "NONE")")
                    print("📍 Instruction distance: \(instruction?.distanceAlongStep ?? 0)m")
                } else {
                    print("📍 Route progress is nil")
                }
            }
    }
    
    // FIXED - Voice instruction subscription
    private func subscribeToVoiceInstruction() {
        // Cancel existing subscription
        voiceInstructionSubscription?.cancel()
        
        print("🎤 Subscribing to voice instructions...")
        
        // Store the subscription
        voiceInstructionSubscription = routeVoiceController.speechSynthesizer.voiceInstructions
            .sink(
                receiveCompletion: { completion in
                    print("🎤 Voice instruction stream completed: \(completion)")
                },
                receiveValue: { [weak self] event in
                    guard let self = self else { return }
                    
                    print("🎤 Voice event received: \(type(of: event))")
                    
                    switch event {
                    case let willSpeak as VoiceInstructionEvents.WillSpeak:
                        print("🎤 WillSpeak: \(willSpeak.instruction.text)")
                        
                        let voiceInstructionData: [String: Any] = [
                            "type": "willSpeak",
                            "instruction": willSpeak.instruction.text,
                            "ssmlText": willSpeak.instruction.ssmlText ?? "",
                            "distance": willSpeak.instruction.distanceAlongStep
                        ]
                        
                        self.voiceInstructionHandler?.eventSink?(voiceInstructionData)
                        
                    case let didSpeak as VoiceInstructionEvents.DidSpeak:
                        print("🎤 DidSpeak: \(didSpeak.instruction.text)")
                        
                        let voiceInstructionData: [String: Any] = [
                            "type": "didSpeak",
                            "instruction": didSpeak.instruction.text,
                            "ssmlText": didSpeak.instruction.ssmlText ?? "",
                            "distance": didSpeak.instruction.distanceAlongStep
                        ]
                        
                        self.voiceInstructionHandler?.eventSink?(voiceInstructionData)
                        
                    case let didInterrupt as VoiceInstructionEvents.DidInterrupt:
                        print("🎤 DidInterrupt")
                        
                        let voiceInstructionData: [String: Any] = [
                            "type": "didInterrupt",
                            "interruptedInstruction": didInterrupt.interruptedInstruction.text,
                            "interruptingInstruction": didInterrupt.interruptingInstruction.text
                        ]
                        
                        self.voiceInstructionHandler?.eventSink?(voiceInstructionData)
                        
                    case let error as VoiceInstructionEvents.EncounteredError:
                        print("🎤 Error: \(error.error)")
                        
                        let voiceInstructionData: [String: Any] = [
                            "type": "error",
                            "error": error.error.localizedDescription
                        ]
                        
                        self.voiceInstructionHandler?.eventSink?(voiceInstructionData)
                        
                    default:
                        print("🎤 Unknown event type: \(type(of: event))")
                    }
                }
            )
        
        print("🎤 Subscription stored: \(voiceInstructionSubscription != nil)")
    }
    
    private func handleStopNavigation(call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Cancel all subscriptions
        locationSubscription?.cancel()
        locationSubscription = nil
        
        voiceInstructionSubscription?.cancel()
        voiceInstructionSubscription = nil
        
        routeProgressSubscription?.cancel()
        routeProgressSubscription = nil
        
        sessionController.stop()
        
        result(["success": true, "message": "Navigation stopped"])
    }
}
```

## Debugging Checklist

1. ✅ **Subscription is stored** - `voiceInstructionSubscription` property exists and is assigned
2. ✅ **Synthesizer not muted** - `speechSynthesizer.muted = false`
3. ✅ **Navigation is active** - `sessionController.isActive == true`
4. ✅ **Route progress is emitting** - Check debug logs for route progress
5. ✅ **Current spoken instruction exists** - Check debug logs
6. ✅ **VoiceInstructionHandler is set up** - `voiceInstructionHandler?.eventSink` is not nil
7. ✅ **Subscribe AFTER navigation starts** - Add delay if needed
8. ✅ **Check synthesizer type** - Different types behave differently

## Test Steps

1. Add all the debug print statements
2. Start navigation
3. Watch console for:
   - "🎤 Subscribing to voice instructions..."
   - "📍 Route progress..." messages
   - "🎤 Voice event received..." messages
4. If you see route progress but no voice events, the synthesizer isn't being triggered
5. If you see no route progress, navigation isn't properly started
