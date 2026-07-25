# Complete Voice Instruction Flow in Mapbox Navigation iOS SDK

## Overview

This document traces the complete flow of how voice instructions are triggered in the Mapbox Navigation iOS SDK, from location updates to voice events.

## Architecture Components

1. **Native Navigator** (C++/Native) - Core navigation engine
2. **MapboxNavigator** - Swift wrapper around native navigator
3. **RouteVoiceController** - Coordinates voice guidance
4. **SpeechSynthesizer** - Handles actual speech synthesis
5. **RouteProgress** - Tracks user progress along route

## Complete Flow

### Step 1: Location Updates → Native Navigator

**Location Source** → **MultiplexLocationClient** → **NativeNavigator**

- Location updates come from `CoreConfig.locationSource`
- `MultiplexLocationClient` forwards them to the native navigator
- Native navigator processes location and matches it to the route

**Code Location:**
- `MapboxNavigationProvider.multiplexLocationClient`
- `MapboxNavigationProvider.navigator()` → `NativeNavigator`

### Step 2: Native Navigator → NavigationStatus

**Native Navigator** processes location and generates `NavigationStatus`:

- Native engine calculates route progress
- Determines if a voice instruction should be triggered
- Sets `NavigationStatus.voiceInstruction` if instruction should be spoken
- Sets `NavigationStatus.activeGuidanceInfo` with progress data

**Key Properties:**
- `NavigationStatus.voiceInstruction` - The instruction to speak (may be nil)
- `NavigationStatus.activeGuidanceInfo` - Progress information
- `NavigationStatus.primaryRouteIndices` - Current step/leg indices

**Code Location:**
- Native C++ code (not in this repo)
- `NavigatorStatusObserver.onStatus()` receives status from native

### Step 3: NavigationStatus → NotificationCenter

**NavigatorStatusObserver** posts notification:

```swift
// Sources/MapboxNavigationCore/Navigator/Internals/CoreNavigator/NavigatorStatusObserver.swift
func onStatus(for origin: NavigationStatusOrigin, status: NavigationStatus) {
    let userInfo: [NativeNavigator.NotificationUserInfoKey: Any] = [
        .statusKey: status
    ]
    NotificationCenter.default.post(
        name: .navigationStatusDidChange, 
        object: nil, 
        userInfo: userInfo
    )
    mostRecentNavigationStatus = status
}
```

**Code Location:**
- `NavigatorStatusObserver.onStatus()`
- Notification: `.navigationStatusDidChange`

### Step 4: NotificationCenter → MapboxNavigator

**MapboxNavigator** receives notification and processes status:

```swift
// Sources/MapboxNavigationCore/Navigator/MapboxNavigator.swift
private func navigationStatusDidChange(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
          let status = userInfo[NativeNavigator.NotificationUserInfoKey.statusKey] as? NavigationStatus
    else { return }
    statusUpdateEvents.yield(status)  // AsyncStream
}
```

**Code Location:**
- `MapboxNavigator.navigationStatusDidChange()`
- `MapboxNavigator.statusUpdateEvents` (AsyncStreamBridge)

### Step 5: AsyncStream → update(to status:)

**MapboxNavigator** processes status in async task:

```swift
// Sources/MapboxNavigationCore/Navigator/MapboxNavigator.swift
self.statusTask = Task.detached { [weak self] in
    for await status in statusUpdateEvents {
        await self?.update(to: status)
    }
}
```

**Code Location:**
- `MapboxNavigator.statusTask`
- `MapboxNavigator.update(to: NavigationStatus)`

### Step 6: update(to:) → RouteProgress Update

**MapboxNavigator.update()** validates and updates route progress:

```swift
// Sources/MapboxNavigationCore/Navigator/MapboxNavigator.swift
private func update(to status: NavigationStatus) async {
    // 1. Validate session state
    guard await currentSession.state != .idle else { return }
    guard await billingSessionIsActive() else { return }
    guard case .activeGuidance = await currentSession.state else { return }
    
    // 2. Update map matching
    await updateMapMatching(status: status)
    
    // 3. Update route progress indices
    await updateIndices(status: status)
    
    // 4. Get updated route progress
    let routeProgress = await state.privateRouteProgress
    
    // 5. Send route progress state
    if let routeProgress, !Task.isCancelled {
        await send(RouteProgressState(routeProgress: routeProgress))
    }
    
    // 6. Handle route progress updates (voice instructions)
    await handleRouteProgressUpdates(status: status, routeProgress: routeProgress)
}
```

**Code Location:**
- `MapboxNavigator.update(to: NavigationStatus)`
- `MapboxNavigator.updateIndices(status: NavigationStatus)`
- `MapboxNavigator.handleRouteProgressUpdates(status:routeProgress:)`

### Step 7: RouteProgress.update() → currentSpokenInstruction

