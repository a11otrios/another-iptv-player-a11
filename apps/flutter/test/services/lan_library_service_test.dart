import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/models/category.dart';
import 'package:another_iptv_player/models/category_type.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/m3u_item.dart';
import 'package:another_iptv_player/models/playlist_model.dart';
import 'package:another_iptv_player/repositories/user_preferences.dart';
import 'package:another_iptv_player/services/lan_server/lan_library_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
