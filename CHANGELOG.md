# Changelog

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
