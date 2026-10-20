part of 'liveness_controller.dart';

/// The gesture phase: choosing the challenge, the per-gesture recognisers,
/// and advancing from one step to the next (and finally into capture).
extension _GestureRecognition on LivenessController {
  /// Resolves the gesture sequence for this session. With
  /// [LivenessConfig.randomGestureCount] set, shuffles a de-duplicated copy of
  /// the pool and takes that many; otherwise returns the configured list
  /// as-is.
  List<LivenessGesture> _resolveGestures() {
    final pool = config.requiredGestures;
    final count = config.randomGestureCount;
    if (count == null || pool.isEmpty) return pool;

    final unique = pool.toSet().toList()..shuffle(math.Random());
    return unique.take(count.clamp(1, unique.length)).toList(growable: false);
  }

  /// Gesture-phase frame handler. The final capture hold is handled
  /// separately in [_FinalCapture._evaluateFinalCapture], called straight
  /// from [_CameraInput._onCameraImage].
  void _processFaceData(Face face) {
    final currentGesture = _currentStep;
    if (currentGesture == null) return;

    switch (currentGesture) {
      case LivenessGesture.blink:
        _detectBlink(face);
        break;
      case LivenessGesture.mouthOpen:
        _detectMouthOpen(face);
        break;
      case LivenessGesture.headShake:
        _detectHeadShake(face);
        break;
      case LivenessGesture.smile:
        _detectSmile(face);
        break;
      case LivenessGesture.turnLeft:
        _detectTurnLeft(face);
        break;
      case LivenessGesture.turnRight:
        _detectTurnRight(face);
        break;
      case LivenessGesture.nod:
        _detectNod(face);
        break;
    }
  }

  void _detectBlink(Face face) {
    final leftEyeOpen = face.leftEyeOpenProbability;
    final rightEyeOpen = face.rightEyeOpenProbability;

    if (leftEyeOpen != null && rightEyeOpen != null) {
      final openThreshold = _thr.blinkOpen.value;
      final closedThreshold = _thr.blinkClosed.value;

      // Both eyes must clear "open"; the binding one is the less-open eye.
      _trackApproach(_thr.blinkOpen, math.min(leftEyeOpen, rightEyeOpen));
      // Both eyes must reach "closed"; the binding one is the more-open eye.
      _trackApproach(_thr.blinkClosed, math.max(leftEyeOpen, rightEyeOpen));

      // Detect eye closure (blink)
      if (_previousLeftEyeOpenProbability != null &&
          _previousRightEyeOpenProbability != null) {
        // Eyes were open, now closed
        if (_previousLeftEyeOpenProbability! > openThreshold &&
            _previousRightEyeOpenProbability! > openThreshold &&
            leftEyeOpen < closedThreshold &&
            rightEyeOpen < closedThreshold) {
          _blinkCount++;
        }

        _setProgress(LivenessGesture.blink, _blinkCount / _thr.blinkCount);

        // If we detected enough blinks
        if (_blinkCount >= _thr.blinkCount && !_blinkDetected) {
          _blinkDetected = true;
          _onGestureDetected(LivenessGesture.blink);
        }
      }

      _previousLeftEyeOpenProbability = leftEyeOpen;
      _previousRightEyeOpenProbability = rightEyeOpen;
    }
  }

