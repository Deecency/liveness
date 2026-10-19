part of 'face_compare.dart';

/// Temporary diagnostic — run once on the failing image and check the logs.
Future<void> diagnoseFaceDetection(File imageFile) async {
  debugPrint("=== FACE DETECTION DIAGNOSTIC ===");
  debugPrint("File path: ${imageFile.path}");
  debugPrint("File exists: ${await imageFile.exists()}");
  debugPrint("File size: ${await imageFile.length()} bytes");

  final bytes = await imageFile.readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    debugPrint("❌ img.decodeImage FAILED — file isn't a decodable image");
    return;
  }
  debugPrint("Raw decoded size: ${decoded.width}x${decoded.height}");
  debugPrint(
    "EXIF orientation present: ${decoded.exif.imageIfd.hasOrientation}",
  );

  final rawImage = img.bakeOrientation(decoded);
  debugPrint("Post-bakeOrientation size: ${rawImage.width}x${rawImage.height}");

  final debugDir = await imageFile.parent.exists()
      ? imageFile.parent
      : Directory.systemTemp;
  final debugPath =
      '${debugDir.path}/diag_raw_${DateTime.now().millisecondsSinceEpoch}.jpg';
  await File(debugPath).writeAsBytes(img.encodeJpg(rawImage, quality: 90));
  debugPrint("Saved orientation-corrected image to: $debugPath");
  debugPrint(
    "👉 Open this file manually and confirm the face is upright and not mirrored/cropped oddly.",
  );

  await _tryDetect(
    label: "InputImage.fromFile + accurate + minFaceSize=0.1 (default)",
    inputImage: InputImage.fromFile(imageFile),
    options: FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  await _tryDetect(
    label: "InputImage.fromFile + fast + minFaceSize=0.1 (default)",
    inputImage: InputImage.fromFile(imageFile),
    options: FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  await _tryDetect(
    label: "InputImage.fromFile + accurate + minFaceSize=0.03",
    inputImage: InputImage.fromFile(imageFile),
    options: FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.03,
    ),
  );

  debugPrint("=== END DIAGNOSTIC ===");
}

Future<void> _tryDetect({
  required String label,
  required InputImage inputImage,
  required FaceDetectorOptions options,
}) async {
  final detector = FaceDetector(options: options);
  try {
    final stopwatch = Stopwatch()..start();
    final faces = await detector.processImage(inputImage);
    stopwatch.stop();
    debugPrint(
      "[$label] → ${faces.length} face(s) found in ${stopwatch.elapsedMilliseconds}ms",
    );
    for (final f in faces) {
      debugPrint(
        "   bbox=${f.boundingBox}, headEulerY=${f.headEulerAngleY}, headEulerZ=${f.headEulerAngleZ}",
      );
    }
  } catch (e) {
    debugPrint("[$label] ❌ threw: $e");
  } finally {
    await detector.close();
  }
}
