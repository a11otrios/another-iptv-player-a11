import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/models/category.dart';
import 'package:another_iptv_player/models/category_type.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/m3u_item.dart';
import 'package:another_iptv_player/models/m3u_series.dart';
import 'package:another_iptv_player/models/watch_history.dart';
import 'package:another_iptv_player/services/watch_history_service.dart';
import 'package:another_iptv_player/models/playlist_model.dart';
import 'package:another_iptv_player/repositories/user_preferences.dart';
import 'package:another_iptv_player/services/lan_server/lan_library_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('M3U series have independent resume keys and preserve legacy history', () async {
    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.insertPlaylist(Playlist(id: 'm3u', name: 'Library',
        type: PlaylistType.m3u, createdAt: DateTime(2026)));
    for (final id in ['show:a', 'show:b']) {
      await database.insertM3uSeries([M3uSerie(playlistId: 'm3u', seriesId: id, name: id).toCompanion()]);
      await database.insertM3uEpisodes([M3uEpisode(playlistId: 'm3u', seriesId: id,
          seasonNumber: 1, episodeNumber: 1, name: 'Pilot',
          url: 'https://example.invalid/$id.mp4').toCompanion()]);
    }
    final history = WatchHistoryService(database);
    await history.saveWatchHistory(WatchHistory(playlistId: 'm3u',
        contentType: ContentType.series, streamId: '1:1', seriesId: 'show:a',
        lastWatched: DateTime(2026), title: 'Show A',
        watchDuration: const Duration(seconds: 12)));
    final library = LanLibraryService(database);
    Future<String> episodeId(String series) async {
      final details = await library.seriesDetails(playlistId: 'm3u', seriesId: series);
      final seasons = details['seasons'] as List;
      return ((seasons.single as Map)['episodes'] as List).single['id'] as String;
    }
    final a = await episodeId('show:a');
    final b = await episodeId('show:b');
    expect(a, isNot(b));
    Future<int> resume(String series, String episode) async =>
        (await library.playback(playlistId: 'm3u', contentType: ContentType.series,
            itemId: series, episodeId: episode)).startPositionMs;
    expect(await resume('show:b', b), 0);
    expect(await resume('show:a', a), 12000);
    // An old client can still send season:episode; its series scopes the write.
    await library.putHistory(playlistId: 'm3u', contentType: ContentType.series,
        itemId: '1:1', seriesId: 'show:b', title: 'Show B', positionMs: 34000);
    expect(await resume('show:a', a), 12000);
    expect(await resume('show:b', '1:1'), 34000);
    expect((await library.history(playlistId: 'm3u')).map((row) => row['itemId']),
        unorderedEquals([a, b]));
    expect(await history.getWatchHistory('m3u', '1:1'), isNull);
    await expectLater(resume('show:a', b), throwsA(isA<LanApiException>()));
    await library.deleteHistory(playlistId: 'm3u', itemId: b);
    expect(await resume('show:b', b), 0);
    expect(await resume('show:a', a), 12000);
  });

  test('item search matches the containing category name', () async {
    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.insertPlaylist(
      Playlist(
        id: 'playlist-1',
        name: 'Playlist',
        type: PlaylistType.m3u,
        createdAt: DateTime(2026),
      ),
    );
    await database.insertCategories([
      Category(
        categoryId: 'children',
        categoryName: 'EN | Children',
        parentId: 0,
        playlistId: 'playlist-1',
        type: CategoryType.live,
      ),
    ]);
    await database.insertM3uItem(
      M3uItem(
        id: 'channel-1',
        playlistId: 'playlist-1',
        name: 'Cartoon One',
        categoryId: 'children',
        url: 'https://example.invalid/live',
        contentType: ContentType.liveStream,
      ),
    );

    final result = await LanLibraryService(database).items(
      playlistId: 'playlist-1',
      contentType: ContentType.liveStream,
      query: 'children',
    );

    final items = result['items'] as List<Map<String, Object?>>;
    expect(items.single['name'], 'Cartoon One');
  });

  test('category-scoped search only matches item names', () async {
    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.insertPlaylist(
      Playlist(
        id: 'playlist-category-search',
        name: 'Playlist',
        type: PlaylistType.m3u,
        createdAt: DateTime(2026),
      ),
    );
    await database.insertCategories([
      Category(
        categoryId: 'children',
        categoryName: 'EN | Children',
        parentId: 0,
        playlistId: 'playlist-category-search',
        type: CategoryType.live,
      ),
    ]);
    await database.insertM3uItem(
      M3uItem(
        id: 'channel-1',
        playlistId: 'playlist-category-search',
        name: 'Cartoon One',
        categoryId: 'children',
        url: 'https://example.invalid/live',
        contentType: ContentType.liveStream,
      ),
    );

    final categoryNameResult = await LanLibraryService(database).items(
      playlistId: 'playlist-category-search',
      contentType: ContentType.liveStream,
      categoryId: 'children',
      query: 'children',
    );
    final itemNameResult = await LanLibraryService(database).items(
      playlistId: 'playlist-category-search',
      contentType: ContentType.liveStream,
      categoryId: 'children',
      query: 'cartoon',
    );

    expect(categoryNameResult['items'], isEmpty);
    expect((itemNameResult['items'] as List).single, isNotNull);
  });

  test('categories follow the desktop saved order', () async {
    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.insertPlaylist(
      Playlist(
        id: 'playlist-order',
        name: 'Playlist',
        type: PlaylistType.m3u,
        createdAt: DateTime(2026),
      ),
    );
    await database.insertCategories([
      Category(
        categoryId: 'news',
        categoryName: 'News',
        parentId: 0,
        playlistId: 'playlist-order',
        type: CategoryType.live,
      ),
      Category(
        categoryId: 'children',
        categoryName: 'Children',
        parentId: 0,
        playlistId: 'playlist-order',
        type: CategoryType.live,
      ),
      Category(
        categoryId: 'sports',
        categoryName: 'Sports',
        parentId: 0,
        playlistId: 'playlist-order',
        type: CategoryType.live,
      ),
    ]);
    await UserPreferences.setCategoryOrder(
      playlistId: 'playlist-order',
      type: CategoryType.live,
      categoryIds: ['children', 'news'],
    );

    final categories = await LanLibraryService(database).categories(
      playlistId: 'playlist-order',
      contentType: ContentType.liveStream,
    );

    expect(categories.map((category) => category['id']), [
      'children',
      'news',
      'sports',
    ]);
  });

  test('desktop radio preference filters LAN categories and items', () async {
    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.insertPlaylist(
      Playlist(
        id: 'playlist-radio',
        name: 'Playlist',
        type: PlaylistType.m3u,
        createdAt: DateTime(2026),
      ),
    );
    await database.insertCategories([
      Category(
        categoryId: 'radio',
        categoryName: 'GR | Radio',
        parentId: 0,
        playlistId: 'playlist-radio',
        type: CategoryType.live,
      ),
      Category(
        categoryId: 'general',
        categoryName: 'General',
        parentId: 0,
        playlistId: 'playlist-radio',
        type: CategoryType.live,
      ),
    ]);
    await database.insertM3uItem(
      M3uItem(
        id: 'radio-1',
        playlistId: 'playlist-radio',
        name: 'Athens FM',
        categoryId: 'radio',
        groupTitle: 'GR | Radio',
        url: 'https://example.invalid/radio',
        contentType: ContentType.liveStream,
      ),
    );
    await database.insertM3uItem(
      M3uItem(
        id: 'tv-1',
        playlistId: 'playlist-radio',
        name: 'Children TV',
        categoryId: 'general',
        groupTitle: 'General',
        url: 'https://example.invalid/tv',
        contentType: ContentType.liveStream,
      ),
    );
    await UserPreferences.setHideRadioStations(
      playlistId: 'playlist-radio',
      value: true,
    );

    final service = LanLibraryService(database);
    final categories = await service.categories(
      playlistId: 'playlist-radio',
      contentType: ContentType.liveStream,
    );
    final items = await service.items(
      playlistId: 'playlist-radio',
      contentType: ContentType.liveStream,
    );
    final preferences = await service.preferences('playlist-radio');

    expect(
      categories.firstWhere((item) => item['id'] == 'radio')['hidden'],
      isTrue,
    );
    expect(
      (items['items'] as List<Map<String, Object?>>).map((item) => item['id']),
      ['tv-1'],
    );
    expect(preferences['hideRadioStations'], isTrue);
  });
}
