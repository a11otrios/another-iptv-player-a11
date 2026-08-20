import 'dart:async';
import 'dart:io';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/models/subtitle_search_result.dart';
import 'package:another_iptv_player/models/watch_history.dart';
import 'package:another_iptv_player/repositories/user_preferences.dart';
import 'package:another_iptv_player/services/app_state.dart';
import 'package:another_iptv_player/services/channel_shortcut_service.dart';
import 'package:another_iptv_player/services/event_bus.dart';
import 'package:another_iptv_player/services/open_subtitles_service.dart';
import 'package:another_iptv_player/services/watch_history_service.dart';
import 'package:another_iptv_player/utils/get_playlist_type.dart';
import 'package:another_iptv_player/utils/live_stream_buffering.dart';
import 'package:another_iptv_player/utils/subtitle_configuration.dart';
import 'package:another_iptv_player/utils/windows_playback_performance.dart';
import 'package:another_iptv_player/widgets/video_widget.dart';
import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import '../../models/content_type.dart';
import '../../services/player_state.dart';
import '../../services/service_locator.dart';
import '../../utils/audio_handler.dart';
import '../utils/player_error_handler.dart';

class PlayerWidget extends StatefulWidget {
  final ContentItem contentItem;
  final double? aspectRatio;
  final bool showControls;
  final bool showInfo;
  final VoidCallback? onFullscreen;
  final List<ContentItem>? queue;

  const PlayerWidget({
    super.key,
    required this.contentItem,
    this.aspectRatio,
    this.showControls = true,
    this.showInfo = false,
    this.onFullscreen,
    this.queue,
  });

  @override
  State<PlayerWidget> createState() => _PlayerWidgetState();
}

