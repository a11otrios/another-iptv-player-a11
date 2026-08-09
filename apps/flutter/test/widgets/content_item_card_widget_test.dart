import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/models/playlist_model.dart';
import 'package:another_iptv_player/services/app_state.dart';
import 'package:another_iptv_player/services/service_locator.dart';
import 'package:another_iptv_player/widgets/content_card.dart';
import 'package:another_iptv_player/widgets/content_item_card_widget.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reordering content retains the matching card state', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    getIt.registerSingleton<AppDatabase>(database);
    AppState.currentPlaylist = Playlist(
      id: 'playlist-1',
      name: 'Playlist',
      type: PlaylistType.m3u,
      createdAt: DateTime(2026),
    );
    addTearDown(() async {
      AppState.currentPlaylist = null;
      await getIt.reset();
      await database.close();
    });

    final first = ContentItem(
      'channel-1',
      'First channel',
      'https://example.invalid/channel-1.png',
      ContentType.liveStream,
    );
    final second = ContentItem(
      'channel-2',
      'Second channel',
      '',
      ContentType.liveStream,
    );
    var items = [first, second];
    late StateSetter rebuildHost;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuildHost = setState;
              return ContentItemCardWidget(
                cardHeight: 220,
                cardWidth: 150,
                contentItems: items,
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    final firstCardFinder = find.descendant(
      of: find.byKey(const ValueKey('content-liveStream-channel-1')),
      matching: find.byType(ContentCard),
    );
    final firstState = tester.state(firstCardFinder);
    final image = tester.widget<CachedNetworkImage>(
      find.descendant(
        of: firstCardFinder,
        matching: find.byType(CachedNetworkImage),
      ),
    );
    expect(image.cacheKey, 'playlist-1:liveStream:channel-1');
    expect(image.useOldImageOnUrlChange, isTrue);

    rebuildHost(() => items = [second, first]);
    await tester.pump();

    expect(tester.state(firstCardFinder), same(firstState));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