**RouteStepProgress.update()** extracts voice instruction from NavigationStatus:

```swift
// Sources/MapboxNavigationCore/Navigator/RouteProgress/RouteStepProgress.swift
mutating func update(using status: NavigationStatus) {
    guard
        let activeGuidanceInfo = status.activeGuidanceInfo,
        let primaryRouteIndices = status.primaryRouteIndices
    else {
        return  // ⚠️ If these are nil, currentSpokenInstruction won't be set
    }
    
    // Update progress metrics
    distanceTraveled = activeGuidanceInfo.stepProgress.distanceTraveled
    distanceRemaining = activeGuidanceInfo.stepProgress.remainingDistance
    
    // Extract voice instruction from native status
    spokenInstructionIndex = status.voiceInstruction.map { Int($0.index) }
    currentSpokenInstruction = status.voiceInstruction.map(SpokenInstruction.init)
    // ⚠️ If status.voiceInstruction is nil, currentSpokenInstruction will be nil
}
```

**Critical Point:**
- `currentSpokenInstruction` is ONLY set if `status.voiceInstruction` is not nil
- If native engine doesn't set `voiceInstruction`, `currentSpokenInstruction` remains nil

**Code Location:**
- `RouteStepProgress.update(using: NavigationStatus)`
- Line 42: `currentSpokenInstruction = status.voiceInstruction.map(SpokenInstruction.init)`

### Step 8: handleRouteProgressUpdates() → Navigator voiceInstructions

**MapboxNavigator.handleRouteProgressUpdates()** emits voice instruction if present:

```swift
// Sources/MapboxNavigationCore/Navigator/MapboxNavigator.swift
func handleRouteProgressUpdates(status: NavigationStatus, routeProgress: RouteProgress?) async {
    guard let routeProgress else { return }
    
    // Check if there's a new spoken instruction
    if let newSpokenInstruction = routeProgress.currentLegProgress.currentStepProgress
        .currentSpokenInstruction
    {
        // Emit SpokenInstructionState to navigator's voiceInstructions publisher
        await send(SpokenInstructionState(spokenInstruction: newSpokenInstruction))
    }
}
```

**Code Location:**
- `MapboxNavigator.handleRouteProgressUpdates(status:routeProgress:)`
- `MapboxNavigator.send(SpokenInstructionState)` → `_voiceInstructions.emit()`

### Step 9: RouteProgress Publisher → RouteVoiceController

**RouteVoiceController** subscribes to route progress:

```swift
// Sources/MapboxNavigationCore/MapboxNavigationProvider.swift
let routeVoiceController = RouteVoiceController(
    routeProgressing: navigation().routeProgress,  // ← Subscribes here
    rerouteSoundTrigger: ...,
    speechSynthesizer: ...
)
```

**Code Location:**
- `MapboxNavigationProvider.routeVoiceController`
- `RouteVoiceController.init(routeProgressing:rerouteSoundTrigger:speechSynthesizer:)`

### Step 10: RouteVoiceController.handle() → speechSynthesizer.speak()

**RouteVoiceController** handles route progress updates:

```swift
// Sources/MapboxNavigationCore/VoiceGuidance/RouteVoiceController.swift
private func handle(routeProgressState: RouteProgressState?) {
    // ⚠️ CRITICAL: Only proceeds if currentSpokenInstruction exists
    guard let routeProgress = routeProgressState?.routeProgress,
          let spokenInstruction = routeProgressState?.routeProgress.currentLegProgress.currentStepProgress
              .currentSpokenInstruction
    else {
        return  // ← If currentSpokenInstruction is nil, nothing happens
    }
    
    // Prepare remaining instructions
    var remainingSpokenInstructions = ...
    speechSynthesizer.prepareIncomingSpokenInstructions(remainingSpokenInstructions, locale: locale)
    
    // Trigger speech synthesis
    speechSynthesizer.speak(
        spokenInstruction,
        during: routeProgress.currentLegProgress,
        locale: locale
    )
}
```

**Critical Point:**
- `handle()` only proceeds if `currentSpokenInstruction` is not nil
- If `currentSpokenInstruction` is nil, the method returns early and nothing happens

**Code Location:**
- `RouteVoiceController.handle(routeProgressState: RouteProgressState?)`
- Lines 121-127: Guard statement checking for `currentSpokenInstruction`

### Step 11: speechSynthesizer.speak() → Voice Events

**SpeechSynthesizer** (e.g., SystemSpeechSynthesizer) emits events:

```swift
// Sources/MapboxNavigationCore/VoiceGuidance/SystemSpeechSynthesizer/SystemSpeechSynthesizer.swift
public func speak(_ instruction: SpokenInstruction, during legProgress: RouteLegProgress, locale: Locale?) {
    guard !muted else { return }
    
    // Emit WillSpeak event
    _voiceInstructions.send(VoiceInstructionEvents.WillSpeak(instruction: instruction))
    
    // Create and speak utterance
    let utterance = AVSpeechUtterance(attributedString: instruction.attributedText(for: legProgress))
    synthesizer.speak(utterance)
    
    // Emit DidSpeak event when done
    _voiceInstructions.send(VoiceInstructionEvents.DidSpeak(instruction: instruction))
}
```

