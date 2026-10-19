part of 'face_compare.dart';

/// Canonical 5-point face template for a 112×112 crop (ArcFace/FaceNet
/// convention): left eye, right eye, nose, left mouth, right mouth. Only the
/// two eye points are used by the current 2-point similarity alignment; the
/// rest are kept for reference / a future least-squares fit.
const List<List<double>> _kCanonical112 = [
  [38.2946, 51.6963],
  [73.5318, 51.5014],
  [56.0252, 71.7366],
  [41.5493, 92.3655],
  [70.7299, 92.2041],
];

/// Result of a detailed compare, with the quality signals that explain a low
/// score (so a caller can ask for a better retake rather than just failing).
class FaceCompareResult {
  final double score; // 0–100
  final int referenceFacePx; // detected face box width in the reference image
  final int probeFacePx; // "" in the (sharpest) probe image
  final int probeFramesUsed; // how many live frames contributed to the probe
  final bool referenceUpscaled;

  const FaceCompareResult({
    required this.score,
    required this.referenceFacePx,
    required this.probeFacePx,
    required this.probeFramesUsed,
    required this.referenceUpscaled,
  });

  @override
  String toString() =>
      'FaceCompareResult(score: ${score.toStringAsFixed(1)}, '
      'referenceFacePx: $referenceFacePx, probeFacePx: $probeFacePx, '
      'probeFramesUsed: $probeFramesUsed, referenceUpscaled: $referenceUpscaled)';
}

/// Result of running face detection multiple times on the same image and
/// averaging the outputs, to smooth out the few-pixel run-to-run jitter
/// ML Kit's detector produces even on identical input.
class _AveragedFace {
  final double left, top, right, bottom;
  final ui.Offset? leftEye;
  final ui.Offset? rightEye;
  final int passesUsed;
  final int passesRequested;
  final int lastPassFaceCount;

  _AveragedFace({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.leftEye,
    required this.rightEye,
    required this.passesUsed,
    required this.passesRequested,
    required this.lastPassFaceCount,
  });

  double get width => right - left;

  double get height => bottom - top;
}

/// Detection + geometric alignment: everything that turns an image file into a
/// model-ready face crop.
extension _FaceCompareAlign on FaceCompare {
  /// Detects + aligns the face crop, or throws the same user-facing message
  /// [FaceCompare.getEmbedding] has always thrown when nothing usable is
  /// found.
  Future<img.Image> _cropOrThrow(File imageFile) async {
    if (_interpreter == null) {
      throw StateError(
        'FaceCompareHelper not initialized. Use FaceCompareHelper.create() instead.',
      );
    }

    final cropped = await _detectAndCropFace(imageFile);
    if (cropped == null) {
      debugPrint(
        "$_tag ❌ No face detected in image: ${imageFile.path}. Make sure the face is clear, well lit, and facing the camera.",
      );
      throw Exception(
        "Make sure the face is clear, well lit, and facing the camera.",
      );
    }
    return cropped;
  }

