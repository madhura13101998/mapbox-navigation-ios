# Voice Instruction Handling Fix

## Issues Found:

1. **Subscription not stored** - The Combine subscription will be deallocated immediately
2. **Missing weak self capture** - Potential retain cycle
3. **Only WillSpeak sent** - Other events (DidSpeak, errors) not sent to Flutter
4. **VoiceInstructionHandler not shown** - Need to verify it's properly set up

## Fixed Code:

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
    private var routeVoiceController: RouteVoiceController
    
    // MARK: - Navigation State
    private var currentRoutes: NavigationRoutes?
    private var locationSubscription: AnyCancellable?
    private var voiceInstructionSubscription: AnyCancellable? // ADD THIS
    private var isNavigating: Bool = false
    
    // MARK: - Initialization
    public override init() {
        mapboxNavigationProvider = MapboxNavigationProvider(coreConfig: .init())
        mapboxNavigation = mapboxNavigationProvider.mapboxNavigation
        routingProvider = mapboxNavigation.routingProvider()
        sessionController = mapboxNavigation.tripSession()
        navigationController = mapboxNavigation.navigation()
        routeVoiceController = mapboxNavigationProvider.routeVoiceController
        
        super.init()
    }
    
    // ... rest of your code ...
    
    // MARK: - Voice Instruction Subscription (FIXED)
    private func subscribeToVoiceInstruction() {
        // Cancel any existing subscription
        voiceInstructionSubscription?.cancel()
        
        // Subscribe and STORE the subscription
        voiceInstructionSubscription = routeVoiceController.speechSynthesizer.voiceInstructions
            .sink { [weak self] event in
                guard let self = self else { return }
                
                switch event {
                case let willSpeak as VoiceInstructionEvents.WillSpeak:
                    print("Will speak: \(willSpeak.instruction.text)")
                    
                    let voiceInstructionData: [String: Any] = [
                        "type": "willSpeak",
                        "instruction": willSpeak.instruction.text,
                        "ssmlText": willSpeak.instruction.ssmlText ?? "",
                        "distance": willSpeak.instruction.distanceAlongStep
                    ]
                    
                    // Send to Flutter via event channel
                    self.voiceInstructionHandler?.eventSink?(voiceInstructionData)
                    
                case let didSpeak as VoiceInstructionEvents.DidSpeak:
                    print("Did speak: \(didSpeak.instruction.text)")
                    
                    let voiceInstructionData: [String: Any] = [
                        "type": "didSpeak",
                        "instruction": didSpeak.instruction.text,
                        "ssmlText": didSpeak.instruction.ssmlText ?? "",
                        "distance": didSpeak.instruction.distanceAlongStep
                    ]
                    
                    self.voiceInstructionHandler?.eventSink?(voiceInstructionData)
                    
                case let didInterrupt as VoiceInstructionEvents.DidInterrupt:
                    print("Interrupted: \(didInterrupt.interruptedInstruction.text)")
                    
                    let voiceInstructionData: [String: Any] = [
                        "type": "didInterrupt",
                        "interruptedInstruction": didInterrupt.interruptedInstruction.text,
                        "interruptingInstruction": didInterrupt.interruptingInstruction.text
                    ]
                    
                    self.voiceInstructionHandler?.eventSink?(voiceInstructionData)
                    
                case let error as VoiceInstructionEvents.EncounteredError:
                    print("Voice instruction error: \(error.error)")
                    
                    let voiceInstructionData: [String: Any] = [
                        "type": "error",
                        "error": error.error.localizedDescription
                    ]
                    
                    self.voiceInstructionHandler?.eventSink?(voiceInstructionData)
                    
                default:
                    break
                }
            }
    }
    
    // MARK: - Stop Navigation (UPDATED)
    private func handleStopNavigation(call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Cancel all subscriptions
        locationSubscription?.cancel()
        locationSubscription = nil
        
        voiceInstructionSubscription?.cancel()
        voiceInstructionSubscription = nil
        
        // Stop navigation session
        sessionController.stop()
        
        result(["success": true, "message": "Navigation stopped"])
    }
}
```

## Key Changes:

1. **Added `voiceInstructionSubscription` property** - Stores the Combine subscription
2. **Added `[weak self]` capture** - Prevents retain cycles
3. **Store the subscription** - Use `.sink { ... }` and assign to `voiceInstructionSubscription`
4. **Send all event types** - WillSpeak, DidSpeak, DidInterrupt, and errors
5. **Cancel on stop** - Properly clean up subscription when stopping navigation
6. **Added type field** - So Flutter can distinguish event types

## VoiceInstructionHandler Class (if you need it):

```swift
@MainActor
class VoiceInstructionHandler: NSObject, FlutterStreamHandler {
    var eventSink: FlutterEventSink?
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
```

## Flutter Side (Dart):

```dart
StreamSubscription? _voiceSubscription;

void _listenToVoiceInstructions() {
  _voiceSubscription = EventChannel('mapbox_navigation/voiceInstruction')
    .receiveBroadcastStream()
    .listen((dynamic event) {
      final data = event as Map<dynamic, dynamic>;
      final type = data['type'] as String;
      
      switch (type) {
        case 'willSpeak':
          print('Will speak: ${data['instruction']}');
          // Handle will speak
          break;
        case 'didSpeak':
          print('Did speak: ${data['instruction']}');
          // Handle did speak
          break;
        case 'didInterrupt':
          print('Interrupted');
          // Handle interruption
          break;
        case 'error':
          print('Error: ${data['error']}');
          // Handle error
          break;
      }
    });
}

void _stopListening() {
  _voiceSubscription?.cancel();
  _voiceSubscription = null;
}
```
