import 'dart:async';

import 'package:another_iptv_player/models/player_aspect_ratio_mode.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/repositories/user_preferences.dart';
import 'package:another_iptv_player/services/app_state.dart';
import 'package:another_iptv_player/services/event_bus.dart';
import 'package:another_iptv_player/services/player_state.dart';
import 'package:another_iptv_player/utils/player_video_view_parameters.dart';
import 'package:another_iptv_player/widgets/player-buttons/back_button_widget.dart';
import 'package:another_iptv_player/widgets/player-buttons/video_aspect_ratio_widget.dart';
import 'package:another_iptv_player/widgets/player-buttons/video_channel_shortcut_widget.dart';
import 'package:another_iptv_player/widgets/player-buttons/video_channel_selector_widget.dart';
import 'package:another_iptv_player/widgets/player-buttons/video_favorite_widget.dart';
import 'package:another_iptv_player/widgets/player-buttons/video_info_widget.dart';
import 'package:another_iptv_player/widgets/player-buttons/video_epg_widget.dart';
import 'package:another_iptv_player/widgets/player-buttons/video_settings_widget.dart';
import 'package:another_iptv_player/widgets/player-buttons/video_title_widget.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

class VideoWidget extends StatefulWidget {
  final VideoController controller;
  final SubtitleViewConfiguration subtitleViewConfiguration;

  const VideoWidget({
    super.key,
    required this.controller,
    required this.subtitleViewConfiguration,
  });

  @override
  State<VideoWidget> createState() => _VideoWidgetState();
}

class _VideoWidgetState extends State<VideoWidget> {
  bool _brightnessGesture = false;
  bool _volumeGesture = false;
  bool _seekGesture = false;
  bool _speedUpOnLongPress = true;
  bool _seekOnDoubleTap = true;
  bool _isLoading = true;
  PlayerAspectRatioMode _aspectRatioMode = PlayerAspectRatioMode.original;
  final ValueNotifier<PlayerAspectRatioMode> _aspectRatioModeNotifier =
      ValueNotifier(PlayerAspectRatioMode.original);
  late final StreamSubscription<ContentItem> _contentItemSubscription;
  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();
  String? _aspectRatioStreamKey;
  int _aspectRatioLoadId = 0;

  @override
  void initState() {
    super.initState();
    _contentItemSubscription = EventBus()
        .on<ContentItem>('player_content_item')
        .listen(_handleContentItemChanged);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final initialStreamKey = _aspectRatioKeyFor(PlayerState.currentContent);
    _aspectRatioStreamKey = initialStreamKey;
    final aspectRatioLoadId = ++_aspectRatioLoadId;
    final aspectRatioFuture = initialStreamKey == null
        ? Future.value(PlayerAspectRatioMode.original)
        : UserPreferences.getPlayerAspectRatio(initialStreamKey);
    final brightnessGesture = await UserPreferences.getBrightnessGesture();
    final volumeGesture = await UserPreferences.getVolumeGesture();
    final seekGesture = await UserPreferences.getSeekGesture();
    final speedUpOnLongPress = await UserPreferences.getSpeedUpOnLongPress();
    final seekOnDoubleTap = await UserPreferences.getSeekOnDoubleTap();
    final aspectRatioMode = await aspectRatioFuture;
    if (mounted) {
      var aspectRatioWasLoaded = false;
      setState(() {
        _brightnessGesture = brightnessGesture;
        _volumeGesture = volumeGesture;
        _seekGesture = seekGesture;
        _speedUpOnLongPress = speedUpOnLongPress;
        _seekOnDoubleTap = seekOnDoubleTap;
        if (aspectRatioLoadId == _aspectRatioLoadId) {
          _aspectRatioMode = aspectRatioMode;
          aspectRatioWasLoaded = true;
        }
        _isLoading = false;
      });
      if (aspectRatioWasLoaded) {
        _aspectRatioModeNotifier.value = aspectRatioMode;
      }
      _applyAspectRatioToVideo();
    }
  }