  /// Detects a face and crops it (uses the largest face found, then aligns
  /// it based on eye position).
  Future<img.Image?> _detectAndCropFace(File imageFile) async {
    debugPrint('$_tag ---- _detectAndCropFace: ${imageFile.path} ----');

    final bytes = await imageFile.readAsBytes();
    if (bytes.isEmpty) {
      debugPrint('$_tag ❌ ${imageFile.path} is empty (0 bytes)');
      throw Exception(
        'The reference photo is missing or empty. It may not have been '
        'provided by the identity check.',
      );
    }

    img.Image? tryDecode() {
      try {
        // The `image` package's format sniffers can throw on truncated /
        // non-image data rather than returning null.
        return img.decodeImage(bytes);
      } catch (e) {
        debugPrint('$_tag ❌ decodeImage threw for ${imageFile.path}: $e');
        return null;
      }
    }

    final decoded = tryDecode();
    if (decoded == null) {
      debugPrint('$_tag ❌ decodeImage failed for ${imageFile.path}');
      throw Exception(
        'Could not read the reference photo — it is not a supported or '
        'intact image.',
      );
    }
    debugPrint(
      '$_tag decoded raw size: ${decoded.width}x${decoded.height}, '
      'exif orientation present: ${decoded.exif.imageIfd.hasOrientation}',
    );

    var rawImage = img.bakeOrientation(decoded);
    debugPrint(
      '$_tag post-bakeOrientation size: ${rawImage.width}x${rawImage.height}',
    );

    // Small reference photos (a passport-style ID crop is often only ~200px
    // wide) leave the detector too little to work with and force the model to
    // upsample from a handful of pixels. Enlarge with cubic interpolation and
    // a light unsharp mask first.
    _lastReferenceUpscaled = false;
    const minWorkingWidth = 480;
    if (rawImage.width < minWorkingWidth) {
      final scaled = img.copyResize(
        rawImage,
        width: minWorkingWidth,
        interpolation: img.Interpolation.cubic,
      );
      rawImage = _unsharp(scaled, amount: 0.6, radius: 1);
      _lastReferenceUpscaled = true;
      debugPrint(
        '$_tag upscaled small reference ${decoded.width}px -> '
        '${rawImage.width}px',
      );
    }

    final tempDir = await getTemporaryDirectory();
    final orientedPath =
        '${tempDir.path}/oriented_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final orientedFile = await File(
      orientedPath,
    ).writeAsBytes(img.encodeJpg(rawImage));
    debugPrint('$_tag wrote oriented file for ML Kit: $orientedPath');

    const detectionPasses = 3;
    final averaged = await _detectAveragedFace(
      orientedFile.path,
      rawImage: rawImage,
      passes: detectionPasses,
    );

    // ignore: body_might_complete_normally_catch_error
    unawaited(orientedFile.delete().catchError((_) {}));

    if (averaged == null) {
      debugPrint(
        '$_tag ❌ no face found in any of $detectionPasses passes — returning null',
      );
      return null;
    }

    debugPrint(
      '$_tag averaged over ${averaged.passesUsed}/${averaged.passesRequested} passes: '
      'bbox=(${averaged.left.toStringAsFixed(1)},${averaged.top.toStringAsFixed(1)})-'
      '(${averaged.right.toStringAsFixed(1)},${averaged.bottom.toStringAsFixed(1)}) '
      'leftEye=${averaged.leftEye} rightEye=${averaged.rightEye} '
      'lastPassFaceCount=${averaged.lastPassFaceCount}',
    );

    _lastFacePx = averaged.width.round();

