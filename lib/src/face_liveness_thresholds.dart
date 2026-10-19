part of 'face_liveness.dart';

// --- Adaptive thresholds ---------------------------------------------------

/// Wait this long into a step before auto-adjust is allowed to nudge — the
/// user gets a fair shot at the default first.
const Duration _kAdaptGracePeriod = Duration(milliseconds: 2500);

/// Minimum spacing between two nudges, so the threshold walks toward the user
/// rather than jumping.
const Duration _kAdaptInterval = Duration(milliseconds: 900);

/// Each nudge moves the threshold this fraction of its default magnitude
/// (capped at the remaining gap so it never overshoots the user).
const double _kAdaptStepFraction = 0.12;

/// Once a step has been active this long without completing, stop requiring
/// the attempt to be within `triggerFraction` of the threshold before
/// nudging — a persistent user who's only got part-way there still needs to
/// get through. They must have reached at least [_kAdaptHardRelaxMinProgress]
/// of the threshold for this to apply (filters out "not attempting").
const Duration _kAdaptHardRelaxAfter = Duration(seconds: 14);
const double _kAdaptHardRelaxMinProgress = 0.1;

/// One numeric detector threshold: a config-or-default value that, when
/// [autoAdjust] is on, can be walked a bounded distance toward a user who is
/// consistently landing just short of it.
class _AdaptiveThreshold {
  _AdaptiveThreshold({
    required this.name,
    required this.defaultValue,
    required this.passWhenBelow,
    required this.autoAdjust,
    required double tolerance,
    required this.triggerFraction,
    double? override,
  }) : _value = override ?? defaultValue,
       _boundA = defaultValue * (1 - tolerance.clamp(0.0, 0.95)),
       _boundB = defaultValue * (1 + tolerance.clamp(0.0, 4.0));

  /// Debug label.
  final String name;

  /// The package default (or config override treated as the new "default").
  final double defaultValue;

  /// True when the detector passes while the measured signal is *below* this
  /// threshold (only blink's eyes-closed cutoff); false when it passes while
  /// the signal is *above* it (everything else).
  final bool passWhenBelow;

  final bool autoAdjust;

  /// How near the threshold (as a fraction of its magnitude) the user's best
  /// attempt must be to count as "almost passing".
  final double triggerFraction;

  final double _boundA;
  final double _boundB;
  double _value;
  int _relaxations = 0;

  double get value => _value;

  int get relaxations => _relaxations;

  double get _lo => math.min(_boundA, _boundB);

  double get _hi => math.max(_boundA, _boundB);

  /// How far [best] (the user's closest attempt this step) is from passing,
  /// in threshold units. > 0 means still short by that much.
  double shortfall(double best) =>
      passWhenBelow ? best - _value : _value - best;

  /// Walk one step toward [best] in the easier direction, bounded by the
  /// tolerance window around [defaultValue]. Returns true if it actually
  /// moved.
  bool relaxToward(double best) {
    if (!autoAdjust) return false;
    final gap = shortfall(best).abs();
    final maxStep = defaultValue.abs() * _kAdaptStepFraction;
    final step = gap == 0 ? maxStep : math.min(maxStep, gap);
    // passWhenBelow ⇒ raising the cutoff is easier; otherwise lowering it is.
    final next = passWhenBelow ? _value + step : _value - step;
    final clamped = next.clamp(_lo, _hi);
    if ((clamped - _value).abs() < 1e-6) return false;
    _value = clamped;
    _relaxations++;
    return true;
  }
}

/// All per-step thresholds resolved from [LivenessThresholds]: config value if
/// set, package default otherwise. The gesture thresholds are [_AdaptiveThreshold]s;
/// frame counts and capture-quality gates are plain values (configurable, never
/// auto-adjusted).
class _ResolvedThresholds {
  _ResolvedThresholds(LivenessThresholds c)
    : blinkCount = c.blinkCount ?? 2,
      mouthOpenFrames = c.mouthOpenFrameCount ?? (Platform.isIOS ? 6 : 4),
      smileFrames = c.smileFrameCount ?? 16,
      headShakeReversals = c.headShakeReversals ?? (Platform.isIOS ? 2 : 1),
      captureYaw = c.captureYawDegrees ?? 5.0,
      capturePitch = c.capturePitchDegrees ?? 8.0,
      captureRoll = c.captureRollDegrees ?? 8.0,
      minFaceWidthRatio = c.minFaceWidthRatio ?? 0.26,
      maxFaceWidthRatio = c.maxFaceWidthRatio ?? 0.72,
      maxFaceCenterOffset = c.maxFaceCenterOffset ?? 0.18,
      minBrightness = c.minFrameBrightness ?? 55,
      maxBrightness = c.maxFrameBrightness ?? 225,
      holdFrames = c.captureHoldFrames ?? 20,
      blinkOpen = _AdaptiveThreshold(
        name: 'blinkEyeOpen',
        defaultValue: c.blinkEyeOpenProbability ?? 0.7,
        passWhenBelow: false,
        autoAdjust: c.autoAdjust,
        tolerance: c.autoAdjustTolerance,
        triggerFraction: c.autoAdjustTriggerFraction,
      ),
      blinkClosed = _AdaptiveThreshold(
        name: 'blinkEyeClosed',
        defaultValue: c.blinkEyeClosedProbability ?? 0.3,
        passWhenBelow: true,
        autoAdjust: c.autoAdjust,
        tolerance: c.autoAdjustTolerance,
        triggerFraction: c.autoAdjustTriggerFraction,
      ),
      mouthRatio = _AdaptiveThreshold(
        name: 'mouthOpenRatio',
        defaultValue: c.mouthOpenRatio ?? (Platform.isIOS ? 0.2 : 0.18),
        passWhenBelow: false,
        autoAdjust: c.autoAdjust,
        tolerance: c.autoAdjustTolerance,
        triggerFraction: c.autoAdjustTriggerFraction,
      ),
      smileProb = _AdaptiveThreshold(
        name: 'smileProbability',
        defaultValue: c.smileProbability ?? (Platform.isIOS ? 0.8 : 0.7),
        passWhenBelow: false,
        autoAdjust: c.autoAdjust,
        tolerance: c.autoAdjustTolerance,
        triggerFraction: c.autoAdjustTriggerFraction,
      ),
      headShakeAngle = _AdaptiveThreshold(
        name: 'headShakeAngle',
        defaultValue: c.headShakeAngle ?? (Platform.isIOS ? 11.5 : 10),
        passWhenBelow: false,
        autoAdjust: c.autoAdjust,
        tolerance: c.autoAdjustTolerance,
        triggerFraction: c.autoAdjustTriggerFraction,
      ),
      turnAngle = _AdaptiveThreshold(
        name: 'turnAngle',
        defaultValue: c.turnAngle ?? 15.0,
        passWhenBelow: false,
        autoAdjust: c.autoAdjust,
        tolerance: c.autoAdjustTolerance,
        triggerFraction: c.autoAdjustTriggerFraction,
      );

