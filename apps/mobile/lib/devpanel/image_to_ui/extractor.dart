import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// The result of analysing a reference image.
class ImageAnalysis {
  const ImageAnalysis({
    required this.clusters,
    required this.tokenMatches,
    required this.newTokens,
    required this.typeScale,
    required this.grid,
    required this.radius,
    required this.imageWidth,
    required this.imageHeight,
  });

  /// Dominant colours found in the image (greys and whites excluded).
  final List<Cluster> clusters;

  /// For each cluster, the nearest existing token and its ΔE distance.
  final List<TokenMatch> tokenMatches;

  /// Cluster colours that are too far from every existing token.
  final List<Cluster> newTokens;

  /// Estimated type scale, keyed by the token name.
  final Map<String, double> typeScale;

  /// Estimated grid geometry.
  final GridEstimate grid;

  /// Estimated corner radius in logical pixels.
  final double radius;

  final int imageWidth;
  final int imageHeight;
}

/// A colour cluster.
class Cluster {
  const Cluster({
    required this.r,
    required this.g,
    required this.b,
    required this.weight,
  });

  final int r;
  final int g;
  final int b;

  /// Share of the analysed pixels, 0..1.
  final double weight;

  String get hex =>
      '#${r.toRadixString(16).padLeft(2, '0')}'
          '${g.toRadixString(16).padLeft(2, '0')}'
          '${b.toRadixString(16).padLeft(2, '0')}'
          .toUpperCase();