    // Preferred path: a similarity transform straight onto the canonical
    // template (scale + rotation + translation in one step), producing the
    // model input at [_inputSize].
    //
    // If eye alignment is on but ML Kit gave no eye position (landmarks OR
    // contours) on any pass, DON'T guess from the box — a box-geometry
    // estimate frames the face differently enough to swing the score 20-50
    // points, so the same image scores randomly. A clean "no usable face" is
    // better: the caller retakes (app) or the pair errors (lab).
    if (_eyeAlignment) {
      if (averaged.leftEye == null || averaged.rightEye == null) {
        debugPrint(
          '$_tag ❌ eye alignment on but ML Kit produced no eye landmarks or '
          'contours across ${averaged.passesRequested}+ passes — no usable '
          'face',
        );
        return null;
      }
      final aligned = _alignByEyes(
        rawImage,
        averaged.leftEye!,
        averaged.rightEye!,
        _inputSize,
      );
      if (_debug) {
        await _saveDebugImage(
          aligned,
          'aligned_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
      }
      debugPrint(
        '$_tag eye-aligned crop -> ${aligned.width}x${aligned.height}',
      );
      return aligned;
    }

    const marginRatio = 0.08;
    final x = (averaged.left - averaged.width * marginRatio).toInt().clamp(
      0,
      rawImage.width - 1,
    );
    final y = (averaged.top - averaged.height * marginRatio).toInt().clamp(
      0,
      rawImage.height - 1,
    );
    final w = (averaged.width * (1 + 2 * marginRatio)).toInt();
    final h = (averaged.height * (1 + 2 * marginRatio)).toInt();

    final size = math
        .max(w, h)
        .clamp(1, math.min(rawImage.width - x, rawImage.height - y))
        .toInt();
    debugPrint(
      '$_tag crop params: x=$x y=$y w=$w h=$h -> pre-rotation square size=$size',
    );

    var cropped = img.copyCrop(rawImage, x: x, y: y, width: size, height: size);
    debugPrint(
      '$_tag cropped (pre-rotation) size: ${cropped.width}x${cropped.height}',
    );

    // Below this many degrees, ML Kit's landmark jitter (confirmed to be
    // ~2-3° run-to-run on identical input) is bigger than the real signal —
    // "correcting" it just injects noise. Skip rotation entirely below it.
    const minTiltDegreesToCorrect = 3.0;

    if (averaged.leftEye != null && averaged.rightEye != null) {
      final dy = averaged.rightEye!.dy - averaged.leftEye!.dy;
      final dx = averaged.rightEye!.dx - averaged.leftEye!.dx;
      final tilt = math.atan2(dy, dx);
      final tiltDeg = tilt * 180 / math.pi;
      debugPrint(
        '$_tag dx=${dx.toStringAsFixed(2)} dy=${dy.toStringAsFixed(2)} '
        'tilt=${tiltDeg.toStringAsFixed(2)}° (positive = right eye lower / clockwise tilt)',
      );

      if (tiltDeg.abs() < minTiltDegreesToCorrect) {
        debugPrint(
          '$_tag |tilt| < $minTiltDegreesToCorrect° — treating as detector noise, skipping rotation',
        );
      } else {
        // copyRotate's positive angle rotates the image clockwise — same
        // direction as a positive tilt — so negate to level the eyes.
        final rotateAngle = -tiltDeg;
        cropped = img.copyRotate(cropped, angle: rotateAngle);
        debugPrint(
          '$_tag applied copyRotate(angle: ${rotateAngle.toStringAsFixed(2)}°) '
          '-> canvas now ${cropped.width}x${cropped.height}',
        );

        // Largest axis-aligned square inside a square of side `size` rotated
        // by |tilt|, so the final crop contains no black corner pixels.
        final phi = tilt.abs() % (math.pi / 2);
        final reducedPhi = phi > math.pi / 4 ? math.pi / 2 - phi : phi;
        final safeSize = (size / (math.cos(reducedPhi) + math.sin(reducedPhi)))
            .floor();
        debugPrint(
          '$_tag safe inscribed square size: $safeSize '
          '(pre-rotation size=$size, reducedPhi=${(reducedPhi * 180 / math.pi).toStringAsFixed(2)}°)',
        );

        cropped = img.copyCrop(
          cropped,
          x: (cropped.width - safeSize) ~/ 2,
          y: (cropped.height - safeSize) ~/ 2,
          width: safeSize,
          height: safeSize,
        );
        debugPrint(
          '$_tag post-rotation re-crop size: ${cropped.width}x${cropped.height}',
        );
      }
    } else {
      debugPrint(
        '$_tag ⚠️ eye landmarks missing — skipping alignment entirely',
      );
    }

    if (_debug) {
      await _saveDebugImage(
        cropped,
        "cropped_${DateTime.now().millisecondsSinceEpoch}.jpg",
      );
    }

    debugPrint(
      '$_tag final aligned crop size: ${cropped.width}x${cropped.height}',
    );
    return cropped;
  }

