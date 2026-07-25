# Complete Voice Instruction Fix - Manual Trigger Approach

## Problem Analysis

The native navigation engine's `NavigationStatus.voiceInstruction` may be nil even when:
- ✅ Route has instructions
- ✅ Location updates are working
- ✅ Navigation is active

This happens because the engine only sets `voiceInstruction` when it determines you're at the right distance/position for an instruction.

## Solution: Manual Instruction Triggering

Since the automatic triggers aren't working, we'll manually check route progress and trigger instructions based on distance.

## Complete Fixed Code

```swift
@MainActor
public class MapboxNavigationBridge: NSObject, FlutterPlugin, FlutterStreamHandler {
    
    // ... existing properties ...
    
    private var navigatorVoiceSubscription: AnyCancellable?
    private var voiceInstructionSubscription: AnyCancellable?
    private var routeProgressSubscription: AnyCancellable?
    private var locationSubscription: AnyCancellable?
    
    // Track which instructions have been spoken
    private var spokenInstructionIndices: Set<Int> = []
    private var currentStepIndex: Int = 0
    private var currentLegIndex: Int = 0
    
    // ... existing code ...
    
    func startActiveNavigation(call: FlutterMethodCall, result: @escaping FlutterResult) {
        Task {
            sessionController.startActiveGuidance(with: currentRoutes!, startLegIndex: 0)
            
            // Reset tracking
            spokenInstructionIndices.removeAll()
            currentStepIndex = 0
            currentLegIndex = 0
            
            // Wait for navigation to initialize
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            // Ensure synthesizer is not muted
            routeVoiceController.speechSynthesizer.muted = false
            
            print("🔊 Starting navigation voice monitoring...")
            print("🔊 Session state: \(await sessionController.state)")
            print("🔊 Synthesizer muted: \(routeVoiceController.speechSynthesizer.muted)")
            
            // Subscribe to everything
            subscribeToLocationUpdates()
            subscribeToRouteProgress()
            subscribeToNavigatorVoiceInstructions()
            subscribeToVoiceInstruction()
            
            result(["success": true, "message": "Navigation started"])
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
                    print("🎤 ✅ Navigator voice instruction: \(instruction.text)")
                    
                    let voiceInstructionData: [String: Any] = [
                        "type": "willSpeak",
                        "instruction": instruction.text,
                        "ssmlText": instruction.ssmlText ?? "",
                        "distance": instruction.distanceAlongStep
                    ]
                    
                    self.voiceInstructionHandler?.eventSink?(voiceInstructionData)
                }
            )
    }
    
    // Subscribe to RouteVoiceController (backup)
    private func subscribeToVoiceInstruction() {
        voiceInstructionSubscription?.cancel()
        
        voiceInstructionSubscription = routeVoiceController.speechSynthesizer.voiceInstructions
            .sink(
                receiveCompletion: { completion in
                    print("🎤 RouteVoiceController stream completed: \(completion)")
                },
                receiveValue: { [weak self] event in
                    guard let self = self else { return }
                    
                    if let willSpeak = event as? VoiceInstructionEvents.WillSpeak {
                        print("🎤 ✅ RouteVoiceController WillSpeak: \(willSpeak.instruction.text)")
                        
                        let voiceInstructionData: [String: Any] = [
                            "type": "willSpeak",
                            "instruction": willSpeak.instruction.text,
                            "ssmlText": willSpeak.instruction.ssmlText ?? "",
                            "distance": willSpeak.instruction.distanceAlongStep
                        ]
                        
                        self.voiceInstructionHandler?.eventSink?(voiceInstructionData)
                    }
                }
            )
    }
    
    // Enhanced route progress subscription with manual triggering
    private func subscribeToRouteProgress() {
        routeProgressSubscription?.cancel()
        
        routeProgressSubscription = navigationController.routeProgress
            .sink { [weak self] state in
                guard let self = self, let routeProgress = state?.routeProgress else { return }
                
                let stepProgress = routeProgress.currentLegProgress.currentStepProgress
                let instruction = stepProgress.currentSpokenInstruction
                
                // Debug info
                print("📍 Route progress:")
                print("   Distance traveled: \(routeProgress.distanceTraveled)m")
                print("   Current instruction: \(instruction?.text ?? "NONE")")
                print("   Step distance traveled: \(stepProgress.distanceTraveled)m")
                
                // MANUAL TRIGGER: Check if we should trigger an instruction
                self.checkAndTriggerManualInstruction(routeProgress: routeProgress)
            }
    }
    
    // NEW: Manually trigger instructions based on distance
    private func checkAndTriggerManualInstruction(routeProgress: RouteProgress) {
        guard let route = currentRoutes?.mainRoute.route else { return }
        
        let legProgress = routeProgress.currentLegProgress
        let stepProgress = legProgress.currentStepProgress
        let currentStep = stepProgress.step
        
        // Get all instructions for current step
        guard let allInstructions = currentStep.instructionsSpokenAlongStep,
              !allInstructions.isEmpty else {
            return
        }
        
        // Find the next instruction that should be spoken
        for (index, instruction) in allInstructions.enumerated() {
            let instructionKey = "\(currentLegIndex)-\(currentStepIndex)-\(index)"
            let hasBeenSpoken = spokenInstructionIndices.contains(index)
            
            // Calculate distance to instruction
            let distanceToInstruction = instruction.distanceAlongStep - stepProgress.distanceTraveled
            
            // Trigger if we're within 50 meters of the instruction and haven't spoken it yet
            if distanceToInstruction <= 50 && distanceToInstruction >= -10 && !hasBeenSpoken {
                print("🎤 🔔 MANUAL TRIGGER: \(instruction.text) (distance: \(distanceToInstruction)m)")
                
                // Mark as spoken
                spokenInstructionIndices.insert(index)
                
                // Send to Flutter
                let voiceInstructionData: [String: Any] = [
                    "type": "willSpeak",
                    "instruction": instruction.text,
                    "ssmlText": instruction.ssmlText ?? "",
                    "distance": instruction.distanceAlongStep
                ]
                
                voiceInstructionHandler?.eventSink?(voiceInstructionData)
                
                // Also trigger the synthesizer manually
                routeVoiceController.speechSynthesizer.speak(
                    instruction,
                    during: legProgress,
                    locale: routeProgress.route.speechLocale ?? Locale.current
                )
                
                // Only trigger one instruction at a time
                break
            }
        }
        
        // Update step/leg indices if needed
        if let stepIndex = route.legs[safe: currentLegIndex]?.steps.firstIndex(where: { $0 === currentStep }) {
            currentStepIndex = stepIndex
        }
    }
    
    private func subscribeToLocationUpdates() {
        locationSubscription?.cancel()
        
        locationSubscription = navigationController.locationMatching
            .sink { [weak self] locationMatching in
                guard let self = self else { return }
                
                let matchedLocation = locationMatching.location
                print("📍 Location: \(matchedLocation.coordinate.latitude), \(matchedLocation.coordinate.longitude)")
                print("📍 Speed: \(matchedLocation.speed) m/s")
                
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
    
    // ... rest of your code ...
}

// Helper extension for safe array access
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
```

