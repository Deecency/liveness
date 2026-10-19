part of 'face_compare.dart';

/// Preprocessing + model inference: turns an aligned face crop into an
/// L2-normalized embedding vector.
extension _FaceCompareEmbed on FaceCompare {
  /// Runs the model on one already-aligned face crop and returns the
  /// L2-normalized embedding.
  Future<List<double>> _embedCrop(img.Image cropped) async {
    final s = _inputSize;
    var resized = cropped.width == s && cropped.height == s
        ? cropped
        : img.copyResize(cropped, width: s, height: s);

    if (_normalizeLighting) {
      resized = _stretchContrast(resized);
    }

    // Gather pixels first so prewhiten can use the crop's own mean/std.
    final r = Float64List(s * s);
    final g = Float64List(s * s);
    final b = Float64List(s * s);
    for (var y = 0; y < s; y++) {
      for (var x = 0; x < s; x++) {
        final pixel = resized.getPixel(x, y);
        final i = y * s + x;
        r[i] = pixel.r.toDouble();
        g[i] = pixel.g.toDouble();
        b[i] = pixel.b.toDouble();
      }
    }

    double scale;
    double meanShift;
    if (_prewhiten) {
      final count = r.length * 3;
      var sum = 0.0;
      for (var i = 0; i < r.length; i++) {
        sum += r[i] + g[i] + b[i];
      }
      final mean = sum / count;
      var sq = 0.0;
      for (var i = 0; i < r.length; i++) {
        sq += math.pow(r[i] - mean, 2) +
            math.pow(g[i] - mean, 2) +
            math.pow(b[i] - mean, 2);
      }
      final std = math.max(math.sqrt(sq / count), 1.0 / math.sqrt(count));
      meanShift = mean;
      scale = std;
    } else {
      meanShift = 127.5;
      scale = 128.0;
    }

    final input = List.generate(
      1,
      (_) => List.generate(
        s,
        (_) => List.generate(s, (_) => List.filled(3, 0.0)),
      ),
    );
    for (var y = 0; y < s; y++) {
      for (var x = 0; x < s; x++) {
        final i = y * s + x;
        input[0][y][x][0] = (r[i] - meanShift) / scale;
        input[0][y][x][1] = (g[i] - meanShift) / scale;
        input[0][y][x][2] = (b[i] - meanShift) / scale;
      }
    }

    var output = List.generate(
      _outputShape[0],
      (_) => List.filled(_outputShape[1], 0.0),
    );

    final inferStopwatch = Stopwatch()..start();
    _interpreter!.run(input, output);
    inferStopwatch.stop();
    debugPrint('$_tag inference took ${inferStopwatch.elapsedMilliseconds}ms');

    final raw = List<double>.from(output[0]);
    final rawNorm = math.sqrt(raw.fold(0.0, (sum, v) => sum + v * v));
    debugPrint(
      '$_tag raw embedding: len=${raw.length} norm=${rawNorm.toStringAsFixed(4)} '
      'min=${raw.reduce(math.min).toStringAsFixed(4)} max=${raw.reduce(math.max).toStringAsFixed(4)}',
    );

    final normalized = _normalize(raw);
    final normCheck = math.sqrt(normalized.fold(0.0, (sum, v) => sum + v * v));
    debugPrint(
      '$_tag normalized embedding norm: ${normCheck.toStringAsFixed(4)} (should be ~1.0)',
    );

    return normalized;
  }

  /// L2 normalization
  List<double> _normalize(List<double> vector) {
    final norm = math.sqrt(vector.fold(0.0, (sum, v) => sum + v * v));
    return vector.map((v) => v / norm).toList();
  }

  /// Mild per-channel contrast stretch: maps the 2nd→98th percentile of each
  /// channel onto 0→255, so a flat ID photo and a differently-exposed selfie
  /// land in a comparable range before embedding.
  img.Image _stretchContrast(img.Image src) {
    final n = src.width * src.height;
    if (n == 0) return src;

    List<int> percentiles(int channel) {
      final hist = List<int>.filled(256, 0);
      for (var y = 0; y < src.height; y++) {
        for (var x = 0; x < src.width; x++) {
          final p = src.getPixel(x, y);
          final v = (channel == 0 ? p.r : (channel == 1 ? p.g : p.b))
              .round()
              .clamp(0, 255);
          hist[v]++;
        }
      }
      final loCount = (n * 0.02).round();
      final hiCount = (n * 0.98).round();
      var acc = 0;
      var lo = 0, hi = 255;
      for (var v = 0; v < 256; v++) {
        acc += hist[v];
        if (acc <= loCount) lo = v;
        if (acc <= hiCount) hi = v;
      }
      if (hi - lo < 8) {
        lo = 0;
        hi = 255;
      }
      return [lo, hi];
    }

    final rp = percentiles(0), gp = percentiles(1), bp = percentiles(2);
    final out = img.Image(width: src.width, height: src.height, numChannels: 3);
    int map(num v, int lo, int hi) =>
        ((v - lo) * 255 / (hi - lo)).round().clamp(0, 255);
    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        out.setPixelRgb(
          x,
          y,
          map(p.r, rp[0], rp[1]),
          map(p.g, gp[0], gp[1]),
          map(p.b, bp[0], bp[1]),
        );
      }
    }
    return out;
  }
}
