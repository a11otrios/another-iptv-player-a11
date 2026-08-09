import 'package:another_iptv_player/controllers/watch_history_controller.dart';
import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/playlist_model.dart';
import 'package:another_iptv_player/models/watch_history.dart';
import 'package:another_iptv_player/services/app_state.dart';
import 'package:another_iptv_player/services/service_locator.dart';
import 'package:another_iptv_player/services/watch_history_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reload keeps existing history mounted until replacement is ready',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      getIt.registerSingleton<AppDatabase>(database);
      AppState.currentPlaylist = Playlist(
        id: 'playlist-1',
        name: 'Playlist',
        type: PlaylistType.m3u,
        createdAt: DateTime(2026),
      );
      final controller = WatchHistoryController();
      addTearDown(() async {
        controller.dispose();
        AppState.currentPlaylist = null;
        await getIt.reset();
        await database.close();
      });

      final service = WatchHistoryService(database);
      await service.saveWatchHistory(
        WatchHistory(
          playlistId: 'playlist-1',
          contentType: ContentType.liveStream,
          streamId: 'channel-1',
          lastWatched: DateTime(2026),
          title: 'Children Channel',
        ),
      );
      await controller.loadWatchHistory();
      expect(controller.liveHistory, hasLength(1));

      await service.deleteWatchHistory('playlist-1', 'channel-1');
      final reload = controller.loadWatchHistory();

      expect(controller.liveHistory, hasLength(1));
      expect(controller.isLoading, isFalse);

      await reload;
      expect(controller.liveHistory, isEmpty);
    },
  );
}