  void _detectMouthOpen(Face face) {
    final upperLip = face.contours[FaceContourType.upperLipBottom]?.points;
    final lowerLip = face.contours[FaceContourType.lowerLipTop]?.points;
    final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;

    if (upperLip == null ||
        upperLip.isEmpty ||
        lowerLip == null ||
        lowerLip.isEmpty ||
        leftEye == null ||
        rightEye == null) {
      debugPrint(
        "🔍 mouthOpen bail: upperLip=${upperLip?.length}, "
        "lowerLip=${lowerLip?.length}, leftEye=$leftEye, rightEye=$rightEye",
      );
      return;
    }

    final upperY =
        upperLip.map((p) => p.y).reduce((a, b) => a + b) / upperLip.length;
    final lowerY =
        lowerLip.map((p) => p.y).reduce((a, b) => a + b) / lowerLip.length;
    final mouthGap = (lowerY - upperY).abs();

    final dx = (rightEye.x - leftEye.x).toDouble();
    final dy = (rightEye.y - leftEye.y).toDouble();
    final eyeDistance = math.sqrt(dx * dx + dy * dy);
    if (eyeDistance == 0) {
      debugPrint("🔍 mouthOpen bail: eyeDistance is 0");
      return;
    }

    final ratio = mouthGap / eyeDistance;
    _trackApproach(_thr.mouthRatio, ratio);
    final threshold = _thr.mouthRatio.value;
    debugPrint(
      "🔍 mouthGap=$mouthGap eyeDist=$eyeDistance ratio=${ratio.toStringAsFixed(3)} "
      "(threshold=${threshold.toStringAsFixed(3)}) frames=$_mouthOpenFrames",
    );

    if (ratio > threshold) {
      _mouthOpenFrames++;
      _setProgress(
        LivenessGesture.mouthOpen,
        _mouthOpenFrames / _thr.mouthOpenFrames,
      );
      if (_mouthOpenFrames >= _thr.mouthOpenFrames && !_mouthOpenDetected) {
        _mouthOpenDetected = true;
        _onGestureDetected(LivenessGesture.mouthOpen);
      }
    } else {
      // Decay instead of hard-reset so a single jittery frame (ML Kit lip
      // contours flicker) doesn't wipe out a genuinely-held open mouth.
      _mouthOpenFrames = (_mouthOpenFrames - 1).clamp(0, 999);
      _setProgress(
        LivenessGesture.mouthOpen,
        _mouthOpenFrames / _thr.mouthOpenFrames,
      );
    }
  }

  void _detectHeadShake(Face face) {
    final headEulerAngleY = face.headEulerAngleY;

    if (headEulerAngleY == null) return;

    _trackApproach(_thr.headShakeAngle, headEulerAngleY.abs());
    final turnThreshold = _thr.headShakeAngle.value;
    var direction = 0; // -1 turned left, 0 neutral, 1 turned right
    if (headEulerAngleY > turnThreshold) {
      direction = 1;
    } else if (headEulerAngleY < -turnThreshold) {
      direction = -1;
    }

    // Require the head to swing from clearly-turned-one-way to
    // clearly-turned-the-other-way (headShakeReversals direction changes,
    // default 1 ⇒ one left-then-right or right-then-left). Movement in two
    // directions is what a held-still photo can't fake; the face match is
    // the real backstop.
    if (direction != 0 && direction != _headShakeDirection) {
      if (_headShakeDirection != 0) {
        _headShakeReversals++;
      }
      _headShakeDirection = direction;
    }

    _setProgress(
      LivenessGesture.headShake,
      _swingProgress(
        angle: headEulerAngleY,
        threshold: turnThreshold,
        direction: _headShakeDirection,
        reversals: _headShakeReversals,
        required: _thr.headShakeReversals,
      ),
    );

    if (_headShakeReversals >= _thr.headShakeReversals && !_headShakeDetected) {
      _headShakeDetected = true;
      _onGestureDetected(LivenessGesture.headShake);
    }
  }

  /// A nod: the head pitched clearly one way, then clearly the other
  /// (`nodReversals` direction changes, default 1 ⇒ down-then-up or
  /// up-then-down). Like the head shake, movement in two directions is what
  /// a held-still photo can't fake.
  void _detectNod(Face face) {
    final pitch = face.headEulerAngleX;
    if (pitch == null) return;

    _trackApproach(_thr.nodAngle, pitch.abs());
    final threshold = _thr.nodAngle.value;
    var direction = 0; // -1 down, 0 level, 1 up
    if (pitch > threshold) {
      direction = 1;
    } else if (pitch < -threshold) {
      direction = -1;
    }

    if (direction != 0 && direction != _nodDirection) {
      if (_nodDirection != 0) {
        _nodReversals++;
      }
      _nodDirection = direction;
    }

    _setProgress(
      LivenessGesture.nod,
      _swingProgress(
        angle: pitch,
        threshold: threshold,
        direction: _nodDirection,
        reversals: _nodReversals,
        required: _thr.nodReversals,
      ),
    );

    if (_nodReversals >= _thr.nodReversals && !_nodDetected) {
      _nodDetected = true;
      _onGestureDetected(LivenessGesture.nod);
    }
  }