  final int blinkCount;
  final int mouthOpenFrames;
  final int smileFrames;
  final int headShakeReversals;
  final double captureYaw;
  final double capturePitch;
  final double captureRoll;
  final double minFaceWidthRatio;
  final double maxFaceWidthRatio;
  final double maxFaceCenterOffset;
  final double minBrightness;
  final double maxBrightness;
  final int holdFrames;

  final _AdaptiveThreshold blinkOpen;
  final _AdaptiveThreshold blinkClosed;
  final _AdaptiveThreshold mouthRatio;
  final _AdaptiveThreshold smileProb;
  final _AdaptiveThreshold headShakeAngle;
  final _AdaptiveThreshold turnAngle;
}

/// Per-step tracking of how close the user is getting, and the runtime
/// nudging of the gesture thresholds toward a struggling user.
extension _Adaptation on _FaceLivenessState {
  /// Called when a step begins (first step, or after each completed gesture).
  /// Resets the per-step adaptation bookkeeping.
  void _beginStepTracking() {
    _stepStartedAt = DateTime.now();
    _lastAdaptAt = null;
    _stepBest.clear();
  }

  /// Records the user's closest-to-passing value for [t] this step and, once
  /// `autoAdjust` is on and they've been landing just short of it past the
  /// grace period, walks [t] a bounded step their way.
  void _trackApproach(_AdaptiveThreshold t, double measured) {
    final prev = _stepBest[t.name];
    final closer =
        prev == null || (t.passWhenBelow ? measured < prev : measured > prev);
    if (closer) _stepBest[t.name] = measured;

    if (!t.autoAdjust) return;
    final best = _stepBest[t.name]!;
    final now = DateTime.now();
    final elapsed = now.difference(_stepStartedAt);
    if (elapsed < _kAdaptGracePeriod) return;
    if (_lastAdaptAt != null &&
        now.difference(_lastAdaptAt!) < _kAdaptInterval) {
      return;
    }

    final short = t.shortfall(best);
    if (short <= 0) return; // value side already clears — completion handles it

    final almost = short <= t.value.abs() * t.triggerFraction;
    // After a long, unproductive step: nudge anyway, provided the user has
    // reached at least a small fraction of the threshold (i.e. is trying the
    // right gesture, just weakly).
    final stuckButTrying =
        elapsed >= _kAdaptHardRelaxAfter &&
        short < t.value.abs() * (1 - _kAdaptHardRelaxMinProgress);
    if (!almost && !stuckButTrying) return;

    if (t.relaxToward(best)) {
      _lastAdaptAt = now;
      debugPrint(
        'adapt ${t.name}: ${t.value.toStringAsFixed(3)} '
        '(default ${t.defaultValue.toStringAsFixed(3)}, '
        'best ${best.toStringAsFixed(3)})',
      );
    }
  }

  /// The representative adaptive threshold behind [g] (blink is reported by
  /// its harder eyes-closed cutoff).
  _AdaptiveThreshold? _thresholdFor(LivenessGesture g) => switch (g) {
    LivenessGesture.blink => _thr.blinkClosed,
    LivenessGesture.mouthOpen => _thr.mouthRatio,
    LivenessGesture.smile => _thr.smileProb,
    LivenessGesture.headShake => _thr.headShakeAngle,
    LivenessGesture.turnLeft || LivenessGesture.turnRight => _thr.turnAngle,
  };

  /// Snapshots where [gesture]'s threshold landed, for the result payload.
  void _recordThresholdOutcome(LivenessGesture gesture) {
    final t = _thresholdFor(gesture);
    if (t == null) return;
    _thresholdAdjustments[gesture.name] = {
      'default': t.defaultValue,
      'effective': t.value,
      'relaxations': t.relaxations.toDouble(),
      if (_stepBest[t.name] != null) 'bestApproach': _stepBest[t.name]!,
    };
  }
}
