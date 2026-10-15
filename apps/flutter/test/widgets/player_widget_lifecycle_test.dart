import 'dart:async';

import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/models/playlist_model.dart';
import 'package:another_iptv_player/services/app_state.dart';
import 'package:another_iptv_player/services/service_locator.dart';
import 'package:another_iptv_player/utils/audio_handler.dart';
import 'package:another_iptv_player/widgets/player_widget.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Playlist;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _PendingPreferences extends InMemorySharedPreferencesStore {
  _PendingPreferences() : super.empty();
  final ready = Completer<Map<String, Object>>();
  @override
  Future<Map<String, Object>> getAll() => ready.future;
}

class _Player extends Fake implements Player {
  bool disposed = false;
  @override
  Future<void> dispose() async { disposed = true; }
}

class _AudioHandler extends Fake implements MyAudioHandler {
  int attachments = 0;
  @override
  void setPlayer(Player? player) { if (player != null) attachments++; }
  @override
  Future<void> stop() async {}
}

void main() {
  testWidgets('leaving during preferences load disposes safely and never resumes startup', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final previousStore = SharedPreferencesStorePlatform.instance;
    final preferences = _PendingPreferences();
    SharedPreferencesStorePlatform.instance = preferences;
    final database = AppDatabase(NativeDatabase.memory());
    final audio = _AudioHandler();
    getIt.registerSingleton<AppDatabase>(database);
    getIt.registerSingleton<MyAudioHandler>(audio);
    final previousPlaylist = AppState.currentPlaylist;
    AppState.currentPlaylist = Playlist(id: 'test', name: 'Test',
        type: PlaylistType.m3u, createdAt: DateTime(2026));
    addTearDown(() async {
      SharedPreferencesStorePlatform.instance = previousStore;
      SharedPreferences.setMockInitialValues({});
      AppState.currentPlaylist = previousPlaylist;
      await getIt.reset();
      await database.close();
    });
    final player = _Player();
    await tester.pumpWidget(MaterialApp(home: PlayerWidget(
      contentItem: ContentItem('test', 'Test', '', ContentType.vod),
      playerFactory: () => player,
    )));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
    expect(player.disposed, isTrue);
    preferences.ready.complete({});
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(audio.attachments, 0);
  });
}