## Key Changes

1. **Manual Instruction Triggering** - `checkAndTriggerManualInstruction()` checks distance to each instruction and triggers when within 50m
2. **Multiple Subscriptions** - Subscribe to both navigator and RouteVoiceController
3. **Enhanced Debugging** - More detailed logging
4. **Instruction Tracking** - Prevents duplicate triggers

## Alternative: Simpler Distance-Based Trigger

If the above is too complex, use this simpler version:

```swift
private func subscribeToRouteProgress() {
    routeProgressSubscription?.cancel()
    
    routeProgressSubscription = navigationController.routeProgress
        .sink { [weak self] state in
            guard let self = self,
                  let routeProgress = state?.routeProgress,
                  let route = self.currentRoutes?.mainRoute.route else { return }
            
            let stepProgress = routeProgress.currentLegProgress.currentStepProgress
            let currentStep = stepProgress.step
            
            // Get first instruction that hasn't been spoken
            if let instructions = currentStep.instructionsSpokenAlongStep,
               let firstInstruction = instructions.first,
               stepProgress.distanceTraveled >= firstInstruction.distanceAlongStep - 50,
               stepProgress.distanceTraveled <= firstInstruction.distanceAlongStep + 10 {
                
                print("🎤 🔔 Triggering: \(firstInstruction.text)")
                
                // Send to Flutter
                let voiceInstructionData: [String: Any] = [
                    "type": "willSpeak",
                    "instruction": firstInstruction.text,
                    "ssmlText": firstInstruction.ssmlText ?? "",
                    "distance": firstInstruction.distanceAlongStep
                ]
                
                self.voiceInstructionHandler?.eventSink?(voiceInstructionData)
            }
        }
}
```

## Debug Checklist

Add this to verify everything:

```swift
func startActiveNavigation(...) {
    Task {
        // ... start navigation ...
        
        // Debug session state
        let sessionState = await sessionController.state
        print("🔍 Session state: \(sessionState)")
        
        // Debug route
        if let route = currentRoutes?.mainRoute.route {
            print("🔍 Route has \(route.legs.count) legs")
            for (legIdx, leg) in route.legs.enumerated() {
                print("🔍 Leg \(legIdx): \(leg.steps.count) steps")
                for (stepIdx, step) in leg.steps.enumerated() {
                    let instructions = step.instructionsSpokenAlongStep ?? []
                    print("🔍   Step \(stepIdx): \(instructions.count) instructions")
                }
            }
        }
    }
}
```

Try the manual triggering approach - it should work even if the native engine isn't emitting voice instructions.