  void _detectSmile(Face face) {
    final smilingProbability = face.smilingProbability;
    if (smilingProbability == null) return;

    _trackApproach(_thr.smileProb, smilingProbability);

    if (smilingProbability > _thr.smileProb.value) {
      _smileFrames++;
      _setProgress(LivenessGesture.smile, _smileFrames / _thr.smileFrames);

      if (_smileFrames >= _thr.smileFrames && !_smileDetected) {
        _smileDetected = true;
        _onGestureDetected(LivenessGesture.smile);
      }
    } else {
      // Decay rather than hard-reset — tolerate a brief classifier dip.
      _smileFrames = (_smileFrames - 1).clamp(0, 999);
      _setProgress(LivenessGesture.smile, _smileFrames / _thr.smileFrames);
    }
  }

  void _detectTurnLeft(Face face) {
    final headEulerAngleY = face.headEulerAngleY;
    if (headEulerAngleY == null) return;

    // Turn-left registers as a positive yaw in this coordinate convention.
    _trackApproach(_thr.turnAngle, headEulerAngleY);
    _setProgress(
      LivenessGesture.turnLeft,
      headEulerAngleY / _thr.turnAngle.value,
    );

    if (headEulerAngleY > _thr.turnAngle.value && !_turnLeftDetected) {
      _turnLeftDetected = true;
      _onGestureDetected(LivenessGesture.turnLeft);
    }
  }

  void _detectTurnRight(Face face) {
    final headEulerAngleY = face.headEulerAngleY;
    if (headEulerAngleY == null) return;

    // Turn-right is a negative yaw; feed its magnitude so the shared
    // turnAngle threshold sees an "above the line" value either way.
    _trackApproach(_thr.turnAngle, -headEulerAngleY);
    _setProgress(
      LivenessGesture.turnRight,
      -headEulerAngleY / _thr.turnAngle.value,
    );

    if (-headEulerAngleY > _thr.turnAngle.value && !_turnRightDetected) {
      _turnRightDetected = true;
      _onGestureDetected(LivenessGesture.turnRight);
    }
  }

  void _onGestureDetected(LivenessGesture gesture) {
    if (_completedGestures.contains(gesture)) return;

    _recordThresholdOutcome(gesture);

    _update(() {
      _completedGestures.add(gesture);
      _gestureProgress = 0;
      if (_currentGestureIndex < _gestures.length - 1) {
        _currentGestureIndex++;
        _currentStep = _gestures[_currentGestureIndex];
        _resetGestureDetectionState();
        _beginStepTracking();

        // Reset timer when gesture is completed successfully
        _resetTimer();
      } else {
        // All configured gestures are done. Completion happens once
        // _evaluateFinalCapture sees a run of steady, well-framed,
        // well-lit, forward-facing frames — not immediately here. Give the
        // user a full fresh window to satisfy those checks.
        _currentStep = null;
        _isInFinalCapture = true;
        _facingCameraFrames = 0;
        _captureHint = null;
        _resetTimer();
      }
    });
  }

  /// Publishes [progress] (clamped to 0–1) for [gesture], if it's the one
  /// being asked for. Small changes are held back so a screen isn't rebuilt
  /// for every frame's jitter.
  void _setProgress(LivenessGesture gesture, double progress) {
    if (_currentStep != gesture || !progress.isFinite) return;
    final p = progress.clamp(0.0, 1.0);
    if ((p - _gestureProgress).abs() < 0.02 && p != 0 && p != 1) return;
    if (p == _gestureProgress) return;
    _update(() => _gestureProgress = p);
  }

  /// Progress through a side-to-side (or up-and-down) swing that needs
  /// [required] direction changes, i.e. [required] + 1 sides reached: the
  /// sides reached so far, plus how far [angle] has got toward the next
  /// one.
  double _swingProgress({
    required double angle,
    required double threshold,
    required int direction,
    required int reversals,
    required int required,
  }) {
    if (threshold <= 0) return 0;
    final reached = (direction != 0 ? 1 : 0) + reversals;
    final towardNext = direction == 0
        ? angle.abs() / threshold
        : math.max(0.0, -direction * angle) / threshold;
    return (reached + towardNext.clamp(0.0, 1.0)) / (required + 1);
  }

  void _resetGestureDetectionState() {
    _blinkCount = 0;
    _mouthOpenFrames = 0;
    _headShakeDirection = 0;
    _headShakeReversals = 0;
    _nodDirection = 0;
    _nodReversals = 0;
    _smileFrames = 0;
    _blinkDetected = false;
    _mouthOpenDetected = false;
    _headShakeDetected = false;
    _smileDetected = false;
    _turnLeftDetected = false;
    _turnRightDetected = false;
    _nodDetected = false;
  }
}
