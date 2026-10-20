part of 'liveness_controller.dart';

// Maps a reported device orientation to the rotation compensation (in
// degrees) needed on Android to turn camera-stream bytes upright for ML
// Kit. See _CameraInput._inputImageFromCameraImage.
const Map<DeviceOrientation, int> _orientations = <DeviceOrientation, int>{
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

/// Camera-frame plumbing: turning each [CameraImage] into an ML Kit
/// [InputImage], dispatching detection results, and cheap per-frame image
/// stats (upright frame size, brightness) the final-capture grading needs.
extension _CameraInput on LivenessController {
  /// Called on (roughly) every camera frame. Runs ML Kit face detection
  /// directly against the in-memory frame — no still-image capture, no
  /// per-frame file I/O — and drops frames that arrive while a previous one
  /// is still being processed instead of queuing them up.
  void _onCameraImage(CameraImage image) {
    if (_disposed || _finished || _isDetecting || _isProcessing) {
      return;
    }

    final inputImage = _inputImageFromCameraImage(image);
    if (inputImage == null) {
      // Silent otherwise — every gesture depends on a `Face` reaching
      // `_processFaceData`, so if this is what's actually happening (the
      // frame never even reaches ML Kit), every gesture fails uniformly
      // with nothing else in logcat to explain why. Throttled to ~1/sec
      // so it doesn't flood logcat at camera frame rate.
      _nullInputImageFrames++;
      if (_nullInputImageFrames % 30 == 1) {
        debugPrint(
          '🔍 no InputImage for frame (format/rotation unresolved) — '
          'count=$_nullInputImageFrames',
        );
      }
      return;
    }

    _isDetecting = true;
    _faceDetector
        .processImage(inputImage)
        .then((faces) {
          if (_disposed || _finished) return;
          if (faces.length != _faceCount) {
            _update(() => _faceCount = faces.length);
          }
          final crowded = config.rejectMultipleFaces && faces.length > 1;
          if (_isWaitingToStart) {
            _preparingFrame(faces, crowded, image);
          } else if (_isInFinalCapture) {
            if (crowded) {
              _multipleFacesDuringCapture();
            } else if (faces.isEmpty) {
              _noFaceDuringCapture();
            } else {
              _evaluateFinalCapture(
                faces.first,
                _uprightFrameSize(image),
                _estimateBrightness(image),
              );
            }
          } else if (crowded) {
            // Someone else is in the frame: no gesture counts until they
            // leave it.
          } else if (faces.isNotEmpty) {
            _processFaceData(faces.first);
          } else {
            // See the `inputImage == null` branch above for why this
            // needs its own visibility: every gesture reads off the same
            // `Face` this would have supplied.
            _emptyFacesFrames++;
            if (_emptyFacesFrames % 30 == 1) {
              debugPrint(
                '🔍 ML Kit returned 0 faces for frame — '
                'count=$_emptyFacesFrames',
              );
            }
          }
        })
        .catchError((e) {
          // PlatformException.toString() drops the native side's own stack
          // trace (`e.stacktrace`) — that's the piece that actually shows
          // where inside the compiled ML Kit/InputImageConverter code a
          // failure originates, which `$e` alone can't tell us.
          if (e is PlatformException) {
            // Logged as separate fields, not `$e`, because
            // PlatformException.toString() silently omits whichever of
            // these are null — and the native `InputImageConverter.kt`
            // that raises this passes the raw Java exception object as
            // `details`, not as `stacktrace`, so it's easy to lose
            // exactly the field that would carry it.
            debugPrint(
              '🔍 Face detection error — code: ${e.code}\n'
              'message: ${e.message}\n'
              'details: ${e.details}\n'
              'stacktrace: ${e.stacktrace}',
            );
          } else {
            debugPrint('🔍 Face detection error: $e');
          }
        })
        .whenComplete(() {
          _isDetecting = false;
        });
  }

  /// Converts a raw [CameraImage] from the live stream into the format
  /// ML Kit expects, including the rotation compensation needed to make
  /// sensor bytes upright. Returns null for any frame it can't confidently
  /// convert (that frame is simply skipped).
  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final controller = _cameraController;
    if (controller == null) return null;
    final camera = controller.description;

    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation =
          _orientations[controller.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null || image.planes.length != 1) return null;

    // `format` above only confirms the raw value is *some* format ML Kit
    // recognizes — not that it's the specific one requested below (the
    // camera/OS is free to substitute a different one; some devices'
    // camera HALs do exactly that regardless of the requested
    // `imageFormatGroup`). Sending a mismatched format straight to ML
    // Kit's native `InputImage.fromByteArray` is exactly the kind of
    // thing that fails deep inside Google's own compiled code rather
    // than with a clear Dart-side error, so check it explicitly instead
    // of assuming the request was honored.
    final expectedGroup = Platform.isAndroid
        ? ImageFormatGroup.nv21
        : ImageFormatGroup.bgra8888;
    if (image.format.group != expectedGroup) {
      _formatMismatchFrames++;
      if (_formatMismatchFrames % 30 == 1) {
        debugPrint(
          '🔍 camera delivered ${image.format.group} instead of '
          '$expectedGroup — count=$_formatMismatchFrames',
        );
      }
      return null;
    }

    // `format` (derived from the platform's raw format code,
    // `image.format.raw`) and `image.format.group` (the camera plugin's
    // own higher-level classification, checked above) are two separate
    // labels the plugin attaches to the same frame, and they can
    // disagree: `google_mlkit_commons` 0.13.0's native bridge added a
    // branch that forwards `ImageFormat.YUV_420_888` (raw 35) straight
    // into `InputImage.fromByteArray`, a call the *older* 0.11.1 bridge
    // deliberately never allowed — its own comment says YUV_420_888
    // needs `fromMediaImage` instead, not the flat-byte-array API. If
    // this camera plugin's NV21 conversion does the pixel-layout
    // conversion but doesn't update the raw format code it reports, we
    // could be sending `image_format: 35` for a buffer that's actually
    // already NV21 (single-plane, correct size — already confirmed via
    // mali_gralloc logs), which is exactly the shape of native failure
    // this has been hitting. Since `image.format.group` above already
    // confirms the buffer matches what we explicitly requested, trust
    // that instead of the raw-derived `format` when building the
    // metadata below.
    if (format != InputImageFormat.nv21 &&
        format != InputImageFormat.bgra8888) {
      debugPrint(
        '🔍 raw format code disagrees with group — raw=${image.format.raw} '
        'decoded=$format group=${image.format.group} (forcing $expectedGroup)',
      );
    }
    final trustedFormat = Platform.isAndroid
        ? InputImageFormat.nv21
        : InputImageFormat.bgra8888;

    _lastRotationDegrees = switch (rotation) {
      InputImageRotation.rotation90deg => 90,
      InputImageRotation.rotation180deg => 180,
      InputImageRotation.rotation270deg => 270,
      InputImageRotation.rotation0deg => 0,
    };

    final plane = image.planes.first;

    // `google_mlkit_commons`'s Android bridge (InputImageConverter.kt)
    // calls the native `InputImage.fromByteArray(data, width, height,
    // rotation, format)` — that signature has no stride/row-padding
    // parameter, so whatever we put in `bytesPerRow` below is silently
    // discarded on Android. If the camera ever hands us a row-padded
    // NV21 buffer (bytesPerRow > width — common when a resolution isn't
    // a clean multiple of the hardware's memory-alignment size), Google's
    // own byte-array size check receives something that doesn't match
    // width*height*1.5 and fails deep inside its compiled code with
    // nothing pointing back at the real cause. Only diagnosed, not fixed
    // here yet — fixing it means repacking the padded buffer down to a
    // tightly-packed one before this call, which isn't worth doing until
    // this confirms padding is actually present on the failing device.
    if (Platform.isAndroid) {
      final expectedSize = (image.width * image.height * 3) ~/ 2;
      final isPadded =
          plane.bytesPerRow != image.width ||
          plane.bytes.length != expectedSize;
      if (isPadded) _paddedBufferFrames++;
      if (!_loggedFirstFrameBufferInfo ||
          (isPadded && _paddedBufferFrames % 30 == 1)) {
        _loggedFirstFrameBufferInfo = true;
        debugPrint(
          '🔍 nv21 buffer — width=${image.width} height=${image.height} '
          'bytesPerRow=${plane.bytesPerRow} bytes.length=${plane.bytes.length} '
          'expected(unpadded)=$expectedSize padded=$isPadded '
          'paddedFrameCount=$_paddedBufferFrames',
        );
      }
    }

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: trustedFormat,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  /// Upright (post-rotation) dimensions of the live buffer, matching the
  /// coordinate space ML Kit reports face bounding boxes in.
  Size _uprightFrameSize(CameraImage image) {
    final swap = _lastRotationDegrees == 90 || _lastRotationDegrees == 270;
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    return swap ? Size(h, w) : Size(w, h);
  }

  /// Mean luma (0–255) over a sparse sample of the centre ~60% of the frame.
  /// Reads plane 0 directly: the Y plane for nv21 (Android), interleaved
  /// BGRA for bgra8888 (iOS). Sampling ~1k pixels keeps this well under a
  /// millisecond. Returns [double.infinity] if it can't read the buffer, so
  /// callers treat lighting as "unknown / don't block".
  double _estimateBrightness(CameraImage image) {
    try {
      final plane = image.planes.first;
      final bytes = plane.bytes;
      final width = image.width;
      final height = image.height;
      final bytesPerRow = plane.bytesPerRow;
      final isBgra = image.format.group == ImageFormatGroup.bgra8888;
      final bytesPerPixel = isBgra ? 4 : 1;

      final x0 = (width * 0.2).round();
      final x1 = (width * 0.8).round();
      final y0 = (height * 0.2).round();
      final y1 = (height * 0.8).round();
      final stepX = math.max(1, (x1 - x0) ~/ 32);
      final stepY = math.max(1, (y1 - y0) ~/ 32);

      double sum = 0;
      int count = 0;
      for (var y = y0; y < y1; y += stepY) {
        final rowStart = y * bytesPerRow;
        for (var x = x0; x < x1; x += stepX) {
          final idx = rowStart + x * bytesPerPixel;
          if (idx + bytesPerPixel > bytes.length) continue;
          if (isBgra) {
            final b = bytes[idx];
            final g = bytes[idx + 1];
            final r = bytes[idx + 2];
            sum += 0.114 * b + 0.587 * g + 0.299 * r;
          } else {
            sum += bytes[idx];
          }
          count++;
        }
      }
      if (count == 0) return double.infinity;
      return sum / count;
    } catch (e) {
      debugPrint('Brightness estimate failed: $e');
      return double.infinity;
    }
  }
}
