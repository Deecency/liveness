import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_litert/flutter_litert.dart';

part 'face_compare_align.dart';
part 'face_compare_diagnostic.dart';
part 'face_compare_embed.dart';

const String _tag = '[FaceCompare]';

/// Which bundled embedding model [FaceCompare] runs.
enum FaceModel {
  /// MobileFaceNet: 112×112×3 NHWC input, `(x-127.5)/128` normalization,
  /// ~192-D self-L2-normalized embedding. Small (~5 MB) and fast (~25 ms).
  /// The default.
  mobileFaceNet(
    'packages/liveness/assets/models/mobilefacenet.tflite',
    wantsPrewhiten: false,
  ),

  /// FaceNet (Inception-ResNet-v1), 128-D. 160×160 input, per-image
  /// "prewhiten" normalization. ~24 MB. The older / weaker FaceNet export.
  faceNet(
    'packages/liveness/assets/models/facenet.tflite',
    wantsPrewhiten: true,
  ),

  /// FaceNet (Inception-ResNet-v1), 512-D — the 20180402 VGGFace2 model,
  /// generally the strongest of the FaceNet family. 160×160 input, prewhiten.
  /// ~24 MB.
  faceNet512(
    'packages/liveness/assets/models/facenet_512.tflite',
    wantsPrewhiten: true,
  );

  const FaceModel(this.asset, {required this.wantsPrewhiten});

  /// tflite asset path (as passed to `Interpreter.fromAsset`).
  final String asset;

  /// The normalization this model's training expects, used as the default
  /// for `create(prewhiten: ...)` when the caller doesn't specify.
  final bool wantsPrewhiten;
}

/// Face matcher: detects + aligns a face in each image, embeds it with the
/// chosen [FaceModel], and scores the pair by cosine similarity.
///
/// The pipeline is split across three `part` files:
///  - `face_compare_align.dart`     — detect, average, eye-similarity warp
///  - `face_compare_embed.dart`     — preprocess + model inference
///  - `face_compare_diagnostic.dart`— standalone detection diagnostic
class FaceCompare {
  Interpreter? _interpreter;
  late List<int> _outputShape;

  /// Square side (px) of the model's input tensor, read from the graph at
  /// load time. MobileFaceNet is 112; kept dynamic so a model swap doesn't
  /// need a code change here.
  late int _inputSize;

  final bool _debug;

  /// When true, faces are aligned with a 2-point (eyes) similarity transform
  /// straight onto the canonical template at model-input size, instead of the
  /// older crop → rotate → re-crop → resize. Falls back to the old path when
  /// eye landmarks are missing.
  final bool _eyeAlignment;

  /// When true, each aligned crop gets a mild per-channel contrast stretch
  /// before embedding, to pull a flat ID photo and a differently-lit selfie
  /// closer together. First thing to A/B-toggle if scores look off — it
  /// nudges pixels away from the model's training distribution.
  final bool _normalizeLighting;

  /// When true, model input is standardised per-image (`(x-mean)/std`,
  /// "prewhiten") instead of `(x-127.5)/128`. Defaults to
  /// [FaceModel.wantsPrewhiten] for the chosen model.
  final bool _prewhiten;

