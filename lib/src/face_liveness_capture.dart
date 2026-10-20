part of 'liveness_controller.dart';

// Variance-of-Laplacian (on a 240px greyscale copy) at or above which a
// still is considered sharp enough that a second shot isn't worth taking.
const double _sharpEnoughScore = 300;

/// The final "hold still" phase: grading each frame for pose / framing /
/// lighting, driving the on-screen guidance, and once it's steady, locking
/// focus + taking the sharpest still.
extension _FinalCapture on LivenessController {
  /// Runs on every frame once all gestures are done. Grades the frame against
  /// the pose/framing/lighting checks (all from `_thr`), drives the on-screen
  /// guidance, and only lets the capture fire after `_thr.holdFrames` good
  /// frames in a row.
  void _evaluateFinalCapture(Face face, Size uprightFrame, double brightness) {
    final hint = _assessCaptureFrame(face, uprightFrame, brightness);

    if (hint != _captureHint) {
      _update(() => _captureHint = hint);
    }

    if (hint == null) {
      _facingCameraFrames++;
    } else {
      _facingCameraFrames = (_facingCameraFrames - 3).clamp(0, 999);
    }

    if (_facingCameraFrames >= _thr.holdFrames && !_isFacingCamera) {
      _isFacingCamera = true;
      _completeSuccessfully();
    }
  }

  /// Returns the single most important thing wrong with this frame, or null
  /// if it's good enough to capture. Order matters — pose first (cheapest to
  /// fix and most impactful), then framing, then lighting.
  LivenessCaptureHint? _assessCaptureFrame(
    Face face,
    Size uprightFrame,
    double brightness,
  ) {
    final yaw = face.headEulerAngleY;
    final pitch = face.headEulerAngleX;
    final roll = face.headEulerAngleZ;
    if (yaw == null || pitch == null || roll == null) {
      return LivenessCaptureHint.faceStraight;
    }
    if (yaw.abs() >= _thr.captureYaw) {
      return LivenessCaptureHint.faceStraight;
    }
    if (pitch.abs() >= _thr.capturePitch || roll.abs() >= _thr.captureRoll) {
      return LivenessCaptureHint.lookLevel;
    }

    // Framing. Skip these checks (rather than block) if the numbers look
    // implausible — a wrong rotation mapping shouldn't make capture
    // impossible, just unguided.
    final box = face.boundingBox;
    if (uprightFrame.width > 0 && uprightFrame.height > 0) {
      final widthRatio = box.width / uprightFrame.width;
      final cx = box.center.dx / uprightFrame.width;
      final cy = box.center.dy / uprightFrame.height;
      final plausible =
          widthRatio > 0 &&
          widthRatio < 1.5 &&
          cx > -0.25 &&
          cx < 1.25 &&
          cy > -0.25 &&
          cy < 1.25;
      if (plausible) {
        if (widthRatio < _thr.minFaceWidthRatio) {
          return LivenessCaptureHint.moveCloser;
        }
        if (widthRatio > _thr.maxFaceWidthRatio) {
          return LivenessCaptureHint.moveBack;
        }
        if ((cx - 0.5).abs() > _thr.maxFaceCenterOffset ||
            (cy - 0.5).abs() > _thr.maxFaceCenterOffset) {
          return LivenessCaptureHint.centerFace;
        }
      }
    }

    if (brightness.isFinite) {
      if (brightness < _thr.minBrightness) return LivenessCaptureHint.tooDark;
      if (brightness > _thr.maxBrightness) {
        return LivenessCaptureHint.tooBright;
      }
    }

    return null;
  }

  /// Called during the final capture hold when a frame has more than one
  /// face and `config.rejectMultipleFaces` is on.
  void _multipleFacesDuringCapture() {
    if (_captureHint != LivenessCaptureHint.multipleFaces) {
      _update(() => _captureHint = LivenessCaptureHint.multipleFaces);
    }
    _facingCameraFrames = (_facingCameraFrames - 3).clamp(0, 999);
  }

  /// Called during the final capture hold when a frame has no face at all.
  void _noFaceDuringCapture() {
    if (_captureHint != LivenessCaptureHint.noFace) {
      _update(() => _captureHint = LivenessCaptureHint.noFace);
    }
    _facingCameraFrames = (_facingCameraFrames - 3).clamp(0, 999);
  }

