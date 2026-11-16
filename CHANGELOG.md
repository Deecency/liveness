# Changelog

## 1.6.0

- **`camera` 0.11 and 0.12 are allowed** (`>=0.10.6 <0.13.0`), so apps on
  the current camera plugin can use the package. From 0.11, Android uses
  `camera_android_camerax`, which turns streamed frames into the single
  NV21 plane ML Kit needs when NV21 is requested, as `camera_android` did;
  the frame conversion is unchanged. Apps on 0.10 keep working.

## 1.5.0

- **Needs Flutter 3.47 or later (Dart 3.13).** The package now imports
  Flutter's standalone `material_ui` and `cupertino_ui` packages instead of
  `package:flutter/material.dart` and `cupertino.dart`, which Flutter 3.47
  deprecated. The API is unchanged.
- Works in apps on either library. An app still on
  `package:flutter/material.dart` provides Material localizations that
  `material_ui`'s widgets cannot see, so the liveness screen now supplies
  its own when it finds none (Flutter's translations for the app's locale,
  else English); without that its app bar failed with "No
  MaterialLocalizations found".
- In such an app the screen also no longer sees the app's Material theme:
  text without a `LivenessTheme.fontFamily` uses Flutter's default font,
  not the app's. Set `fontFamily`, or move the app to `material_ui`
  (`dart fix --apply --code=migrate_design_widgets`).

## 1.4.0

- ML Kit moves to `google_mlkit_face_detection` 1.0.3 (from 0.15.1). The
  Dart API is unchanged.
- **iOS apps must enable Swift Package Manager.** ML Kit 1.0 ships its iOS
  plugin only as a Swift package, so it no longer builds through
  CocoaPods. See "App setup" in the README.
- The iOS simulator no longer needs `arm64` excluded: ML Kit's Swift
  package carries an arm64 simulator slice, which the iOS 26+ simulators
  on Apple Silicon require. Apps should delete that workaround.
- Minimum iOS is now 15.0 (was 15.5).

## 1.3.0

- TensorFlow Lite now comes from `flutter_litert` instead of
  `tflite_flutter`. It is a maintained fork with the same `Interpreter`
  API, so `FaceCompare` behaves as before; the models are unchanged.
  `tflite_flutter` has no Swift Package Manager support and has not been
  updated since 0.12.1.
- iOS apps should delete the `TensorFlowLiteSwift` shim (the local podspec
  and its `pod` line in `ios/Podfile`): `flutter_litert` downloads its own
  prebuilt TensorFlow Lite frameworks and depends on no TensorFlow pod.
  Keeping the shim would link a second copy of `TensorFlowLiteC`.
- Fixed: on iOS, turn left and turn right were swapped — passing the
  turn-left step took a turn to the right. The iOS camera plugin mirrors
  the front-camera stream and Android's does not, so ML Kit reported the
  head's yaw with opposite signs; the turn steps now read it the same way
  on both. Android is unchanged.
- No API change. Run the face match on a device after upgrading.

## 1.2.0

- `LivenessState.gestureProgress`: 0–1 into the current gesture (turn angle
  reached, smile or open-mouth frames held, blinks done, sides of a shake
  or nod reached), for a progress arc that fills as the person moves.
- Faces are detected from the moment the camera is ready: during the
  `preparing` pause `faceCount` is live and `hint` reports framing (no
  face, move closer, centre, light, multiple faces). No gesture counts
  until the pause ends; the hint resets to null when it does.
  `FaceLiveness`'s own screen doesn't show it, so it looks the same.
- `LivenessThresholds.faceCenterTargetY` (default 0.5): where the face's
  centre should sit, top to bottom, for a guide that isn't centred.

## 1.1.0

- `LivenessController`: the liveness check without its screen — camera,
  face detection, gestures, final capture and countdown — publishing an
  immutable `LivenessState` and completing `result` with the same
  `LivenessResult` as before.
- `LivenessPreview`: the controller's camera picture, nothing drawn on it.
- `FaceLiveness` is now built on the controller. Same API and the same
  look; an app using `FaceLiveness.show` needs no change.
- New gesture `LivenessGesture.nod`, with `LivenessThresholds.nodAngle`
  (default 10°) and `nodReversals` (default 1).
- New `LivenessConfig.rejectMultipleFaces` (default false) and
  `LivenessCaptureHint.multipleFaces`. `LivenessState.faceCount` is
  reported either way.
- An app with an exhaustive `switch` over `LivenessGesture` or
  `LivenessCaptureHint` needs a case for the new value.

## 1.0.0

- The package as moved out of Solace.