  @override
  void dispose() {
    _contentItemSubscription.cancel();
    _aspectRatioModeNotifier.dispose();
    super.dispose();
  }

  String? _aspectRatioKeyFor(ContentItem? item) {
    final playlistId = AppState.currentPlaylist?.id;
    if (playlistId == null || item == null) return null;

    final streamId = item.m3uItem?.id ?? item.id;
    return '$playlistId\u0000${item.contentType.name}\u0000$streamId';
  }

  void _handleContentItemChanged(ContentItem item) {
    if (!mounted) return;
    final streamKey = _aspectRatioKeyFor(item);
    if (streamKey == null || streamKey == _aspectRatioStreamKey) return;

    _aspectRatioStreamKey = streamKey;
    final loadId = ++_aspectRatioLoadId;
    setState(() {
      _aspectRatioMode = PlayerAspectRatioMode.original;
    });
    _aspectRatioModeNotifier.value = PlayerAspectRatioMode.original;
    _applyAspectRatioToVideo();
    unawaited(_loadAspectRatio(streamKey, loadId));
  }

  Future<void> _loadAspectRatio(String streamKey, int loadId) async {
    final mode = await UserPreferences.getPlayerAspectRatio(streamKey);
    if (!mounted ||
        streamKey != _aspectRatioStreamKey ||
        loadId != _aspectRatioLoadId) {
      return;
    }
    setState(() {
      _aspectRatioMode = mode;
    });
    _aspectRatioModeNotifier.value = mode;
    _applyAspectRatioToVideo();
  }

  void _applyAspectRatioToVideo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final videoState = _videoKey.currentState;
      if (videoState == null) return;