  /// Runs ML Kit face detection [passes] times on the same file and
  /// averages the largest face's bounding box and eye landmarks across
  /// passes that found a face, to cancel out the detector's inherent
  /// run-to-run jitter. Returns null only if every pass found nothing.
  Future<_AveragedFace?> _detectAveragedFace(
    String path, {
    required img.Image rawImage,
    int passes = 3,
  }) async {
    final lefts = <double>[];
    final tops = <double>[];
    final rights = <double>[];
    final bottoms = <double>[];
    final leftEyes = <ui.Offset>[];
    final rightEyes = <ui.Offset>[];
    int lastPassFaceCount = 0;

    // ML Kit's landmark detection is flaky on marginal faces — it can find a
    // box but no eyes on one attempt and succeed on the next. If the base
    // passes yield a box but no eyes, run a few more before giving up.
    const maxExtraPasses = 3;
    var totalPasses = passes;

    for (var i = 0; i < totalPasses; i++) {
      final inputImage = InputImage.fromFilePath(path);
      final stopwatch = Stopwatch()..start();
      final faces = await _faceDetector.processImage(inputImage);
      stopwatch.stop();
      lastPassFaceCount = faces.length;
      debugPrint(
        '$_tag detect pass $i took ${stopwatch.elapsedMilliseconds}ms, '
        'found ${faces.length} face(s)',
      );

      if (faces.isEmpty) {
        debugPrint('$_tag pass $i: no face found, skipping this pass');
        continue;
      }

      for (var j = 0; j < faces.length; j++) {
        final f = faces[j];
        final area = f.boundingBox.width * f.boundingBox.height;
        debugPrint(
          '$_tag pass $i face[$j] bbox=${f.boundingBox} area=${area.toStringAsFixed(0)} '
          'hasLeftEye=${f.landmarks[FaceLandmarkType.leftEye] != null} '
          'hasRightEye=${f.landmarks[FaceLandmarkType.rightEye] != null}',
        );
      }

      // Drop phantom detections: ML Kit occasionally emits a ghost face with
      // a non-positive or largely off-frame bounding box (seen at negative
      // coordinates). Blending one of these into the average wrecks the crop.
      final imW = rawImage.width;
      final imH = rawImage.height;
      final plausible = faces.where((f) {
        final r = f.boundingBox;
        if (r.width <= 1 || r.height <= 1) return false;
        // Reject if the box is mostly outside the image.
        final ix = r.left.clamp(0.0, imW.toDouble());
        final iy = r.top.clamp(0.0, imH.toDouble());
        final ix2 = r.right.clamp(0.0, imW.toDouble());
        final iy2 = r.bottom.clamp(0.0, imH.toDouble());
        final insideArea = (ix2 - ix) * (iy2 - iy);
        return insideArea >= 0.6 * r.width * r.height;
      }).toList();
      if (plausible.isEmpty) {
        debugPrint(
          '$_tag pass $i: ${faces.length} face(s) but all implausible '
          '(off-frame / zero-size), skipping this pass',
        );
        continue;
      }
      faces
        ..clear()
        ..addAll(plausible);

      // Only dump candidate crops once, from the first pass, so a 3-pass
      // multi-face capture doesn't produce 6-9 near-duplicate debug files.
      if (i == 0 && _debug && faces.length > 1) {
        for (var j = 0; j < faces.length; j++) {
          final b = faces[j].boundingBox;
          final bx = b.left.toInt().clamp(0, rawImage.width - 1);
          final by = b.top.toInt().clamp(0, rawImage.height - 1);
          final bw = b.width.toInt().clamp(1, rawImage.width - bx);
          final bh = b.height.toInt().clamp(1, rawImage.height - by);
          final candidate = img.copyCrop(
            rawImage,
            x: bx,
            y: by,
            width: bw,
            height: bh,
          );
          await _saveDebugImage(
            candidate,
            'candidate_${j}_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
        }
      }

      faces.sort(
        (a, b) => (b.boundingBox.width * b.boundingBox.height).compareTo(
          a.boundingBox.width * a.boundingBox.height,
        ),
      );
      final face = faces.first;
      final b = face.boundingBox;
      lefts.add(b.left);
      tops.add(b.top);
      rights.add(b.right);
      bottoms.add(b.bottom);

      // Eye positions: prefer the landmark points; if ML Kit didn't produce
      // them (flaky on marginal faces) fall back to the *centre* of the eye
      // contour clouds, which are computed separately and often survive when
      // the landmarks don't. Both are real detected positions — unlike a
      // box-geometry guess, which frames the face differently.
      final eyes = _eyePair(face);
      if (eyes != null) {
        leftEyes.add(eyes.$1);
        rightEyes.add(eyes.$2);
      }

      if (i == totalPasses - 1 &&
          leftEyes.isEmpty &&
          lefts.isNotEmpty &&
          totalPasses < passes + maxExtraPasses) {
        totalPasses++;
        debugPrint(
          '$_tag box found but no eye landmarks — extra detect pass '
          '(#$totalPasses)',
        );
      }
    }

    if (lefts.isEmpty) return null;

    double avg(List<double> v) => v.reduce((a, b) => a + b) / v.length;

    var avgLeftEye = leftEyes.isEmpty
        ? null
        : ui.Offset(
            avg(leftEyes.map((p) => p.dx).toList()),
            avg(leftEyes.map((p) => p.dy).toList()),
          );
    var avgRightEye = rightEyes.isEmpty
        ? null
        : ui.Offset(
            avg(rightEyes.map((p) => p.dx).toList()),
            avg(rightEyes.map((p) => p.dy).toList()),
          );

    // Guard the eye-alignment path: only trust the averaged eyes if they sit
    // inside the frame, above the box's vertical midpoint, and the right eye
    // is to the right of the left one (the non-mirrored ordering _alignByEyes
    // assumes). Otherwise fall through to the plain bbox crop.
    bool eyesUsable() {
      final l = avgLeftEye, r = avgRightEye;
      if (l == null || r == null) return false;
      final midY = avg(tops) + (avg(bottoms) - avg(tops)) / 2;
      for (final p in [l, r]) {
        if (p.dx < 0 ||
            p.dy < 0 ||
            p.dx > rawImage.width ||
            p.dy > rawImage.height ||
            p.dy > midY) {
          return false;
        }
      }
      return r.dx > l.dx;
    }

    if (!eyesUsable()) {
      if (avgLeftEye != null || avgRightEye != null) {
        debugPrint('$_tag ⚠️ averaged eyes implausible — dropping to bbox crop');
      }
      avgLeftEye = null;
      avgRightEye = null;
    }

    return _AveragedFace(
      left: avg(lefts),
      top: avg(tops),
      right: avg(rights),
      bottom: avg(bottoms),
      leftEye: avgLeftEye,
      rightEye: avgRightEye,
      passesUsed: lefts.length,
      passesRequested: passes,
      lastPassFaceCount: lastPassFaceCount,
    );
  }

  /// (leftEye, rightEye) image-space centres for [face], from landmarks if
  /// present, otherwise from the mean of the eye contour points. Null when
  /// ML Kit gave neither.
  (ui.Offset, ui.Offset)? _eyePair(Face face) {
    final le = face.landmarks[FaceLandmarkType.leftEye];
    final re = face.landmarks[FaceLandmarkType.rightEye];
    if (le != null && re != null) {
      return (
        ui.Offset(le.position.x.toDouble(), le.position.y.toDouble()),
        ui.Offset(re.position.x.toDouble(), re.position.y.toDouble()),
      );
    }

    ui.Offset? contourCentre(FaceContourType t) {
      final pts = face.contours[t]?.points;
      if (pts == null || pts.isEmpty) return null;
      var sx = 0.0;
      var sy = 0.0;
      for (final p in pts) {
        sx += p.x;
        sy += p.y;
      }
      return ui.Offset(sx / pts.length, sy / pts.length);
    }

    final lc = contourCentre(FaceContourType.leftEye);
    final rc = contourCentre(FaceContourType.rightEye);
    if (lc != null && rc != null) return (lc, rc);
    return null;
  }

  /// Saves the cropped face image for debugging purposes
  Future<void> _saveDebugImage(img.Image face, String name) async {
    final dir = await getTemporaryDirectory();
    final file = File("${dir.path}/$name");
    await file.writeAsBytes(img.encodeJpg(face));
    debugPrint("$_tag ✅ debug crop saved at: ${file.path}");
  }

  /// Aligns a face to the canonical template at [outSize]×[outSize] using a
  /// 2-point (both eyes) similarity transform: solves the
  /// scale/rotation/translation that maps the detected eye centres onto
  /// [_kCanonical112]'s first two points (scaled to [outSize]), then
  /// inverse-maps every output pixel and bilinearly samples [src]. Removes
  /// in-plane rotation, scale and translation in one pass — no separate
  /// rotate-and-recrop, no black corners.
  img.Image _alignByEyes(
    img.Image src,
    ui.Offset leftEye,
    ui.Offset rightEye,
    int outSize,
  ) {
    final k = outSize / 112.0;
    final s0x = leftEye.dx, s0y = leftEye.dy;
    final s1x = rightEye.dx, s1y = rightEye.dy;
    final d0x = _kCanonical112[0][0] * k, d0y = _kCanonical112[0][1] * k;
    final d1x = _kCanonical112[1][0] * k, d1y = _kCanonical112[1][1] * k;

    final sdx = s1x - s0x, sdy = s1y - s0y;
    final denom = sdx * sdx + sdy * sdy;
    if (denom < 1e-6) {
      // Degenerate (eyes on top of each other) — fall back to a plain resize.
      return img.copyResize(src, width: outSize, height: outSize);
    }
    final ddx = d1x - d0x, ddy = d1y - d0y;

    // Forward similarity: [a -b; b a] * s + [tx, ty] = d
    final a = (sdx * ddx + sdy * ddy) / denom;
    final b = (sdx * ddy - sdy * ddx) / denom;
    final tx = d0x - (a * s0x - b * s0y);
    final ty = d0y - (b * s0x + a * s0y);

    // Inverse of the same transform, for output→source sampling.
    final det = a * a + b * b;
    final out = img.Image(width: outSize, height: outSize, numChannels: 3);
    final maxX = src.width - 1;
    final maxY = src.height - 1;

    for (var oy = 0; oy < outSize; oy++) {
      for (var ox = 0; ox < outSize; ox++) {
        final rx = ox - tx;
        final ry = oy - ty;
        final sx = (a * rx + b * ry) / det;
        final sy = (-b * rx + a * ry) / det;

        // Bilinear sample with edge clamp.
        final fx = sx.clamp(0.0, maxX.toDouble());
        final fy = sy.clamp(0.0, maxY.toDouble());
        final x0 = fx.floor();
        final y0 = fy.floor();
        final x1 = math.min(x0 + 1, maxX);
        final y1 = math.min(y0 + 1, maxY);
        final wx = fx - x0;
        final wy = fy - y0;

        final p00 = src.getPixel(x0, y0);
        final p10 = src.getPixel(x1, y0);
        final p01 = src.getPixel(x0, y1);
        final p11 = src.getPixel(x1, y1);

        double lerp(num c00, num c10, num c01, num c11) =>
            (c00 * (1 - wx) + c10 * wx) * (1 - wy) +
            (c01 * (1 - wx) + c11 * wx) * wy;

        out.setPixelRgb(
          ox,
          oy,
          lerp(p00.r, p10.r, p01.r, p11.r).round().clamp(0, 255),
          lerp(p00.g, p10.g, p01.g, p11.g).round().clamp(0, 255),
          lerp(p00.b, p10.b, p01.b, p11.b).round().clamp(0, 255),
        );
      }
    }
    return out;
  }

  /// scaled + amount·(scaled − blur(scaled)) — a light unsharp mask, clamped.
  img.Image _unsharp(img.Image scaled, {double amount = 0.6, int radius = 1}) {
    final blurred = img.gaussianBlur(scaled.clone(), radius: radius);
    final out = img.Image(
      width: scaled.width,
      height: scaled.height,
      numChannels: 3,
    );
    for (var y = 0; y < scaled.height; y++) {
      for (var x = 0; x < scaled.width; x++) {
        final s = scaled.getPixel(x, y);
        final bl = blurred.getPixel(x, y);
        int sharp(num sv, num bv) =>
            (sv + amount * (sv - bv)).round().clamp(0, 255);
        out.setPixelRgb(
          x,
          y,
          sharp(s.r, bl.r),
          sharp(s.g, bl.g),
          sharp(s.b, bl.b),
        );
      }
    }
    return out;
  }
}
