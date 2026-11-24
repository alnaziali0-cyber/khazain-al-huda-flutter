import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:khazain_al_huda/devpanel/image_to_ui/extractor.dart';

/// Builds a small RGBA buffer with two colour blocks and a white margin.
Uint8List _buildImage({
  required int width,
  required int height,
  required int blockColor,
  required int blockTop,
  required int blockHeight,
}) {
  final data = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final index = (y * width + x) * 4;
      final inBlock = y >= blockTop && y < blockTop + blockHeight;
      if (inBlock) {
        data[index] = (blockColor >> 16) & 0xFF;
        data[index + 1] = (blockColor >> 8) & 0xFF;
        data[index + 2] = blockColor & 0xFF;
      } else {
        data[index] = 0xFF;
        data[index + 1] = 0xFF;
        data[index + 2] = 0xFF;
      }
      data[index + 3] = 0xFF;
    }
  }
  return data;
}

void main() {
  const analyzer = ImageAnalyzer();

  test('the analyser finds the dominant non-neutral colour', () {
    final pixels = _buildImage(
      width: 120,
      height: 120,
      blockColor: 0x174940,
      blockTop: 30,
      blockHeight: 40,
    );

    final analysis = analyzer.analysePixels(
      pixels,
      width: 120,
      height: 120,
      existingTokens: const <String, String>{
        'green': '#174940',
        'gold': '#BC9551',
        'bgApp': '#222222',
      },
    );

    expect(analysis.clusters, isNotEmpty);
    final cluster = analysis.clusters.first;
    expect(cluster.hex, '#174940');
    expect(cluster.isNeutral, isFalse);
  });

  test('a matching colour updates the token instead of adding one', () {
    final pixels = _buildImage(
      width: 120,
      height: 120,
      blockColor: 0x174940,
      blockTop: 20,
      blockHeight: 60,
    );

    final analysis = analyzer.analysePixels(
      pixels,
      width: 120,
      height: 120,
      existingTokens: const <String, String>{'green': '#174940'},
    );

    expect(analysis.tokenMatches, isNotEmpty);
    final match = analysis.tokenMatches.first;
    expect(match.tokenName, 'green');
    expect(match.deltaE, lessThan(6));
    expect(match.isUpdate, isTrue);
    expect(analysis.newTokens, isEmpty);
  });

  test('a distant colour is reported as a new token', () {
    final pixels = _buildImage(
      width: 120,
      height: 120,
      blockColor: 0xE5484D,
      blockTop: 20,
      blockHeight: 60,
    );

    final analysis = analyzer.analysePixels(
      pixels,
      width: 120,
      height: 120,
      existingTokens: const <String, String>{'green': '#174940'},
    );

    expect(analysis.newTokens, isNotEmpty);
    expect(analysis.newTokens.first.hex, '#E5484D');
  });

  test('the grid estimate keeps four columns and a fractional gutter', () {
    final pixels = _buildImage(
      width: 200,
      height: 200,
      blockColor: 0xBC9551,
      blockTop: 40,
      blockHeight: 80,
    );

    final analysis = analyzer.analysePixels(
      pixels,
      width: 200,
      height: 200,
      existingTokens: const <String, String>{'gold': '#BC9551'},
    );

    expect(analysis.grid.columns, 4);
    expect(analysis.grid.gutter, greaterThan(0));
    expect(analysis.grid.gutter, lessThan(1));
    expect(analysis.grid.sidePadding, greaterThanOrEqualTo(0));
  });

  test('the type estimate produces the four headline steps', () {
    final pixels = _buildImage(
      width: 200,
      height: 200,
      blockColor: 0xBC9551,
      blockTop: 40,
      blockHeight: 80,
    );

    final analysis = analyzer.analysePixels(
      pixels,
      width: 200,
      height: 200,
      existingTokens: const <String, String>{'gold': '#BC9551'},
    );

    expect(analysis.typeScale.keys, containsAll(<String>['display', 'h1', 'h2', 'body']));
    expect(analysis.typeScale['body']!, greaterThanOrEqualTo(11));
    expect(analysis.typeScale['display']!,
        greaterThan(analysis.typeScale['body']!));
  });
}