class _PlayerWidgetState extends State<PlayerWidget>
    with WidgetsBindingObserver {
  static final Map<LogicalKeyboardKey, int> _numberKeys = {
    LogicalKeyboardKey.digit0: 0,
    LogicalKeyboardKey.digit1: 1,
    LogicalKeyboardKey.digit2: 2,
    LogicalKeyboardKey.digit3: 3,
    LogicalKeyboardKey.digit4: 4,
    LogicalKeyboardKey.digit5: 5,
    LogicalKeyboardKey.digit6: 6,
    LogicalKeyboardKey.digit7: 7,
    LogicalKeyboardKey.digit8: 8,
    LogicalKeyboardKey.digit9: 9,
    LogicalKeyboardKey.numpad0: 0,
    LogicalKeyboardKey.numpad1: 1,
    LogicalKeyboardKey.numpad2: 2,
    LogicalKeyboardKey.numpad3: 3,
    LogicalKeyboardKey.numpad4: 4,
    LogicalKeyboardKey.numpad5: 5,
    LogicalKeyboardKey.numpad6: 6,
    LogicalKeyboardKey.numpad7: 7,
    LogicalKeyboardKey.numpad8: 8,
    LogicalKeyboardKey.numpad9: 9,
  };
  static final Map<LogicalKeyboardKey, String> _shortcutPageKeys = {
    LogicalKeyboardKey.keyA: 'A',
    LogicalKeyboardKey.keyS: 'S',
    LogicalKeyboardKey.keyD: 'D',
    LogicalKeyboardKey.keyF: 'F',
    LogicalKeyboardKey.keyG: 'G',
  };

  late StreamSubscription videoTrackSubscription;
  late StreamSubscription audioTrackSubscription;
  late StreamSubscription subtitleTrackSubscription;
  late StreamSubscription externalSubtitleSubscription;
  late StreamSubscription subtitleOffsetSubscription;
  late StreamSubscription contentItemIndexChangedSubscription;
  late StreamSubscription _connectivitySubscription;
  StreamSubscription<VideoParams>? _performanceVideoParamsSubscription;

  late Player _player;
  VideoController? _videoController;
  late WatchHistoryService watchHistoryService;
  final OpenSubtitlesService _openSubtitlesService = OpenSubtitlesService();
  final MyAudioHandler _audioHandler = getIt<MyAudioHandler>();
  final ChannelShortcutService _shortcutService = ChannelShortcutService();
  List<ContentItem>? _queue;
  late ContentItem contentItem;
  final PlayerErrorHandler _errorHandler = PlayerErrorHandler();

  bool isLoading = true;
  bool hasError = false;
  String errorMessage = '';
  bool _wasDisconnected = false;
  bool _isFirstCheck = true;
  int _currentItemIndex = 0;
  bool _showChannelList = false;
  Timer? _watchHistoryTimer;
  Duration? _pendingWatchDuration;
  Duration? _pendingTotalDuration;
  bool _isShortcutSwitching = false;
  String _shortcutPage = ChannelShortcutService.defaultPage;
  int? _surfacePointer;
  Offset? _surfacePointerStart;
  bool _surfaceTapEligible = false;
  DateTime? _lastSurfaceTap;
  Timer? _surfaceTapTimer;

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    contentItem = widget.contentItem;
    _queue = widget.queue;

    // --- INSERTION 1: INITIAL CONTENT SET ---
    PlayerState.currentContent = widget.contentItem;
    PlayerState.queue = _queue;
    PlayerState.currentIndex = 0;
    // ----------------------------------------

    PlayerState.title = widget.contentItem.name;
    _player = Player(configuration: PlayerConfiguration());
    watchHistoryService = WatchHistoryService();

    super.initState();
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    videoTrackSubscription = EventBus()
        .on<VideoTrack>('video_track_changed')
        .listen((VideoTrack data) async {
          _player.setVideoTrack(data);
          await UserPreferences.setVideoTrack(data.id);
        });

    audioTrackSubscription = EventBus()
        .on<AudioTrack>('audio_track_changed')
        .listen((AudioTrack data) async {
          _player.setAudioTrack(data);
          await UserPreferences.setAudioTrack(data.language ?? 'null');
        });

    subtitleTrackSubscription = EventBus()
        .on<SubtitleTrack>('subtitle_track_changed')
        .listen((SubtitleTrack data) async {
          _player.setSubtitleTrack(data);
          await UserPreferences.setSubtitleTrack(
            data.id == 'no'
                ? UserPreferences.subtitleOff
                : data.language ?? 'auto',
          );
        });

    externalSubtitleSubscription = EventBus()
        .on<CachedSubtitle>('external_subtitle_selected')
        .listen((CachedSubtitle data) async {
          await _applyExternalSubtitle(data);
        });

    subtitleOffsetSubscription = EventBus()
        .on<double>('subtitle_offset_changed')
        .listen((double data) async {
          await _setSubtitleOffset(data, persist: true);
        });

    _initializePlayer();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    // Cancel timer and save watch history one last time before disposing
    _watchHistoryTimer?.cancel();
    _surfaceTapTimer?.cancel();
    if (_pendingWatchDuration != null) {
      // Use unawaited to save without blocking dispose
      _saveWatchHistory().catchError((e) {
        // Ignore errors during dispose
      });
    }

    _performanceVideoParamsSubscription?.cancel();
    _player.dispose();
    _audioHandler.setPlayer(null);
    _audioHandler.stop();
    videoTrackSubscription.cancel();
    audioTrackSubscription.cancel();
    subtitleTrackSubscription.cancel();
    externalSubtitleSubscription.cancel();
    subtitleOffsetSubscription.cancel();
    contentItemIndexChangedSubscription.cancel();
    _connectivitySubscription.cancel();
    _errorHandler.reset();
    super.dispose();
  }

  Future<void> _saveWatchHistory() async {
    if (_pendingWatchDuration == null || !mounted) return;

    try {
      await watchHistoryService.saveWatchHistory(
        WatchHistory(
          playlistId: AppState.currentPlaylist!.id,
          contentType: contentItem.contentType,
          streamId: isXtreamCode
              ? contentItem.id
              : contentItem.m3uItem?.id ?? contentItem.id,
          lastWatched: DateTime.now(),
          title: contentItem.name,
          imagePath: contentItem.imagePath,
          totalDuration: _pendingTotalDuration,
          watchDuration: _pendingWatchDuration,
          seriesId: contentItem.seriesStream?.seriesId,
        ),
      );
      _pendingWatchDuration = null;
      _pendingTotalDuration = null;
    } catch (e) {
      // Silently handle database errors to prevent crashes
      // The next save attempt will retry
      debugPrint('Error saving watch history: $e');
    }
  }

  Future<void> _initializePlayer() async {
    if (!mounted) return;

    PlayerState.subtitleConfiguration = await getSubtitleConfiguration();

    PlayerState.backgroundPlay = await UserPreferences.getBackgroundPlay();
    _audioHandler.setPlayer(_player);
    _videoController = VideoController(_player);
    if (contentItem.contentType == ContentType.liveStream) {
      await _enableLiveStreamBuffering();
    }
    if (Platform.isWindows &&
        await UserPreferences.getWindowsPlaybackPerformanceMode()) {
      await _enableWindowsPlaybackPerformanceMode();
    }

    var watchHistory = await watchHistoryService.getWatchHistory(
      AppState.currentPlaylist!.id,
      isXtreamCode ? contentItem.id : contentItem.m3uItem?.id ?? contentItem.id,
    );

    List<MediaItem> mediaItems = [];
    var currentItemIndex = 0;
    var initialQueueIndex = 0;

    if (_queue != null) {
      for (int i = 0; i < _queue!.length; i++) {
        final item = _queue![i];
        final itemWatchHistory = await watchHistoryService.getWatchHistory(
          AppState.currentPlaylist!.id,
          isXtreamCode ? item.id : item.m3uItem?.id ?? item.id,
        );

        mediaItems.add(
          MediaItem(
            id: item.id.toString(),
            title: item.name,
            artist: _getContentTypeDisplayName(),
            album: AppState.currentPlaylist?.name ?? '',
            artUri: item.imagePath.isEmpty
                ? null
                : Uri.tryParse(item.imagePath),
            playable: true,
            extras: {
              'url': item.url,
              'startPosition':
                  itemWatchHistory?.watchDuration?.inMilliseconds ?? 0,
            },
          ),
        );

        if (item.id == contentItem.id) {
          initialQueueIndex = i;
          _currentItemIndex = i;

          if (contentItem.contentType == ContentType.liveStream) {
            currentItemIndex = 0;
            contentItem = item;

            EventBus().emit('player_content_item', item);
            EventBus().emit('player_content_item_index', i);
          } else {
            currentItemIndex = i;
          }
        }
      }

      PlayerState.currentContent = contentItem;
      PlayerState.currentIndex = _currentItemIndex;

      await _audioHandler.setQueue(mediaItems, initialIndex: initialQueueIndex);

      if (contentItem.contentType != ContentType.liveStream) {
        var playlist = mediaItems.map((mediaItem) {
          final url = mediaItem.extras!['url'] as String;
          final startMs = mediaItem.extras!['startPosition'] as int;
          return Media(url, start: Duration(milliseconds: startMs));
        }).toList();

        await _player.open(
          Playlist(playlist, index: currentItemIndex),
          play: true,
        );
      } else {
        await _player.open(Media(contentItem.url));
      }
    } else {
      final mediaItem = MediaItem(
        id: contentItem.id.toString(),
        title: contentItem.name,
        artist: _getContentTypeDisplayName(),
        artUri: contentItem.imagePath.isEmpty
            ? null
            : Uri.tryParse(contentItem.imagePath),
        extras: {
          'url': contentItem.url,
          'startPosition': watchHistory?.watchDuration?.inMilliseconds ?? 0,
        },
      );

      // if (contentItem.contentType == ContentType.liveStream) {
      //   liveStreamContentItem = contentItem;
      // }

      await _audioHandler.setQueue([mediaItem]);

      await _player.open(
        Playlist([
          Media(
            contentItem.url,
            start: watchHistory?.watchDuration ?? Duration(),
          ),
        ]),
        play: true,
      );
    }

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) async {
      bool hasConnection = results.any(
        (connectivity) =>
            connectivity == ConnectivityResult.mobile ||
            connectivity == ConnectivityResult.wifi ||
            connectivity == ConnectivityResult.ethernet,
      );

      if (_isFirstCheck) {
        final currentConnectivity = await Connectivity().checkConnectivity();
        hasConnection = currentConnectivity.any(
          (connectivity) =>
              connectivity == ConnectivityResult.mobile ||
              connectivity == ConnectivityResult.wifi ||
              connectivity == ConnectivityResult.ethernet,
        );
        _isFirstCheck = false;
      }

      if (!mounted) return;
      if (hasConnection) {
        if (_wasDisconnected &&
            contentItem.contentType == ContentType.liveStream &&
            contentItem.url.isNotEmpty) {
          try {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Online", style: TextStyle(color: Colors.white)),
                backgroundColor: Colors.green,
              ),
            );

            // TODO: Implement watch history duration for vod and series
            await _player.open(Media(contentItem.url));
          } catch (e) {
            debugPrint('Error opening media: $e');
          }
        }
        _wasDisconnected = false;
      } else {
        _wasDisconnected = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "No Connection",
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    });

    _player.stream.tracks.listen((event) async {
      if (!mounted) return;

      PlayerState.videos = event.video;
      PlayerState.audios = event.audio;
      PlayerState.subtitles = event.subtitle;

      EventBus().emit('player_tracks', event);

      await _player.setVideoTrack(
        VideoTrack(await UserPreferences.getVideoTrack(), null, null),
      );

      var selectedAudioLanguage = await UserPreferences.getAudioTrack();
      var possibleAudioTrack = event.audio.firstWhere(
        (x) => x.language == selectedAudioLanguage,
        orElse: AudioTrack.auto,
      );

      await _player.setAudioTrack(possibleAudioTrack);

      var selectedSubtitleLanguage = await UserPreferences.getSubtitleTrack();
      var possibleSubtitleLanguage =
          selectedSubtitleLanguage == UserPreferences.subtitleOff
          ? SubtitleTrack.no()
          : event.subtitle.firstWhere(
              (x) => x.language == selectedSubtitleLanguage,
              orElse: SubtitleTrack.auto,
            );

      if (!PlayerState.selectedSubtitle.uri &&
          !PlayerState.selectedSubtitle.data) {
        await _player.setSubtitleTrack(possibleSubtitleLanguage);
      }
    });

    _player.stream.track.listen((event) async {
      if (!mounted) return;

      PlayerState.selectedVideo = _player.state.track.video;
      PlayerState.selectedAudio = _player.state.track.audio;
      PlayerState.selectedSubtitle = _player.state.track.subtitle;

      // Track değişikliğini bildir
      EventBus().emit('player_track_changed', null);

      var volume = await UserPreferences.getVolume();
      await _player.setVolume(volume);
    });

    _player.stream.volume.listen((event) async {
      await UserPreferences.setVolume(event);
    });

    _player.stream.position.listen((position) {
      _player.state.playlist.medias[currentItemIndex] = Media(
        contentItem.url,
        start: position,
      );

      // Debounce: Save watch history every 5 seconds instead of on every position update
      _pendingWatchDuration = position;
      _pendingTotalDuration = _player.state.duration;

      _watchHistoryTimer?.cancel();
      _watchHistoryTimer = Timer(const Duration(seconds: 5), () {
        _saveWatchHistory();
      });
    });

    _player.stream.error.listen((error) async {
      debugPrint('PLAYER ERROR -> $error');
      if (error.contains('Failed to open')) {
        _errorHandler.handleError(
          error,
          () async {
            if (contentItem.contentType == ContentType.liveStream) {
              await _player.open(Media(contentItem.url));
            }
          },
          (errorMessage) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                duration: Duration(seconds: 3),
              ),
            );
          },
        );
      }
    });

    _player.stream.playlist.listen((playlist) {
      if (!mounted) return;

      if (contentItem.contentType == ContentType.liveStream) {
        return;
      }

      _currentItemIndex = playlist.index;
      currentItemIndex = _currentItemIndex;
      contentItem = _queue?[playlist.index] ?? widget.contentItem;

      // --- INSERTION 2: QUEUE CHANGE SETTER ---
      PlayerState.currentContent = contentItem;
      PlayerState.currentIndex = _currentItemIndex;
      // ----------------------------------------

      PlayerState.title = contentItem.name;
      EventBus().emit('player_content_item', contentItem);
      EventBus().emit('player_content_item_index', playlist.index);
      unawaited(_loadCachedSubtitleForCurrentContent());

      // Kanal listesi açıksa güncelle
      if (_showChannelList && mounted) {
        setState(() {});
      }
    });

    _player.stream.completed.listen((playlist) async {
      if (contentItem.contentType == ContentType.liveStream) {
        await _player.open(Media(contentItem.url));
      }
    });

    contentItemIndexChangedSubscription = EventBus()
        .on<int>('player_content_item_index_changed')
        .listen((int index) async {
          if (contentItem.contentType == ContentType.liveStream) {
            // Queue'yu PlayerState'ten al (kategori değiştiğinde güncellenmiş olabilir)
            final updatedQueue = PlayerState.queue ?? _queue;
            if (updatedQueue == null || index >= updatedQueue.length) return;

            final item = updatedQueue[index];
            contentItem = item;
            _queue = updatedQueue; // Queue'yu güncelle

            // --- INSERTION 3: EXTERNAL CHANGE SETTER ---
            PlayerState.currentContent = contentItem;
            PlayerState.currentIndex = index;
            PlayerState.title = item.name;
            _currentItemIndex = index;
            // -------------------------------------------

            await _player.open(Playlist([Media(item.url)]), play: true);
            EventBus().emit('player_content_item', item);
            EventBus().emit('player_content_item_index', index);
            unawaited(_loadCachedSubtitleForCurrentContent());
            _errorHandler.reset();

            // Kanal listesi açıksa güncelle
            if (_showChannelList && mounted) {
              setState(() {});
            }
          } else {
            _player.jump(index);
          }
        });

    // Kanal listesi göster/gizle event'i
    EventBus().on<bool>('toggle_channel_list').listen((bool show) {
      if (mounted) {
        setState(() {
          _showChannelList = show;
          PlayerState.showChannelList = show;
        });
      }
    });

    // Video bilgisi göster/gizle event'i
    EventBus().on<bool>('toggle_video_info').listen((bool show) {
      if (mounted) {
        setState(() {
          PlayerState.showVideoInfo = show;
        });
      }
    });

    // Video ayarları göster/gizle event'i
    EventBus().on<bool>('toggle_video_settings').listen((bool show) {
      if (mounted) {
        setState(() {
          PlayerState.showVideoSettings = show;
        });
      }
    });

    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }

    await _loadCachedSubtitleForCurrentContent();
  }

  /// Enlarge mpv's demuxer cache for live streams so high-bitrate channels do
  /// not stall when the provider connection briefly slows down. Best-effort:
  /// unsupported platforms simply keep the default buffer.
  Future<void> _enableLiveStreamBuffering() async {
    final platform = _player.platform;
    if (platform == null) return;

    // Respect a per-item User-Agent (m3u playlists can carry one); otherwise
    // fall back to a broadly whitelisted UA so providers do not throttle us.
    final itemUserAgent = contentItem.m3uItem?.userAgent;
    final userAgent = (itemUserAgent != null && itemUserAgent.isNotEmpty)
        ? itemUserAgent
        : liveStreamDefaultUserAgent;

    final properties = <String, String>{
      ...liveStreamBufferingMpvProperties,
      'user-agent': userAgent,
    };

    for (final property in properties.entries) {
      try {
        await (platform as dynamic).setProperty(property.key, property.value);
      } catch (error) {
        debugPrint(
          'Could not apply live stream buffering property '
          '${property.key}: $error',
        );
      }
    }
  }

  Future<void> _enableWindowsPlaybackPerformanceMode() async {
    final controller = _videoController;
    if (controller == null) return;

    // Wait until media-kit has attached its own video-parameter listener. Our
    // capped resize then runs after its source-resolution resize.
    try {
      await controller.platform.future;
    } catch (error) {
      debugPrint(
        'Could not initialize the Windows performance video surface: $error',
      );
      return;
    }
    if (!mounted) return;

    final platform = _player.platform;
    if (platform != null) {
      for (final property in windowsPerformanceMpvProperties.entries) {
        try {
          await (platform as dynamic).setProperty(property.key, property.value);
        } catch (error) {
          debugPrint(
            'Could not apply Windows playback performance property '
            '${property.key}: $error',
          );
        }
      }
    }

    _performanceVideoParamsSubscription = _player.stream.videoParams.listen((
      params,
    ) async {
      final size = windowsPerformanceVideoSurfaceSize(
        width: params.dw,
        height: params.dh,
        rotate: params.rotate,
      );
      if (size == null) return;
      try {
        await controller.setSize(width: size.width, height: size.height);
      } catch (error) {
        debugPrint('Could not cap Windows video surface: $error');
      }
    });
  }

  Future<void> _loadCachedSubtitleForCurrentContent() async {
    final cached = await _openSubtitlesService.cachedForContent(contentItem);
    if (cached == null) {
      PlayerState.subtitleOffsetSeconds = 0.0;
      EventBus().emit('player_track_changed', null);
      return;
    }
    await _applyExternalSubtitle(cached);
  }

  Future<void> _applyExternalSubtitle(CachedSubtitle subtitle) async {
    if (!await File(subtitle.filePath).exists()) {
      _showPlayerMessage('Subtitle file not found');
      return;
    }

    final track = SubtitleTrack.uri(
      File(subtitle.filePath).uri.toString(),
      title: subtitle.title,
      language: subtitle.language,
    );

    await _player.setSubtitleTrack(track);
    PlayerState.selectedSubtitle = track;
    if (!PlayerState.subtitles.any((item) => item.id == track.id)) {
      PlayerState.subtitles = [...PlayerState.subtitles, track];
    }
    await _setSubtitleOffset(subtitle.offsetSeconds, persist: false);
    EventBus().emit('player_track_changed', null);
    _showPlayerMessage('Subtitle loaded: ${subtitle.language}');
  }

  Future<void> _setSubtitleOffset(
    double offsetSeconds, {
    required bool persist,
  }) async {
    PlayerState.subtitleOffsetSeconds = offsetSeconds;
    try {
      await (_player.platform as dynamic).setProperty(
        'sub-delay',
        offsetSeconds.toStringAsFixed(3),
      );
    } catch (error) {
      debugPrint('Subtitle offset is not supported on this platform: $error');
    }
    if (persist) {
      await _openSubtitlesService.saveOffset(contentItem, offsetSeconds);
    }
    EventBus().emit('player_track_changed', null);
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.detached:
        await _player.dispose();
        _audioHandler.setPlayer(null);
        await _audioHandler.stop();
        break;
      default:
        break;
    }
  }

  void _changeChannel(int direction) {
    final queue = PlayerState.queue ?? _queue;
    if (queue == null || queue.length <= 1) return;

    final newIndex = (_currentItemIndex + direction) % queue.length;

    EventBus().emit('player_content_item_index_changed', newIndex);
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (!mounted ||
        event is! KeyDownEvent ||
        contentItem.contentType != ContentType.liveStream) {
      return false;
    }

    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;

    final shortcutPage = _shortcutPageKeys[event.logicalKey];
    if (shortcutPage != null) {
      _shortcutPage = shortcutPage;
      _showPlayerMessage('Shortcut page $shortcutPage');
      return true;
    }

    final channelNumber = _numberKeys[event.logicalKey];
    if (channelNumber != null) {
      unawaited(_switchToShortcut(channelNumber));
      return true;
    }

    final queue = PlayerState.queue ?? _queue;
    if (queue == null || queue.length <= 1) return false;

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _changeChannel(-1);
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _changeChannel(1);
      return true;
    }

    return false;
  }

  Future<void> _switchToShortcut(int number) async {
    if (_isShortcutSwitching) return;
    _isShortcutSwitching = true;

    try {
      final shortcut = await _shortcutService.getShortcut(
        number,
        page: _shortcutPage,
      );
      if (!mounted) return;

      if (shortcut == null) {
        _showPlayerMessage('No channel assigned to $_shortcutPage$number');
        return;
      }

      var queue = PlayerState.queue ?? _queue ?? [];
      var index = queue.indexWhere((item) => item.id == shortcut.id);

      if (index < 0) {
        queue = await _loadShortcutCategory(shortcut);
        if (!mounted) return;

        if (queue.isEmpty) {
          queue = [shortcut];
        }
        index = queue.indexWhere((item) => item.id == shortcut.id);
        if (index < 0) {
          queue = [...queue, shortcut];
          index = queue.length - 1;
        }

        _queue = queue;
        PlayerState.queue = queue;
      }

      EventBus().emit('player_content_item_index_changed', index);
      _showPlayerMessage('$_shortcutPage$number: ${shortcut.name}');
    } finally {
      _isShortcutSwitching = false;
    }
  }

  Future<List<ContentItem>> _loadShortcutCategory(ContentItem shortcut) async {
    if (isXtreamCode) {
      final categoryId = shortcut.liveStream?.categoryId;
      if (categoryId == null || categoryId.isEmpty) return [shortcut];

      final streams = await AppState.xtreamCodeRepository!
          .getLiveChannelsByCategoryId(categoryId: categoryId);
      return (streams ?? []).map((stream) {
        return ContentItem(
          stream.streamId,
          stream.name,
          stream.streamIcon,
          ContentType.liveStream,
          liveStream: stream,
        );
      }).toList();
    }

    final categoryId = shortcut.m3uItem?.categoryId;
    if (categoryId == null || categoryId.isEmpty) return [shortcut];

    final streams = await AppState.m3uRepository!.getM3uItemsByCategoryId(
      categoryId: categoryId,
    );
    return (streams ?? []).map((stream) {
      return ContentItem(
        stream.url,
        stream.name ?? 'NO NAME',
        stream.tvgLogo ?? '',
        ContentType.liveStream,
        m3uItem: stream,
      );
    }).toList();
  }

  void _showPlayerMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  void _handleSurfacePointerDown(PointerDownEvent event, double surfaceHeight) {
    const topControlsHeight = 72.0;
    const bottomControlsHeight = 104.0;
    final isPrimaryPointer = (event.buttons & kPrimaryButton) != 0;
    final isInControlRegion =
        event.localPosition.dy <= topControlsHeight ||
        event.localPosition.dy >= surfaceHeight - bottomControlsHeight;
    final hasOverlay =
        _showChannelList ||
        PlayerState.showVideoInfo ||
        PlayerState.showVideoSettings;

    _surfacePointer = event.pointer;
    _surfacePointerStart = event.localPosition;
    _surfaceTapEligible = isPrimaryPointer && !isInControlRegion && !hasOverlay;
  }

  void _handleSurfacePointerMove(PointerMoveEvent event) {
    if (event.pointer != _surfacePointer || !_surfaceTapEligible) return;
    final start = _surfacePointerStart;
    if (start != null && (event.localPosition - start).distance > 10) {
      _surfaceTapEligible = false;
    }
  }

  void _handleSurfacePointerUp(PointerUpEvent event) {
    if (event.pointer != _surfacePointer) return;
    final shouldToggle = _surfaceTapEligible;
    _resetSurfacePointer();
    if (!shouldToggle) return;

    final now = DateTime.now();
    final previousTap = _lastSurfaceTap;
    if (previousTap != null &&
        now.difference(previousTap) < const Duration(milliseconds: 400)) {
      _surfaceTapTimer?.cancel();
      _surfaceTapTimer = null;
      _lastSurfaceTap = null;
      return;
    }

    _lastSurfaceTap = now;
    _surfaceTapTimer?.cancel();
    _surfaceTapTimer = Timer(const Duration(milliseconds: 400), () {
      _lastSurfaceTap = null;
      if (mounted) {
        unawaited(_player.playOrPause());
      }
    });
  }

  void _handleSurfacePointerCancel(PointerCancelEvent event) {
    if (event.pointer == _surfacePointer) {
      _resetSurfacePointer();
    }
  }

  void _resetSurfacePointer() {
    _surfacePointer = null;
    _surfacePointerStart = null;
    _surfaceTapEligible = false;
  }

  Widget _buildChannelListOverlay(BuildContext context) {
    final items = _queue!;
    final currentContent = PlayerState.currentContent;
    final screenWidth = MediaQuery.of(context).size.width;
    final panelWidth = (screenWidth / 3).clamp(200.0, 400.0);

    // Mevcut index'i bul
    int selectedIndex = _currentItemIndex;
    if (currentContent != null) {
      final foundIndex = items.indexWhere(
        (item) => item.id == currentContent.id,
      );
      if (foundIndex != -1) {
        selectedIndex = foundIndex;
      }
    }

    String overlayTitle = 'Kanal Seç';
    if (currentContent?.contentType == ContentType.vod) {
      overlayTitle = 'Filmler';
    } else if (currentContent?.contentType == ContentType.series) {
      overlayTitle = 'Bölümler';
    }

    return Positioned.fill(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _showChannelList = false;
          });
        },
        child: Container(
          color: Colors.black.withValues(alpha: 0.3),
          child: Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {}, // Panel içine tıklanınca kapanmasın
              child: Container(
                width: panelWidth,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.95),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.grey[800]!,
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              overlayTitle,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Text(
                            '${selectedIndex + 1} / ${items.length}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[400],
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 20,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              setState(() {
                                _showChannelList = false;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    // Channel list
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final isSelected = index == selectedIndex;

                          return _buildChannelListItem(
                            context,
                            item,
                            index,
                            isSelected,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChannelListItem(
    BuildContext context,
    ContentItem item,
    int index,
    bool isSelected,
  ) {
    return InkWell(
      onTap: () {
        EventBus().emit('player_content_item_index_changed', index);
        // Panel kapanmasın, sadece kanal değişsin
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : Border.all(color: Colors.grey[800]!, width: 1),
        ),
        child: Row(
          children: [
            // Thumbnail
            if (item.imagePath.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  item.imagePath,
                  width: 50,
                  height: 35,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 50,
                      height: 35,
                      color: Colors.grey[800],
                      child: const Icon(
                        Icons.image,
                        color: Colors.grey,
                        size: 20,
                      ),
                    );
                  },
                ),
              )
            else
              Container(
                width: 50,
                height: 35,
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  Icons.video_library,
                  color: Colors.grey,
                  size: 20,
                ),
              ),
            const SizedBox(width: 10),
            // Title and info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        _getContentTypeIcon(item.contentType),
                        size: 11,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _getContentTypeDisplayNameForItem(item.contentType),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  IconData _getContentTypeIcon(ContentType contentType) {
    switch (contentType) {
      case ContentType.liveStream:
        return Icons.live_tv;
      case ContentType.vod:
        return Icons.movie;
      case ContentType.series:
        return Icons.tv;
    }
  }

  String _getContentTypeDisplayNameForItem(ContentType contentType) {
    switch (contentType) {
      case ContentType.liveStream:
        return 'Canlı Yayın';
      case ContentType.vod:
        return 'Film';
      case ContentType.series:
        return 'Dizi';
    }
  }

  String _getContentTypeDisplayName() {
    switch (widget.contentItem.contentType) {
      case ContentType.liveStream:
        return 'Canlı Yayın';
      case ContentType.vod:
        return 'Film';
      case ContentType.series:
        return 'Dizi';
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.shortestSide >= 600;
    final isLandscape = screenSize.width > screenSize.height;

    // Series ve LiveStream için tam ekran modu
    final isSeries = widget.contentItem.contentType == ContentType.series;
    final isLiveStream =
        widget.contentItem.contentType == ContentType.liveStream;
    final isVod = widget.contentItem.contentType == ContentType.vod;
    final isFullScreen = isSeries || isLiveStream || isVod;

    double calculateAspectRatio() {
      if (widget.aspectRatio != null) return widget.aspectRatio!;

      if (isTablet) {
        return isLandscape ? 21 / 9 : 16 / 9;
      }
      return 16 / 9;
    }

    double? calculateMaxHeight() {
      if (isTablet) {
        if (isLandscape) {
          return screenSize.height * 0.6;
        } else {
          return screenSize.height * 0.4;
        }
      }
      return null;
    }

    Widget playerWidget;

    if (isFullScreen) {
      // Series ve LiveStream için tam ekran
      playerWidget = SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: isLoading
            ? Container(
                color: Colors.black,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              )
            : _buildPlayerContent(),
      );
    } else {
      // Diğer içerikler için aspect ratio kullan
      playerWidget = AspectRatio(
        aspectRatio: calculateAspectRatio(),
        child: isLoading
            ? Container(
                color: Colors.black,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              )
            : _buildPlayerContent(),
      );

      if (isTablet) {
        final maxHeight = calculateMaxHeight();
        if (maxHeight != null) {
          playerWidget = ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: playerWidget,
          );
        }
      }
    }

    return Container(
      color: Colors.black,
      child: isFullScreen ? playerWidget : Column(children: [playerWidget]),
    );
  }

  Widget _buildPlayerContent() {
    if (hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 32),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                errorMessage,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final surfaceHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        return Listener(
          onPointerDown: (event) =>
              _handleSurfacePointerDown(event, surfaceHeight),
          onPointerMove: _handleSurfacePointerMove,
          onPointerUp: _handleSurfacePointerUp,
          onPointerCancel: _handleSurfacePointerCancel,
          child: GestureDetector(
            onVerticalDragEnd: (details) {
              if (_queue == null || _queue!.length <= 1) return;

              // Yukarı swipe - sonraki kanal
              if (details.primaryVelocity != null &&
                  details.primaryVelocity! < -500) {
                _changeChannel(1);
              }
              // Aşağı swipe - önceki kanal
              else if (details.primaryVelocity != null &&
                  details.primaryVelocity! > 500) {
                _changeChannel(-1);
              }
            },
            child: Stack(
              children: [
                getVideo(
                  context,
                  _videoController!,
                  PlayerState.subtitleConfiguration,
                ),

                if (widget.onFullscreen != null &&
                    (Theme.of(context).platform == TargetPlatform.macOS ||
                        Theme.of(context).platform == TargetPlatform.windows ||
                        Theme.of(context).platform == TargetPlatform.linux))
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      onPressed: widget.onFullscreen,
                      icon: const Icon(
                        Icons.fullscreen,
                        color: Colors.white,
                        size: 24,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                      ),
                    ),
                  ),

                // Kanal listesi overlay - normal mod için
                if (_showChannelList && _queue != null && _queue!.length > 1)
                  _buildChannelListOverlay(context),
              ],
            ),
          ),
        );
      },
    );
  }
}