  /// Set by [_detectAndCropFace] on every call — the detected face-box width
  /// (px) and whether the source was upscaled first. Read straight after the
  /// relevant embedding call for diagnostics; not safe across concurrent
  /// compares (there are none — calls are awaited in sequence).
  int _lastFacePx = 0;
  bool _lastReferenceUpscaled = false;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: true,
      enableTracking: true,
      enableClassification: true,
      // Matching is a one-shot, offline operation (not a live stream), so
      // the slower `accurate` model is worth it here for tighter bounding
      // boxes and steadier eye landmarks — both feed the alignment/crop
      // that the embedding is computed from.
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.03,
    ),
  );

  FaceCompare._(
    this._debug,
    this._eyeAlignment,
    this._normalizeLighting,
    this._prewhiten,
  );

  /// Factory method (async init).
  ///
  /// [model] picks the embedding network (see [FaceModel]).
  ///
  /// Set [debug] to true to save a copy of each detected/aligned face crop
  /// to the temp directory for troubleshooting. Off by default since it
  /// writes a file to disk on every call.
  ///
  /// [eyeAlignment], [normalizeLighting] and [prewhiten] toggle the Phase 3
  /// matching-accuracy steps — see the corresponding fields. [prewhiten]
  /// defaults to what [model] expects.
  static Future<FaceCompare> create({
    FaceModel model = FaceModel.mobileFaceNet,
    bool debug = false,
    bool eyeAlignment = true,
    bool normalizeLighting = true,
    bool? prewhiten,
  }) async {
    final usePrewhiten = prewhiten ?? model.wantsPrewhiten;
    debugPrint(
      '$_tag create() — loading ${model.asset}, debug=$debug, '
      'eyeAlignment=$eyeAlignment, normalizeLighting=$normalizeLighting, '
      'prewhiten=$usePrewhiten',
    );
    final helper = FaceCompare._(
      debug,
      eyeAlignment,
      normalizeLighting,
      usePrewhiten,
    );
    helper._interpreter = await Interpreter.fromAsset(model.asset);
    helper._outputShape = helper._interpreter!.getOutputTensor(0).shape;

    final inShape = helper._interpreter!.getInputTensor(0).shape;
    // NHWC [1,S,S,3] expected; guard against an NCHW [1,3,S,S] export.
    helper._inputSize = inShape.length == 4 && inShape[1] == 3
        ? inShape[2]
        : (inShape.length == 4 ? inShape[1] : 112);
    debugPrint(
      '$_tag model loaded — input shape: $inShape (inputSize=${helper._inputSize}), '
      'output shape: ${helper._outputShape}',
    );
    return helper;
  }

  /// Converts an image file into an embedding vector.
  Future<List<double>> getEmbedding(File imageFile) async {
    final cropped = await _cropOrThrow(imageFile);
    return _embedCrop(cropped);
  }

  /// Like [getEmbedding], but averages the embedding of the aligned crop with
  /// that of its horizontal mirror (test-time flip augmentation) and
  /// re-normalizes. A face is near-symmetric, so the mirror is a valid extra
  /// "view" of the same identity; averaging the two cancels some of the
  /// left/right lighting and pose asymmetry, which matters most for the
  /// low-resolution ID reference photo.
  Future<List<double>> getAugmentedEmbedding(File imageFile) async {
    final cropped = await _cropOrThrow(imageFile);
    final direct = await _embedCrop(cropped);
    final flipped = await _embedCrop(img.flipHorizontal(cropped));

    final summed = List<double>.generate(
      direct.length,
      (i) => direct[i] + flipped[i],
    );
    final averaged = _normalize(summed);
    debugPrint(
      '$_tag flip-augmented embedding: cos(direct,flipped)='
      '${cosineSimilarity(direct, flipped).toStringAsFixed(4)}',
    );
    return averaged;
  }

  /// Cosine similarity (0–1)
  double cosineSimilarity(List<double> v1, List<double> v2) {
    if (v1.length != v2.length) {
      throw ArgumentError(
        'Cannot compare embeddings of different lengths: '
        '${v1.length} vs ${v2.length}.',
      );
    }
    double dot = 0.0;
    for (int i = 0; i < v1.length; i++) {
      dot += v1[i] * v2[i];
    }
    final clamped = dot.clamp(-1.0, 1.0);
    debugPrint(
      '$_tag cosineSimilarity: raw dot=${dot.toStringAsFixed(4)} clamped=${clamped.toStringAsFixed(4)}',
    );
    return clamped;
  }

  /// Compares two faces and returns a similarity score as a percentage.
  Future<double> compare(File img1, File img2) async {
    debugPrint('$_tag ==== compare(): ${img1.path}  vs  ${img2.path} ====');

    final emb1 = await getAugmentedEmbedding(img1);
    final emb2 = await getAugmentedEmbedding(img2);

    final similarity = cosineSimilarity(emb1, emb2);
    final pct = similarity * 100;
    debugPrint('$_tag ==== similarity = ${pct.toStringAsFixed(2)}% ====');
    return pct;
  }

  /// Compares [reference] against one or more [liveFrames], averaging the
  /// live frames' (flip-augmented) embeddings into one probe before scoring.
  /// More live frames ⇒ a steadier score. Frames that yield no detectable
  /// face are skipped; if none work the last error is rethrown.
  Future<double> compareBest(File reference, List<File> liveFrames) async {
    final result = await compareDetailed(reference, liveFrames);
    return result.score;
  }

  /// Like [compareBest] but also returns the quality signals behind the
  /// score, so a caller can prompt for a better retake instead of a blunt
  /// "failed".
  Future<FaceCompareResult> compareDetailed(
    File reference,
    List<File> liveFrames,
  ) async {
    final frames = liveFrames.isEmpty ? <File>[] : liveFrames;
    if (frames.isEmpty) {
      throw ArgumentError('compareDetailed needs at least one live frame');
    }

    final refEmb = await getAugmentedEmbedding(reference);
    final referenceFacePx = _lastFacePx;
    final referenceUpscaled = _lastReferenceUpscaled;

    final probeEmbeddings = <List<double>>[];
    var probeFacePx = 0;
    Object? lastError;
    for (final frame in frames) {
      try {
        final e = await getAugmentedEmbedding(frame);
        probeEmbeddings.add(e);
        if (_lastFacePx > probeFacePx) probeFacePx = _lastFacePx;
      } catch (e) {
        debugPrint('$_tag probe frame skipped (${frame.path}): $e');
        lastError = e;
      }
    }
    if (probeEmbeddings.isEmpty) {
      throw lastError ?? Exception('No usable face in any live frame.');
    }

    final summed = List<double>.filled(refEmb.length, 0.0);
    for (final e in probeEmbeddings) {
      for (var i = 0; i < summed.length; i++) {
        summed[i] += e[i];
      }
    }
    final probeEmb = _normalize(summed);

    final pct = cosineSimilarity(refEmb, probeEmb) * 100;
    debugPrint(
      '$_tag ==== compareDetailed: score=${pct.toStringAsFixed(2)}% '
      'refFacePx=$referenceFacePx probeFacePx=$probeFacePx '
      'probeFrames=${probeEmbeddings.length}/${frames.length} '
      'refUpscaled=$referenceUpscaled ====',
    );

    return FaceCompareResult(
      score: pct,
      referenceFacePx: referenceFacePx,
      probeFacePx: probeFacePx,
      probeFramesUsed: probeEmbeddings.length,
      referenceUpscaled: referenceUpscaled,
    );
  }

  /// Checks whether two faces belong to the same person (default threshold 50%)
  Future<bool> isSamePerson(
    File img1,
    File img2, {
    double threshold = 50,
  }) async {
    final score = await compare(img1, img2);
    final result = score >= threshold;
    debugPrint(
      '$_tag isSamePerson: score=${score.toStringAsFixed(2)} threshold=$threshold -> $result',
    );
    return result;
  }

  void dispose() {
    _interpreter?.close();
    _faceDetector.close();
  }
}
