import 'package:another_iptv_player/models/player_aspect_ratio_mode.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit_video/media_kit_video.dart';

BoxFit playerVideoFit(PlayerAspectRatioMode mode) {
  return switch (mode) {
    PlayerAspectRatioMode.stretch => BoxFit.fill,
    PlayerAspectRatioMode.zoom => BoxFit.cover,
    _ => BoxFit.contain,
  };
}

VideoViewParameters applyPlayerAspectRatio(
  VideoViewParameters current,
  PlayerAspectRatioMode mode,
) {
  return VideoViewParameters(
    width: current.width,
    height: current.height,
    fit: playerVideoFit(mode),
    fill: current.fill,
    alignment: current.alignment,
    aspectRatio: mode.ratio,
    filterQuality: current.filterQuality,
    controls: current.controls,
    subtitleViewConfiguration: current.subtitleViewConfiguration,
    focusNode: current.focusNode,
  );
}