  /// Relative luminance.
  double get luminance {
    double channel(double value) {
      final normalised = value / 255;
      return normalised <= 0.03928
          ? normalised / 12.92
          : math.pow((normalised + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel(r.toDouble()) +
        0.7152 * channel(g.toDouble()) +
        0.0722 * channel(b.toDouble());
  }

  bool get isNeutral {
    final max = math.max(r, math.max(g, b)).toDouble();
    final min = math.min(r, math.min(g, b)).toDouble();
    if (max == 0) return true;
    return (max - min) / max < 0.12;
  }
}

/// A cluster matched to the nearest existing token.
class TokenMatch {
  const TokenMatch({
    required this.cluster,
    required this.tokenName,
    required this.deltaE,
    required this.currentHex,
  });

  final Cluster cluster;
  final String tokenName;

  /// CIE76 colour difference in Lab space.
  final double deltaE;

  final String currentHex;

  /// A difference below 6 means "update the token" rather than "add a new one".
  bool get isUpdate => deltaE < 6;
}

/// The estimated grid geometry of a reference image.
class GridEstimate {
  const GridEstimate({
    required this.columns,
    required this.gutter,
    required this.sidePadding,
    required this.tileAspect,
  });

  final int columns;
  final double gutter;
  final double sidePadding;
  final double tileAspect;

  static const GridEstimate unknown = GridEstimate(
    columns: 4,
    gutter: 0.35,
    sidePadding: 16,
    tileAspect: 1,
  );
}

/// Local image analysis used by the Image→UI engine.
///
/// Scope (honest): the in-app pipeline performs colour clustering, a
/// type-scale estimate, a gutter/column estimate and nearest-token matching.
/// It never generates source code — that remains the job of the optional
/// external CLI (`tools/image-to-ui`) which emits the same `UIPatch`.
class ImageAnalyzer {
  const ImageAnalyzer();

  /// Analyses raw RGBA pixels of [width]×[height].
  ImageAnalysis analysePixels(
    Uint8List rgba, {
    required int width,
    required int height,
    required Map<String, String> existingTokens,
    int maxSampleWidth = 160,
    int clusters = 6,
  }) {
    final scale = width > maxSampleWidth ? maxSampleWidth / width : 1.0;
    final sampleWidth = math.max(1, (width * scale).floor());
    final sampleHeight = math.max(1, (height * scale).floor());

    final pixels = <_Sample>[];
    final rowInk = List<double>.filled(sampleHeight, 0);
    final columnInk = List<double>.filled(sampleWidth, 0);

    for (var y = 0; y < sampleHeight; y++) {
      final sourceY = (y / scale).floor();
      for (var x = 0; x < sampleWidth; x++) {
        final sourceX = (x / scale).floor();
        final index = ((sourceY * width) + sourceX) * 4;
        if (index + 3 >= rgba.length) continue;
        final r = rgba[index];
        final g = rgba[index + 1];
        final b = rgba[index + 2];
        final a = rgba[index + 3];
        if (a < 32) continue;

        final sample = _Sample(r, g, b);
        // Ink density per row and column drives the type and grid estimates.
        final luma = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
        final isBackground = luma > 0.82 || luma < 0.08;
        if (!isBackground) {
          rowInk[y] += 1;
          columnInk[x] += 1;
        }
        // Greys and whites are excluded from the colour clustering.
        final cluster = Cluster(r: r, g: g, b: b, weight: 0);
        if (!cluster.isNeutral && luma > 0.08 && luma <= 0.82) {
          pixels.add(sample);
        }
      }
    }

    final found = _kMeans(pixels, clusters);
    final matches = <TokenMatch>[];
    final newTokens = <Cluster>[];
    for (final cluster in found) {
      final nearest = _nearestToken(cluster, existingTokens);
      if (nearest == null || nearest.$2 >= 6) {
        // ΔE ≥ 6 means the colour is too far from every existing token, so
        // the token set grows instead of being rewritten.
        newTokens.add(cluster);
        continue;
      }
      matches.add(TokenMatch(
        cluster: cluster,
        tokenName: nearest.$1,
        deltaE: nearest.$2,
        currentHex: existingTokens[nearest.$1] ?? '#000000',
      ));
    }

    final typeScale = _estimateTypeScale(rowInk, sampleHeight);
    final grid = _estimateGrid(columnInk, sampleWidth);
    final radius = _estimateRadius(clusterLuma(found));

    return ImageAnalysis(
      clusters: found,
      tokenMatches: matches,
      newTokens: newTokens,
      typeScale: typeScale,
      grid: grid,
      radius: radius,
      imageWidth: width,
      imageHeight: height,
    );
  }

  /// Decodes an encoded image and analyses it.
  Future<ImageAnalysis> analyseFile(
    Uint8List bytes, {
    required Map<String, String> existingTokens,
  }) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      throw const FormatException('تعذر فك ترميز الصورة.');
    }
    final result = analysePixels(
      data.buffer.asUint8List(),
      width: image.width,
      height: image.height,
      existingTokens: existingTokens,
    );
    image.dispose();
    codec.dispose();
    return result;
  }

  List<Cluster> _kMeans(List<_Sample> samples, int k) {
    if (samples.isEmpty) return const <Cluster>[];
    final effective = math.min(k, samples.length);
    final random = math.Random(7);
    final centroids = <_Sample>[
      for (var index = 0; index < effective; index++)
        samples[random.nextInt(samples.length)],
    ];

    for (var iteration = 0; iteration < 12; iteration++) {
      final buckets = List.generate(effective, (_) => <_Sample>[]);
      for (final sample in samples) {
        var best = 0;
        var bestDistance = double.infinity;
        for (var index = 0; index < centroids.length; index++) {
          final distance = sample.distanceTo(centroids[index]);
          if (distance < bestDistance) {
            bestDistance = distance;
            best = index;
          }
        }
        buckets[best].add(sample);
      }
      for (var index = 0; index < centroids.length; index++) {
        if (buckets[index].isEmpty) continue;
        var r = 0, g = 0, b = 0;
        for (final sample in buckets[index]) {
          r += sample.r;
          g += sample.g;
          b += sample.b;
        }
        final count = buckets[index].length;
        centroids[index] =
            _Sample(r ~/ count, g ~/ count, b ~/ count);
      }
    }

    final counts = List<int>.filled(centroids.length, 0);
    for (final sample in samples) {
      var best = 0;
      var bestDistance = double.infinity;
      for (var index = 0; index < centroids.length; index++) {
        final distance = sample.distanceTo(centroids[index]);
        if (distance < bestDistance) {
          bestDistance = distance;
          best = index;
        }
      }
      counts[best]++;
    }

    final result = <Cluster>[];
    for (var index = 0; index < centroids.length; index++) {
      if (counts[index] == 0) continue;
      result.add(Cluster(
        r: centroids[index].r,
        g: centroids[index].g,
        b: centroids[index].b,
        weight: counts[index] / samples.length,
      ));
    }
    result.sort((a, b) => b.weight.compareTo(a.weight));
    return result;
  }

  (String, double)? _nearestToken(Cluster cluster, Map<String, String> tokens) {
    var bestName = '';
    var bestDelta = double.infinity;
    final lab = _toLab(cluster.r, cluster.g, cluster.b);
    tokens.forEach((name, hex) {
      final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
      if (value == null) return;
      final tokenLab = _toLab((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF);
      final delta = _deltaE(lab, tokenLab);
      if (delta < bestDelta) {
        bestDelta = delta;
        bestName = name;
      }
    });
    if (bestName.isEmpty) return null;
    return (bestName, bestDelta);
  }

  Map<String, double> _estimateTypeScale(
      List<double> rowInk, int sampleHeight) {
    // Contiguous bands of ink approximate the cap height of the headings.
    final bands = <int>[];
    var current = 0;
    for (var index = 0; index < rowInk.length; index++) {
      final threshold = sampleHeight * 0.012;
      if (rowInk[index] > threshold) {
        current++;
      } else {
        if (current > 0) bands.add(current);
        current = 0;
      }
    }
    if (current > 0) bands.add(current);
    if (bands.isEmpty) return const <String, double>{};

    bands.sort();
    final median = bands[bands.length ~/ 2];
    // The band height is a fraction of the em size; headings are roughly
    // 1.7× the body band.
    final bodySize = (median * 2.6).clamp(11.0, 20.0);
    return <String, double>{
      'display': (bodySize * 1.7).clamp(18.0, 34.0),
      'h1': (bodySize * 1.45).clamp(16.0, 28.0),
      'h2': (bodySize * 1.2).clamp(14.0, 22.0),
      'body': bodySize,
    };
  }

  GridEstimate _estimateGrid(List<double> columnInk, int sampleWidth) {
    if (columnInk.isEmpty) return GridEstimate.unknown;
    final threshold = sampleWidth * 0.004;
    final gaps = <int>[];
    var run = 0;
    for (var index = 0; index < columnInk.length; index++) {
      if (columnInk[index] <= threshold) {
        run++;
      } else {
        if (run > 0) gaps.add(run);
        run = 0;
      }
    }
    if (run > 0) gaps.add(run);
    if (gaps.isEmpty) return GridEstimate.unknown;

    gaps.sort();
    final medianGap = gaps[gaps.length ~/ 2];
    if (medianGap <= 0) return GridEstimate.unknown;
    // A gutter is about a third of a tile; four tiles plus three gutters fill
    // the width, so the tile is width / (columns + (columns - 1) * ratio).
    final columns = 4;
    final ratio = 0.35;
    final tile = sampleWidth / (columns + (columns - 1) * ratio);
    final estimatedGutter = tile * ratio;
    final sidePadding = (sampleWidth - (columns * tile) - ((columns - 1) * estimatedGutter)) / 2;
    return GridEstimate(
      columns: columns,
      gutter: ratio,
      sidePadding: sidePadding.clamp(0, sampleWidth / 3),
      tileAspect: tile <= 0 ? 1 : 1,
    );
  }

  double _estimateRadius(double averageLuma) {
    // A bright image tends to come from a light surface with a large radius.
    return (averageLuma * 28).clamp(8, 28);
  }

  static double clusterLuma(List<Cluster> clusters) {
    if (clusters.isEmpty) return 0.5;
    var sum = 0.0;
    for (final cluster in clusters) {
      sum += cluster.luminance;
    }
    return sum / clusters.length;
  }

  static List<double> _toLab(int r, int g, int b) {
    double channel(double value) {
      final normalised = value / 255;
      return normalised <= 0.04045
          ? normalised / 12.92
          : math.pow((normalised + 0.055) / 1.055, 2.4).toDouble();
    }

    final rl = channel(r.toDouble());
    final gl = channel(g.toDouble());
    final bl = channel(b.toDouble());

    final x = (rl * 0.4124 + gl * 0.3576 + bl * 0.1805) / 0.95047;
    final y = (rl * 0.2126 + gl * 0.7152 + bl * 0.0722);
    final z = (rl * 0.0193 + gl * 0.1192 + bl * 0.9505) / 1.08883;

    double f(double t) =>
        t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : (7.787 * t) + (16 / 116);

    final fx = f(x);
    final fy = f(y);
    final fz = f(z);
    return <double>[116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
  }

  static double _deltaE(List<double> a, List<double> b) {
    final dl = a[0] - b[0];
    final da = a[1] - b[1];
    final db = a[2] - b[2];
    return math.sqrt(dl * dl + da * da + db * db);
  }
}

class _Sample {
  const _Sample(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;

  double distanceTo(_Sample other) {
    final dr = (r - other.r).toDouble();
    final dg = (g - other.g).toDouble();
    final db = (b - other.b).toDouble();
    return dr * dr + dg * dg + db * db;
  }
}