  /// Completes the flow successfully: stops the live frame stream, locks
  /// focus/exposure, takes the sharpest still, then reports the result and
  /// closes the page.
  Future<void> _completeSuccessfully() async {
    if (_isProcessing) return;
    _update(() {
      _isProcessing = true;
      _isCompleting = true;
    });
    _timer?.cancel();

    try {
      final controller = _cameraController;
      if (controller != null && controller.value.isStreamingImages) {
        await controller.stopImageStream();
        // Give the camera session a moment to fully settle after
        // stopping the stream — on some Android devices, calling
        // takePicture() immediately can hang indefinitely.
        await Future.delayed(const Duration(milliseconds: 250));
      }

      // The user is holding still and centred at this point, so pin
      // focus/exposure to the middle of the frame and lock them before
      // the still is taken — this avoids the final photo coming back
      // hunting for focus or mid exposure-ramp. Best effort: several
      // devices (and the front camera in particular) don't support one
      // or more of these, so each is guarded independently.
      if (controller != null) {
        await _lockFocusAndExposure(controller);
        await Future.delayed(const Duration(milliseconds: 200));
      }

      _capturedImages = await _captureStills(controller);
      _capturedImage = _capturedImages.isNotEmpty
          ? _capturedImages.first
          : null;
    } catch (e, s) {
      debugPrint('Failed to capture final liveness photo: $e');
      debugPrint('Failed to capture final liveness photo: $s');
    }

    _finish(
      LivenessResult(
        status: LivenessResultStatus.success,
        message: 'Liveness verification succeeded',
        capturedImage: _capturedImage,
        capturedImages: _capturedImages,
        completedGestures: _completedGestures.toList(),
        confidence: 0.95,
        duration: DateTime.now().difference(_startTime),
        thresholdAdjustments: Map.of(_thresholdAdjustments),
      ),
    );
  }

  /// Best-effort: point focus/exposure at the centre of the frame (where the
  /// user's face is during the capture hold) and lock them so the final
  /// still isn't taken mid AF/AE hunt. Every call is guarded on its own —
  /// unsupported operations throw `CameraException` rather than no-op, and
  /// support varies by device and lens.
  Future<void> _lockFocusAndExposure(CameraController controller) async {
    const centre = Offset(0.5, 0.5);

    Future<void> attempt(Future<void> Function() op) async {
      try {
        await op();
      } catch (e) {
        debugPrint('Focus/exposure lock step skipped: $e');
      }
    }

    await attempt(() => controller.setFocusPoint(centre));
    await attempt(() => controller.setExposurePoint(centre));
    // Let the sensor converge on the new point before freezing it.
    await Future.delayed(const Duration(milliseconds: 350));
    await attempt(() => controller.setFocusMode(FocusMode.locked));
    await attempt(() => controller.setExposureMode(ExposureMode.locked));
  }

  /// Takes up to two stills. The first frame right after the stream stops can
  /// come back soft (focus/exposure still settling); a second shot a beat
  /// later is often crisper. Returns every frame that succeeded, sharpest
  /// first, so the caller can average an embedding over them.
  Future<List<File>> _captureStills(CameraController? controller) async {
    if (controller == null) return const [];

    final shots = <(File, double)>[];
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        await Future.delayed(const Duration(milliseconds: 350));
      }
      try {
        final shot = await controller.takePicture().timeout(
          const Duration(seconds: 5),
        );
        final file = File(shot.path);
        final score = await _sharpnessScore(file);
        debugPrint('Liveness still attempt $attempt sharpness=$score');
        shots.add((file, score));
        if (score >= _sharpEnoughScore) break;
      } catch (e) {
        debugPrint('Liveness still attempt $attempt failed: $e');
      }
    }

    shots.sort((a, b) => b.$2.compareTo(a.$2));
    return shots.map((s) => s.$1).toList();
  }

  /// Variance of the Laplacian over a downscaled greyscale copy — higher is
  /// sharper. Used only to pick the better of two shots, so the absolute
  /// value doesn't need calibrating. Returns [double.infinity] if the image
  /// can't be decoded, so a decode failure never beats a real score in a way
  /// that would drop a usable frame.
  Future<double> _sharpnessScore(File file) async {
    try {
      final decoded = img.decodeImage(await file.readAsBytes());
      if (decoded == null) return double.infinity;
      final gray = img.grayscale(
        img.copyResize(img.bakeOrientation(decoded), width: 240),
      );
      final w = gray.width;
      final h = gray.height;
      var sum = 0.0;
      var sumSq = 0.0;
      var n = 0;
      for (var y = 1; y < h - 1; y++) {
        for (var x = 1; x < w - 1; x++) {
          final c = gray.getPixel(x, y).r;
          final up = gray.getPixel(x, y - 1).r;
          final down = gray.getPixel(x, y + 1).r;
          final left = gray.getPixel(x - 1, y).r;
          final right = gray.getPixel(x + 1, y).r;
          final lap = (4 * c - up - down - left - right).toDouble();
          sum += lap;
          sumSq += lap * lap;
          n++;
        }
      }
      if (n == 0) return 0;
      final mean = sum / n;
      return sumSq / n - mean * mean;
    } catch (e) {
      debugPrint('Sharpness score failed: $e');
      return double.infinity;
    }
  }
}