      final current = videoState.videoViewParametersNotifier.value;
      final updated = applyPlayerAspectRatio(current, _aspectRatioMode);
      if (updated != current) {
        videoState.videoViewParametersNotifier.value = updated;
      }
    });
  }

  void _setAspectRatio(PlayerAspectRatioMode mode) {
    if (_aspectRatioMode == mode) return;
    _aspectRatioLoadId++;
    setState(() {
      _aspectRatioMode = mode;
    });
    _aspectRatioModeNotifier.value = mode;
    _applyAspectRatioToVideo();
    final streamKey = _aspectRatioStreamKey;
    if (streamKey != null) {
      unawaited(UserPreferences.setPlayerAspectRatio(streamKey, mode));
    }
  }

  Widget _buildAspectRatioButton() {
    return VideoAspectRatioWidget(
      selectedModeListenable: _aspectRatioModeNotifier,
      onChanged: _setAspectRatio,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    switch (Theme.of(context).platform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return MaterialVideoControlsTheme(
          normal: MaterialVideoControlsThemeData().copyWith(
            brightnessGesture: _brightnessGesture,
            volumeGesture: _volumeGesture,
            seekGesture: _seekGesture,
            speedUpOnLongPress: _speedUpOnLongPress,
            seekOnDoubleTap: _seekOnDoubleTap,
            topButtonBar: [
              BackButtonWidget(),
              Expanded(child: VideoTitleWidget()),
              VideoInfoWidget(),
              VideoChannelSelectorWidget(
                queue: PlayerState.queue,
                currentIndex: PlayerState.currentIndex,
              ),
              VideoChannelShortcutWidget(),
              VideoFavoriteWidget(),
              _buildAspectRatioButton(),
              VideoSettingsWidget(),
            ],
            bottomButtonBar: const [MaterialPositionIndicator()],
          ),
          fullscreen: MaterialVideoControlsThemeData().copyWith(
            brightnessGesture: _brightnessGesture,
            volumeGesture: _volumeGesture,
            seekGesture: _seekGesture,
            speedUpOnLongPress: _speedUpOnLongPress,
            seekOnDoubleTap: _seekOnDoubleTap,
            topButtonBar: [
              BackButtonWidget(),
              Expanded(child: VideoTitleWidget()),
              VideoInfoWidget(),
              VideoChannelSelectorWidget(
                queue: PlayerState.queue,
                currentIndex: PlayerState.currentIndex,
              ),
              VideoChannelShortcutWidget(),
              VideoFavoriteWidget(),
              _buildAspectRatioButton(),
              VideoSettingsWidget(),
            ],
            seekBarMargin: EdgeInsets.fromLTRB(0, 0, 0, 10),
          ),
          child: Scaffold(
            body: Video(
              key: _videoKey,
              controller: widget.controller,
              resumeUponEnteringForegroundMode: true,
              pauseUponEnteringBackgroundMode: !PlayerState.backgroundPlay,
              subtitleViewConfiguration: widget.subtitleViewConfiguration,
              fit: playerVideoFit(_aspectRatioMode),
              aspectRatio: _aspectRatioMode.ratio,
            ),
          ),
        );
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return MaterialDesktopVideoControlsTheme(
          normal: MaterialDesktopVideoControlsThemeData().copyWith(
            modifyVolumeOnScroll: false,
            toggleFullscreenOnDoublePress: true,
            playAndPauseOnTap: false,
            topButtonBar: [
              BackButtonWidget(),
              Expanded(child: VideoTitleWidget()),
              VideoInfoWidget(),
              VideoChannelSelectorWidget(
                queue: PlayerState.queue,
                currentIndex: PlayerState.currentIndex,
              ),
              VideoChannelShortcutWidget(),
              VideoFavoriteWidget(),
              _buildAspectRatioButton(),
              VideoSettingsWidget(),
            ],
            bottomButtonBar: const [
              MaterialDesktopSkipPreviousButton(),
              MaterialDesktopPlayOrPauseButton(),
              MaterialDesktopSkipNextButton(),
              MaterialDesktopVolumeButton(),
              MaterialDesktopPositionIndicator(),
              Expanded(child: VideoEpgWidget()),
              MaterialDesktopFullscreenButton(),
            ],
          ),
          fullscreen: MaterialDesktopVideoControlsThemeData().copyWith(
            modifyVolumeOnScroll: false,
            toggleFullscreenOnDoublePress: true,
            playAndPauseOnTap: false,
            topButtonBar: [
              BackButtonWidget(),
              Expanded(child: VideoTitleWidget()),
              VideoInfoWidget(),
              VideoChannelSelectorWidget(
                queue: PlayerState.queue,
                currentIndex: PlayerState.currentIndex,
              ),
              VideoChannelShortcutWidget(),
              VideoFavoriteWidget(),
              _buildAspectRatioButton(),
              VideoSettingsWidget(),
            ],
            bottomButtonBar: const [
              MaterialDesktopSkipPreviousButton(),
              MaterialDesktopPlayOrPauseButton(),
              MaterialDesktopSkipNextButton(),
              MaterialDesktopVolumeButton(),
              MaterialDesktopPositionIndicator(),
              Expanded(child: VideoEpgWidget()),
              MaterialDesktopFullscreenButton(),
            ],
          ),
          child: Scaffold(
            body: Video(
              key: _videoKey,
              controller: widget.controller,
              resumeUponEnteringForegroundMode: true,
              pauseUponEnteringBackgroundMode: !PlayerState.backgroundPlay,
              subtitleViewConfiguration: widget.subtitleViewConfiguration,
              fit: playerVideoFit(_aspectRatioMode),
              aspectRatio: _aspectRatioMode.ratio,
            ),
          ),
        );
      default:
        return Video(
          key: _videoKey,
          controller: widget.controller,
          controls: NoVideoControls,
          resumeUponEnteringForegroundMode: true,
          pauseUponEnteringBackgroundMode: !PlayerState.backgroundPlay,
          subtitleViewConfiguration: widget.subtitleViewConfiguration,
          fit: playerVideoFit(_aspectRatioMode),
          aspectRatio: _aspectRatioMode.ratio,
        );
    }
  }
}

// Backward compatibility wrapper
Widget getVideo(
  BuildContext context,
  VideoController controller,
  SubtitleViewConfiguration subtitleViewConfiguration,
) {
  return VideoWidget(
    controller: controller,
    subtitleViewConfiguration: subtitleViewConfiguration,
  );
}
