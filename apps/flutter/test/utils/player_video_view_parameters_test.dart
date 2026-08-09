import 'package:another_iptv_player/models/player_aspect_ratio_mode.dart';
import 'package:another_iptv_player/utils/player_video_view_parameters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  VideoViewParameters parameters({
    double? aspectRatio,
    BoxFit fit = BoxFit.contain,
  }) {
    return VideoViewParameters(
      width: null,
      height: null,
      fit: fit,
      fill: Colors.black,
      alignment: Alignment.center,
      aspectRatio: aspectRatio,
      filterQuality: FilterQuality.low,
      controls: null,
      subtitleViewConfiguration: const SubtitleViewConfiguration(),
    );
  }

  test('Original clears a previously forced aspect ratio', () {
    final updated = applyPlayerAspectRatio(
      parameters(aspectRatio: 4 / 3),
      PlayerAspectRatioMode.original,
    );

    expect(updated.aspectRatio, isNull);
    expect(updated.fit, BoxFit.contain);
  });

  test('forced aspect ratios and viewport fits are applied', () {
    final widescreen = applyPlayerAspectRatio(
      parameters(),
      PlayerAspectRatioMode.ratio16x9,
    );
    final stretched = applyPlayerAspectRatio(
      parameters(aspectRatio: 16 / 9),
      PlayerAspectRatioMode.stretch,
    );
    final zoomed = applyPlayerAspectRatio(
      parameters(),
      PlayerAspectRatioMode.zoom,
    );

    expect(widescreen.aspectRatio, closeTo(16 / 9, 0.0001));
    expect(widescreen.fit, BoxFit.contain);
    expect(stretched.aspectRatio, isNull);
    expect(stretched.fit, BoxFit.fill);
    expect(zoomed.aspectRatio, isNull);
    expect(zoomed.fit, BoxFit.cover);
  });
}