**Code Location:**
- `SystemSpeechSynthesizer.speak(_:during:locale:)`
- `MultiplexedSpeechSynthesizer.speak(_:during:locale:)` (forwards to first synthesizer)

### Step 12: voiceInstructions Publisher → Your Code

**Your code** subscribes to `speechSynthesizer.voiceInstructions`:

```swift
routeVoiceController.speechSynthesizer.voiceInstructions
    .sink { event in
        switch event {
        case let willSpeak as VoiceInstructionEvents.WillSpeak:
            // Handle willSpeak event
        case let didSpeak as VoiceInstructionEvents.DidSpeak:
            // Handle didSpeak event
        default:
            break
        }
    }
```

## Critical Dependencies

For voice instructions to work, ALL of these must be true:

1. ✅ **Session State**: Must be `.activeGuidance` (not `.idle` or `.freeDrive`)
2. ✅ **Billing Session**: Must be active
3. ✅ **Location Updates**: Must be flowing to native navigator
4. ✅ **Route Set**: Routes must be properly set in native navigator
5. ✅ **activeGuidanceInfo**: `NavigationStatus.activeGuidanceInfo` must not be nil
6. ✅ **primaryRouteIndices**: `NavigationStatus.primaryRouteIndices` must not be nil
7. ✅ **voiceInstruction**: `NavigationStatus.voiceInstruction` must be set by native engine
8. ✅ **currentSpokenInstruction**: Extracted from `status.voiceInstruction` in `RouteStepProgress.update()`
9. ✅ **RouteVoiceController**: Must subscribe to `navigation().routeProgress`
10. ✅ **Synthesizer Not Muted**: `speechSynthesizer.muted` must be `false`

## Why Voice Instructions Might Not Work

### Issue 1: `status.voiceInstruction` is nil

**Symptom:** `currentSpokenInstruction` is always nil

**Cause:** Native engine doesn't set `NavigationStatus.voiceInstruction`

**Possible Reasons:**
- Not close enough to instruction trigger point
- Route doesn't have instructions
- Native engine hasn't processed location yet
- Route format issue

### Issue 2: `activeGuidanceInfo` is nil

**Symptom:** `RouteStepProgress.update()` returns early

**Cause:** `NavigationStatus.activeGuidanceInfo` is nil

**Possible Reasons:**
- Session not in active guidance state
- Route not properly set in native navigator
- Location not matched to route

### Issue 3: Session State Wrong

**Symptom:** `MapboxNavigator.update()` returns early

**Cause:** Session state is `.idle` or not `.activeGuidance`

**Fix:** Ensure `sessionController.startActiveGuidance()` is called and completes

### Issue 4: RouteVoiceController Not Subscribed

**Symptom:** `handle()` never called

**Cause:** `RouteVoiceController` not properly initialized or subscription lost

**Fix:** Ensure `routeVoiceController` is accessed and subscription is retained

## Flow Diagram

```
Location Update
    ↓
Native Navigator (C++)
    ↓
NavigationStatus (with voiceInstruction)
    ↓
NotificationCenter (.navigationStatusDidChange)
    ↓
MapboxNavigator.navigationStatusDidChange()
    ↓
AsyncStream (statusUpdateEvents)
    ↓
MapboxNavigator.update(to:)
    ↓
RouteStepProgress.update(using:) → currentSpokenInstruction
    ↓
MapboxNavigator.handleRouteProgressUpdates() → SpokenInstructionState
    ↓
RouteProgress Publisher → RouteProgressState
    ↓
RouteVoiceController.handle() → speechSynthesizer.speak()
    ↓
SpeechSynthesizer.speak() → VoiceInstructionEvents
    ↓
voiceInstructions Publisher → Your Code
```

## Summary

The voice instruction flow depends on the **native navigation engine** setting `NavigationStatus.voiceInstruction`. If this is nil, the entire chain breaks at `RouteStepProgress.update()`, and `currentSpokenInstruction` remains nil, causing `RouteVoiceController.handle()` to return early without triggering speech synthesis.

The SDK cannot force voice instructions if the native engine doesn't provide them. The native engine determines when to trigger instructions based on:
- Your position along the route
- Distance to next maneuver
- Internal navigation logic

If the native engine isn't providing `voiceInstruction`, you need to:
1. Verify session is in `.activeGuidance` state
2. Verify location updates are flowing
3. Verify route has instructions
4. Wait for native engine to process and trigger instructions
5. Check if you're close enough to trigger points
