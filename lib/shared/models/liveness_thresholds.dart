/// Optional overrides for the numeric thresholds behind every liveness step,
/// plus the settings that control runtime auto-adjustment.
///
/// Every field is nullable and defaults to null — a null field means "use the
/// package default". Pass a [LivenessThresholds] to [LivenessConfig.thresholds]
/// only for the values you actually want to pin.
///
/// ## Auto-adjustment
///
/// When [autoAdjust] is true (the default), the *gesture* thresholds
/// (`blink*`, `mouthOpenRatio`, `smileProbability`, `headShakeAngle`,
/// `nodAngle`, `turnAngle`) are nudged toward a struggling user during a step: if the
/// best value they reach sits just short of passing — within
/// [autoAdjustTriggerFraction] of the threshold — for long enough, the
/// threshold moves a small step in the easier direction. It can never drift
/// further than [autoAdjustTolerance] (a fraction) away from the effective
/// default, so a single awkward user can't collapse it.
///
/// Frame-count thresholds and the final-capture quality gates
/// (`capture*`, `*FrameCount`, framing, brightness) are **configurable but
/// never auto-adjusted** — loosening those would undo the capture-quality
/// work the match depends on.
class LivenessThresholds {
  // --- Blink -----------------------------------------------------------------
  /// Eye-open probability above which an eye counts as "open" for the
  /// open→closed transition that makes a blink. Default 0.7. Auto-adjustable.
  final double? blinkEyeOpenProbability;

  /// Eye-open probability below which an eye counts as "closed". Default 0.3.
  /// Auto-adjustable (upward — a higher cutoff is easier to reach).
  final double? blinkEyeClosedProbability;

  /// Number of blinks required. Default 2. Config-only.
  final int? blinkCount;

  // --- Mouth open ----------------------------------------------------------
  /// Inner-lip gap as a fraction of inter-eye distance, above which the mouth
  /// is "open". Default 0.18. Auto-adjustable.
  final double? mouthOpenRatio;

  /// Consecutive open-mouth frames required. Default 4. Config-only.
  final int? mouthOpenFrameCount;

  // --- Smile ---------------------------------------------------------------
  /// Smiling probability above which the user is "smiling". Default 0.7.
  /// Auto-adjustable.
  final double? smileProbability;

  /// Consecutive smiling frames required (~16 ≈ 1.6s). Default 16. Config-only.
  final int? smileFrameCount;

  // --- Head shake --------------------------------------------------------
  /// Yaw magnitude (degrees) that counts as "clearly turned" for the
  /// side-to-side shake. Default 10. Auto-adjustable.
  final double? headShakeAngle;

  /// Number of direction reversals required — 1 ⇒ turn one way then the
  /// other once. Default 1. Config-only.
  final int? headShakeReversals;

  // --- Nod -------------------------------------------------------------------
  /// Pitch magnitude (degrees) that counts as "clearly down" or "clearly up"
  /// for a nod. Default 10. Auto-adjustable.
  final double? nodAngle;

  /// Number of direction reversals required — 1 ⇒ down then up (or up then
  /// down) once. Default 1. Config-only.
  final int? nodReversals;

  // --- Turn left / right ----------------------------------------------------
  /// Yaw magnitude (degrees) to hold for a turn-left / turn-right step.
  /// Default 15. Auto-adjustable.
  final double? turnAngle;

  // --- Final capture hold (config-only) -----------------------------------
  /// Max yaw / pitch / roll (degrees) allowed in the frame that gets
  /// captured. Defaults 5 / 8 / 8.
  final double? captureYawDegrees;
  final double? capturePitchDegrees;
  final double? captureRollDegrees;

  /// Face-box width as a fraction of the frame — min (too far) and max
  /// (too close). Defaults 0.26 and 0.72.
  final double? minFaceWidthRatio;
  final double? maxFaceWidthRatio;

  /// Max distance of the face-box centre from frame centre, as a fraction.
  /// Default 0.18.
  final double? maxFaceCenterOffset;

  /// Where the face's centre should sit, top to bottom, as a fraction of
  /// the frame: 0.5 is the middle (default), 0.43 is a little above it. For
  /// a screen whose face guide isn't vertically centred. With the preview
  /// filling a portrait screen (as `LivenessPreview` does when given the
  /// whole screen), a fraction of the screen's height is the same fraction
  /// of the frame's. Measured against [maxFaceCenterOffset].
  final double? faceCenterTargetY;

  /// Mean-luma (0–255) window the captured frame must fall inside.
  /// Defaults 55 and 225.
  final double? minFrameBrightness;
  final double? maxFrameBrightness;

  /// Consecutive good frames required before the still is taken. Default 20.
  final int? captureHoldFrames;

  // --- Auto-adjust controls ---------------------------------------------
  /// Master switch for runtime adjustment of the gesture thresholds.
  final bool autoAdjust;

  /// Largest fraction the effective default a threshold may drift under
  /// auto-adjust, e.g. 0.8 ⇒ the value stays within [0.2×, 1.8×] of default.
  final double autoAdjustTolerance;

  /// How near a threshold the user's best attempt must land to count as
  /// "almost passing" and trigger a nudge, as a fraction of the threshold.
  /// (After a step drags on, this gate is bypassed anyway as long as the user
  /// has got at least ~10% of the way there.)
  final double autoAdjustTriggerFraction;

  const LivenessThresholds({
    this.blinkEyeOpenProbability,
    this.blinkEyeClosedProbability,
    this.blinkCount,
    this.mouthOpenRatio,
    this.mouthOpenFrameCount,
    this.smileProbability,
    this.smileFrameCount,
    this.headShakeAngle,
    this.headShakeReversals,
    this.nodAngle,
    this.nodReversals,
    this.turnAngle,
    this.captureYawDegrees,
    this.capturePitchDegrees,
    this.captureRollDegrees,
    this.minFaceWidthRatio,
    this.maxFaceWidthRatio,
    this.maxFaceCenterOffset,
    this.faceCenterTargetY,
    this.minFrameBrightness,
    this.maxFrameBrightness,
    this.captureHoldFrames,
    this.autoAdjust = true,
    this.autoAdjustTolerance = 0.8,
    this.autoAdjustTriggerFraction = 0.5,
  });
}
