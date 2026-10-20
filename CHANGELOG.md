# Changelog

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
