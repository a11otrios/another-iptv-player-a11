import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/live_stream.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/models/playlist_model.dart';
import 'package:another_iptv_player/services/app_state.dart';
import 'package:another_iptv_player/services/channel_shortcut_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.currentPlaylist = Playlist(
      id: 'playlist-1',
      name: 'Playlist',
      type: PlaylistType.xtream,
      createdAt: DateTime(2026, 8),
    );
  });

  tearDown(() {
    AppState.currentPlaylist = null;
  });

  test(
    'stores shortcut pages independently while keeping A as default',
    () async {
      final service = ChannelShortcutService();
      final aChannel = _liveChannel('a');
      final sChannel = _liveChannel('s');

      await service.assignShortcut(1, aChannel);
      await service.assignShortcut(1, sChannel, page: 'S');

      expect((await service.getShortcut(1))?.id, 'a');
      expect((await service.getShortcut(1, page: 'A'))?.id, 'a');
      expect((await service.getShortcut(1, page: 'S'))?.id, 's');
      expect(await service.getShortcut(1, page: 'D'), isNull);
    },
  );
}

ContentItem _liveChannel(String id) {
  final stream = LiveStream(
    streamId: id,
    name: 'Channel $id',
    streamIcon: '',
    categoryId: 'category',
    epgChannelId: '',
    playlistId: 'playlist-1',
  );
  return ContentItem(
    id,
    'Channel $id',
    '',
    ContentType.liveStream,
    liveStream: stream,
  );
}
