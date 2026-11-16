# liveness

On-device face liveness and face matching for Flutter apps. Used by
Solace's identity check, and available to any app in this workspace.

- **`FaceLiveness.show`** opens a full-screen camera flow. It asks for
  random gestures (blink, smile, turn left or right, open mouth, shake
  head) and returns a `LivenessResult` with the frames it captured.
- **`LivenessController`** + **`LivenessPreview`** are the same check
  without the screen, for an app that draws its own (see "Your own
  screen" below).
- **`FaceCompare`** turns faces into embeddings with a TFLite model and
  scores how alike two faces are: `compare`, `compareBest` (a reference
  photo against several live frames), `compareDetailed`, `isSamePerson`.

Faces are found with ML Kit. Everything runs on the phone; nothing is
uploaded.

## Using it

The package is a private GitHub repo, `Deecency/liveness`. Add it at a
tagged version:

```yaml
dependencies:
  liveness:
    git:
      url: https://github.com/Deecency/liveness.git
      ref: v1.5.0
```

Fetching it needs git access to the repo (the machine's GitHub sign-in).
An app moves to a newer version only when its `ref` changes.

To try unreleased changes from a local copy beside the app, add a
`pubspec_overrides.yaml` to the app, and keep it out of git:

```yaml
dependency_overrides:
  liveness:
    path: ../liveness
```

## Language

The screen's words are in English and French, and it follows the app's
locale on its own: with French selected it speaks French, with no setup.
Any other language falls back to English.

For other wording or another language, pass your own words, for example
built from the app's own translations. Extend `LivenessLocalizationsEn` to
change some words and keep the rest, or implement `LivenessLocalizations`
in full:

```dart
class AppLivenessWords extends LivenessLocalizationsEn {
  const AppLivenessWords(this.l10n);
  final AppLocalizations l10n;

  @override
  String get title => l10n.verifyYourFace;
}

FaceLiveness.show(
  context,
  config: LivenessConfig(localizations: AppLivenessWords(context.l10n)),
);
```

`LivenessConfig.title`, when set, still wins over the translated title. A
screen of your own (`LivenessController` + `LivenessPreview`) can use
`LivenessLocalizations.of(context)` for the same words, and
`LivenessState.errorKind` to show a camera error in the app's language;
`LivenessState.error` and `LivenessResult.message` stay in English, for
logs.

## App setup (required — builds succeed, but the app breaks without it)

Each step below is in the app's own project files, not in this package,
and none of the failures shows at build time: `flutter build` succeeds,
and some show only in release builds. Test on real devices, through the
face match.

**Flutter:** 3.47 or later, from 1.5.0, which builds on the standalone
`material_ui` and `cupertino_ui` packages. Apps on either those or the
deprecated `package:flutter/material.dart` work. In an app still on the
latter, the screen cannot see the app's Material theme, so set
`LivenessTheme.fontFamily` to keep the app's font, or move the app over
with `dart fix --apply --code=migrate_design_widgets`.

**Both platforms:** camera permission — `NSCameraUsageDescription` in
`ios/Runner/Info.plist`, `android.permission.CAMERA` in
`android/app/src/main/AndroidManifest.xml`.

**iOS**

- Swift Package Manager must be on. Since 1.4.0, ML Kit
  (`google_mlkit_face_detection` 1.0) ships only a Swift package, with no
  podspec, so it cannot build through CocoaPods. In the app's
  `pubspec.yaml`:

  ```yaml
  flutter:
    config:
      enable-swift-package-manager: true
  ```

  Plugins that still lack SPM support keep building with CocoaPods
  alongside it.
- Minimum iOS 15.0 (ML Kit): `IPHONEOS_DEPLOYMENT_TARGET` in the Runner
  project, and `platform :ios` in `ios/Podfile` if there is one.
- **ML Kit's Swift package needs two Runner changes**, or face detection
  crashes on a device (debug builds too) with
  `-[MLKITx_CCTLogContext hashForFilePath]: unrecognized selector`, or
  cannot load its model. ML Kit ships static libraries; under CocoaPods
  its pods made CocoaPods add `-ObjC`, so apps on 1.3.0 or earlier never
  set it themselves.

  1. **Other Linker Flags** on the Runner target, every configuration:
     `$(inherited) -ObjC -all_load`. ML Kit adds methods in Objective-C
     categories and registers its models in static initialisers, and
     without these flags the linker drops both. Both flags are what ML
     Kit's own plugin README asks for.
  2. **A Run Script build phase** on Runner, placed after "Copy Bundle
     Resources" and named e.g. "Copy ML Kit model bundles". ML Kit looks
     for `GoogleMVFaceDetectorResources.bundle` in the main bundle, but
     Swift Package Manager leaves it inside
     `MLKitFaceDetection.framework`:

     ```sh
     set -eu
     src="${BUILT_PRODUCTS_DIR}/MLKitFaceDetection.framework/GoogleMVFaceDetectorResources.bundle"
     dst="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/GoogleMVFaceDetectorResources.bundle"
     if [ ! -d "$src" ]; then
       echo "error: $src not found; did ML Kit's package layout change?" >&2
       exit 1
     fi
     rm -rf "$dst"
     cp -R "$src" "$dst"
     ```

     Set the phase's Input Files to the `src` path and Output Files to the
     `dst` path, so Xcode reruns it only when the model changes. It copies
     from the framework, so it follows whichever ML Kit version is in use,
     and fails the build if the bundle is missing. The framework keeps its
     signed copy too, so the app carries the 9.6 MB model twice; together
     with `-all_load` the IPA grows by about 12 MB.

  Pass's `ios/Runner.xcodeproj` has both, as a working example.
- **No strip settings.** Earlier versions of this README said to turn
  release stripping off (`DEAD_CODE_STRIPPING`, `STRIP_STYLE`,
  `STRIP_INSTALLED_PRODUCT`) so TensorFlow Lite's `TfLiteModelCreate`
  survived. `flutter_litert` exports the `TfLite*` symbols from its own
  framework, and a release build without those settings matched faces
  normally (model loaded in 35 ms). Delete them from `ios/Podfile`'s
  `post_install` and from the Runner project if an app has them. If a
  face match ever fails with "Failed to lookup symbol
  'TfLiteModelCreate'", check that the archive's `flutter-litert`
  framework (hyphenated) exports it:
  `nm -gU build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app/Frameworks/flutter-litert.framework/flutter-litert | grep TfLiteModelCreate`
  should print a `T _TfLiteModelCreate` line.
- Upgrading from 1.3.0 or earlier: delete any
  `EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64` those versions needed in
  `ios/Podfile` and the Runner project. ML Kit's Swift package has an
  arm64 simulator slice, and the iOS 26+ simulators on Apple Silicon
  require arm64.
- Upgrading from 1.2.0 or earlier: delete the `TensorFlowLiteSwift` shim
  those versions needed — `ios/podspecs/TensorFlowLiteSwift/` and the
  `pod 'TensorFlowLiteSwift', :path => ...` line in `ios/Podfile` — then
  run `pod install`. `flutter_litert` downloads its own prebuilt
  TensorFlow Lite frameworks (about 85 MB, once, cached afterwards) and
  depends on no TensorFlow pod, so a leftover shim would link a second
  copy of `TensorFlowLiteC`. Run the face match on a device afterwards,
  not just the camera.

**Android** (`android/app/build.gradle.kts`, inside `android { }`)

```kotlin
packaging {
    jniLibs {
        pickFirsts.add("**/libc++_shared.so") // camera and tflite both ship it
        useLegacyPackaging = true
    }
}
androidResources {
    noCompress += listOf("tflite", "emd", "tfl", "pb") // models stay uncompressed
}
buildTypes {
    release {
        // R8 may stay on, with keep rules for ML Kit and TensorFlow Lite
        // in proguard-rules.pro (Solace's android/app/proguard-rules.pro
        // is a working set); Google Play's release check wants the DEX
        // obfuscated. Without those rules, turn it off:
        // isMinifyEnabled = false
        isShrinkResources = false
    }
}
```

And in the main `<activity>` of `AndroidManifest.xml` (Impeller has
camera-preview texture problems on some devices):

```xml
<meta-data
    android:name="io.flutter.embedding.android.EnableImpeller"
    android:value="false" />
```

Test a release build on a real Android phone and an archived build on a
real iPhone, through the face match, not just the camera opening.

```dart
import 'package:liveness/liveness.dart';

final result = await FaceLiveness.show(
  context,
  config: const LivenessConfig(randomGestureCount: 2, timeoutSeconds: 60),
);
if (result?.status == LivenessResultStatus.success) {
  final faceCompare = await FaceCompare.create();
  // Score result's frames against a reference photo.
}
```

## Your own screen

`FaceLiveness.show` draws the package's own screen. To draw your own,
drive a `LivenessController` and rebuild from its state:

```dart
final controller = LivenessController(
  config: const LivenessConfig(
    requiredGestures: [LivenessGesture.turnLeft, LivenessGesture.smile],
    rejectMultipleFaces: true,
  ),
);
controller.initialize(); // opens the camera; failures show in state.error
controller.start();      // countdown, a 2 s "get ready", then the gestures

// In build():
Stack(children: [
  LivenessPreview(controller: controller), // camera only, cover-cropped
  ValueListenableBuilder<LivenessState>(
    valueListenable: controller,
    builder: (context, state, _) => YourOverlay(state),
  ),
]);

final result = await controller.result; // same LivenessResult as show()
controller.dispose();
```

`LivenessState` has `phase` (`preparing`, `gesture`, `finalCapture`,
`completing`, `finished`), `cameraReady`, `gestures` (the order chosen for
this session), `currentIndex`, `currentGesture`, `gestureProgress` (0–1
into the current gesture, e.g. how far the head has turned), `completed`,
`hint` (during `preparing` and `finalCapture`: what to fix — no face, move
closer, centre, light — or null when the frame is good), `faceCount`,
`timeRemaining`/`timeoutSeconds`, `error` and `result`. Faces are tracked
from the moment the camera is ready, so the "get ready" pause can already
say "face found" or "move closer"; no gesture counts until it ends. Map
the enums to your own wording; the package's English is only used by its
own screen. `cancel()` ends the session; disposing an unfinished one
completes `result` as cancelled.

If your face guide isn't vertically centred, tell the framing check where
it is: `LivenessThresholds(faceCenterTargetY: 0.43)` for a guide whose
centre is 43% down a full-screen preview (the default is 0.5).

With `rejectMultipleFaces: true`, a frame with more than one face counts
for nothing and the hint becomes `LivenessCaptureHint.multipleFaces`. It's
off by default, which keeps the original behaviour.

## Models

`FaceModel.mobileFaceNet` (about 5 MB, the default) and
`FaceModel.faceNet` (about 24 MB) are bundled. `FaceModel.faceNet512` is
listed, but its model file isn't bundled: choosing it fails until
`assets/models/facenet_512.tflite` is added back.

## Changing it

This package is shared. To release a change: commit it, tag a new
version (`git tag -a v1.1.0 -m "..." && git push origin v1.1.0`), then
bump `ref` in each app that should get it. Keep the API backward
compatible, so apps can move up one at a time.

## Origin and licence

Started from Widiyanto Ramadhan's
[face_match_liveness](https://github.com/widiramadhan/face_match_liveness)
(MIT, see [LICENSE](LICENSE)), then substantially reworked for Solace's
identity check: capture, gestures, thresholds and matching.
