import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// A face found in a photo by [LivenessPhotoFaces.find].
@immutable
class LivenessPhotoFace {
  const LivenessPhotoFace({
    required this.bounds,
    this.yaw,
    this.pitch,
    this.roll,
    this.leftEyeOpen,
    this.rightEyeOpen,
  });

  /// Where the face is, in the photo's pixels.
  final Rect bounds;

  /// Head turned left or right, in degrees. Null when it wasn't measured,
  /// as for the other readings.
  final double? yaw;

  /// Head tilted up or down, in degrees.
  final double? pitch;

  /// Head leaning towards a shoulder, in degrees.
  final double? roll;

  /// How likely each eye is open, from 0 to 1.
  final double? leftEyeOpen;
  final double? rightEyeOpen;
}

/// Finds the faces in a photo on disk, such as the still a liveness check
/// took (`LivenessResult.capturedImage`), with the same ML Kit face detector
/// the check uses. An app can then check the photo itself (one face,
/// looking ahead, eyes open) or find where the face is, without depending
/// on ML Kit.
///
/// Positions are in the photo's pixels as stored. A camera may store a
/// photo sideways with a tag saying how to turn it: to measure it as it is
/// shown, pass a copy turned upright.
abstract final class LivenessPhotoFaces {
  /// The faces in the photo at [path]. [minFaceSize] is the smallest face
  /// looked for, as a share of the photo's width.
  static Future<List<LivenessPhotoFace>> find(
    String path, {
    double minFaceSize = 0.1,
  }) async {
    final detector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: minFaceSize,
      ),
    );
    try {
      final faces = await detector.processImage(InputImage.fromFilePath(path));
      return [
        for (final face in faces)
          LivenessPhotoFace(
            bounds: face.boundingBox,
            yaw: face.headEulerAngleY,
            pitch: face.headEulerAngleX,
            roll: face.headEulerAngleZ,
            leftEyeOpen: face.leftEyeOpenProbability,
            rightEyeOpen: face.rightEyeOpenProbability,
          ),
      ];
    } finally {
      await detector.close();
    }
  }
}
