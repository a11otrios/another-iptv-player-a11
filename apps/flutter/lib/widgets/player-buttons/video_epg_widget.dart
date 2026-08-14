import 'dart:async';

import 'package:another_iptv_player/models/epg_program.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/services/app_state.dart';
import 'package:another_iptv_player/services/event_bus.dart';
import 'package:another_iptv_player/services/player_state.dart';
import 'package:flutter/material.dart';

/// Compact current/next programme text for the player control bar.
class VideoEpgWidget extends StatefulWidget {
  const VideoEpgWidget({super.key});

  @override
  State<VideoEpgWidget> createState() => _VideoEpgWidgetState();
}

class _VideoEpgWidgetState extends State<VideoEpgWidget> {
  StreamSubscription<ContentItem>? _contentSubscription;
  ContentItem? _content;
  Future<List<EpgProgram>?>? _future;

  @override
  void initState() {
    super.initState();
    _setContent(PlayerState.currentContent);
    _contentSubscription = EventBus()
        .on<ContentItem>('player_content_item')
        .listen(_setContent);
  }

  @override
  void dispose() {
    _contentSubscription?.cancel();
    super.dispose();
  }

  void _setContent(ContentItem? content) {
    if (_content?.id == content?.id && _future != null) return;
    _content = content;
    final streamId = content?.liveStream?.streamId;
    final repository = AppState.xtreamCodeRepository;
    _future = streamId == null || streamId.isEmpty || repository == null
        ? null
        : repository.getShortEpg(streamId, limit: 2);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_future == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<List<EpgProgram>?>(
      future: _future,
      builder: (context, snapshot) {
        final programs = snapshot.data;
        if (programs == null || programs.isEmpty) {
          return const SizedBox.shrink();
        }
        final now = programs.firstWhere(
          (program) => program.nowPlaying || program.isAiringAt(DateTime.now()),
          orElse: () => programs.first,
        );
        final laterPrograms = programs.where(
          (program) => !identical(program, now),
        );
        final next = laterPrograms.isEmpty ? null : laterPrograms.first;
        final text = [
          'Now: ${now.title}',
          if (next != null) 'Next: ${next.title}',
        ].join('  ·  ');
        return Tooltip(
          message: text,
          child: Row(
            children: [
              const Icon(Icons.schedule, color: Colors.white70, size: 17),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
