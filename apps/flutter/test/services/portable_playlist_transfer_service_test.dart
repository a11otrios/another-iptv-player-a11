import 'dart:convert';

import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/models/category.dart';
import 'package:another_iptv_player/models/category_type.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/live_stream.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/models/playlist_model.dart';
import 'package:another_iptv_player/models/series.dart';
import 'package:another_iptv_player/models/vod_streams.dart';
import 'package:another_iptv_player/repositories/user_preferences.dart';
import 'package:another_iptv_player/services/app_state.dart';
import 'package:another_iptv_player/services/channel_shortcut_service.dart';
import 'package:another_iptv_player/services/portable_playlist_transfer_service.dart';
import 'package:another_iptv_player/utils/category_item_sort.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PortablePlaylistMatcher', () {
    test('normalizes provider prefixes, quality labels, and accents', () {
      expect(
        PortablePlaylistMatcher.normalizeName('GR | ÉRT 1 (FHD)'),
        'ert 1',
      );
      expect(PortablePlaylistMatcher.normalizeName('ΕΡΤ 1 HD'), 'ερτ 1');
    });

    test('ignores source IDs for a different playlist', () {
      final matcher = PortablePlaylistMatcher([
        const PortableMatchCandidate(
          key: 'first',
          sourceId: 'same-id-as-backup',
          name: 'Channel One',
          contentType: ContentType.liveStream,
        ),
        const PortableMatchCandidate(
          key: 'second',
          sourceId: 'target-two',
          name: 'Channel Two',
          contentType: ContentType.liveStream,
        ),
      ]);

      final result = matcher.match(
        const PortableTransferEntry(
          name: 'Channel Two HD',
          contentType: ContentType.liveStream,
          sourceId: 'same-id-as-backup',
        ),
        samePlaylist: false,
      );

      expect(result.status, PortableMatchStatus.matched);
      expect(result.candidate?.key, 'second');
    });

    test('uses group names to disambiguate duplicate channel names', () {
      final matcher = PortablePlaylistMatcher([
        const PortableMatchCandidate(
          key: 'news',
          sourceId: '1',
          name: 'World Feed HD',
          contentType: ContentType.liveStream,
          groupName: 'News',
        ),
        const PortableMatchCandidate(
          key: 'sports',
          sourceId: '2',
          name: 'World Feed FHD',
          contentType: ContentType.liveStream,
          groupName: 'Sports',
        ),
      ]);

      final result = matcher.match(
        const PortableTransferEntry(
          name: 'World Feed',
          contentType: ContentType.liveStream,
          groupName: 'Sports',
        ),
        samePlaylist: false,
      );

      expect(result.status, PortableMatchStatus.matched);
      expect(result.candidate?.key, 'sports');
    });

    test(
      'uses a stable source ID to disambiguate duplicate names on another PC',
      () {
        final matcher = PortablePlaylistMatcher([
          const PortableMatchCandidate(
            key: 'sd',
            sourceId: '100',
            name: 'GR | ERT 1',
            contentType: ContentType.liveStream,
            groupName: 'Greek',
          ),
          const PortableMatchCandidate(
            key: 'hd',
            sourceId: '101',
            name: 'GR | ERT 1 HD',
            contentType: ContentType.liveStream,
            groupName: 'Greek',
          ),
        ]);

        final result = matcher.match(
          const PortableTransferEntry(
            name: 'GR | ERT 1 HD',
            contentType: ContentType.liveStream,
            sourceId: '101',
            groupName: 'Greek',
          ),
          samePlaylist: false,
        );

        expect(result.status, PortableMatchStatus.matched);
        expect(result.candidate?.key, 'hd');
      },
    );

    test('does not trust a colliding source ID with a different identity', () {
      final matcher = PortablePlaylistMatcher([
        const PortableMatchCandidate(
          key: 'collision',
          sourceId: '101',
          name: 'Unrelated Channel',
          contentType: ContentType.liveStream,
        ),
        const PortableMatchCandidate(
          key: 'correct',
          sourceId: '202',
          name: 'ERT 1 HD',
          contentType: ContentType.liveStream,
        ),
      ]);

      final result = matcher.match(
        const PortableTransferEntry(
          name: 'GR | ERT 1 FHD',
          contentType: ContentType.liveStream,
          sourceId: '101',
        ),
        samePlaylist: false,
      );

      expect(result.status, PortableMatchStatus.matched);
      expect(result.candidate?.key, 'correct');
    });
  });

  group('PortablePlaylistTransferService', () {
    late AppDatabase database;
    late _FakeShortcutStore shortcutStore;
    late Playlist playlist;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      database = AppDatabase(NativeDatabase.memory());
      shortcutStore = _FakeShortcutStore();
      playlist = Playlist(
        id: 'target-playlist',
        name: 'Target',
        type: PlaylistType.xtream,
        url: 'https://target.invalid',
        username: 'target-user',
        password: 'target-password',
        createdAt: DateTime(2026),
      );
      AppState.currentPlaylist = playlist;

      await database.insertCategories([
        Category(
          categoryId: 'greek',
          categoryName: 'Greek',
          parentId: 0,
          playlistId: playlist.id,
          type: CategoryType.live,
        ),
        Category(
          categoryId: 'sports',
          categoryName: 'Sports',
          parentId: 0,
          playlistId: playlist.id,
          type: CategoryType.live,
        ),
        Category(
          categoryId: 'movies',
          categoryName: 'Movies',
          parentId: 0,
          playlistId: playlist.id,
          type: CategoryType.vod,
        ),
        Category(
          categoryId: 'series',
          categoryName: 'Series',
          parentId: 0,
          playlistId: playlist.id,
          type: CategoryType.series,
        ),
      ]);

      await database.insertLiveStreams([
        LiveStream(
          streamId: 'target-ert',
          name: 'ERT 1 HD',
          streamIcon: '',
          categoryId: 'greek',
          epgChannelId: 'ert1.gr',
          playlistId: playlist.id,
        ),
        LiveStream(
          streamId: 'target-sport',
          name: 'COSMOTE SPORT 1',
          streamIcon: '',
          categoryId: 'sports',
          epgChannelId: 'cosmote.sport.1',
          playlistId: playlist.id,
        ),
      ]);
      await database.insertVodStreams([
        VodStream(
          streamId: 'target-matrix',
          name: 'Matrix (1999)',
          streamIcon: '',
          categoryId: 'movies',
          rating: '',
          rating5based: 0,
          containerExtension: 'mkv',
          playlistId: playlist.id,
          createdAt: DateTime(2026),
        ),
      ]);
      await database.insertSeriesStreams([
        SeriesStream(
          playlistId: playlist.id,
          seriesId: 'target-series',
          name: 'House of the Dragon',
          categoryId: 'series',
        ),
      ]);

      shortcutStore.shortcuts[9] = ContentItem(
        'existing',
        'Existing shortcut',
        '',
        ContentType.liveStream,
        liveStream: LiveStream(
          streamId: 'existing',
          name: 'Existing shortcut',
          streamIcon: '',
          categoryId: '',
          epgChannelId: '',
          playlistId: playlist.id,
        ),
      );
      shortcutStore.shortcutsByPage['S'] = {
        2: ContentItem(
          'existing-s',
          'Existing S shortcut',
          '',
          ContentType.liveStream,
          liveStream: LiveStream(
            streamId: 'existing-s',
            name: 'Existing S shortcut',
            streamIcon: '',
            categoryId: '',
            epgChannelId: '',
            playlistId: playlist.id,
          ),
        ),
      };
    });

    tearDown(() async {
      AppState.currentPlaylist = null;
      await database.close();
    });

    test(
      'imports by name and guide ID while preserving unrelated slots',
      () async {
        final backup = jsonEncode({
          'format': PortablePlaylistTransferService.formatName,
          'version': PortablePlaylistTransferService.formatVersion,
          'sourcePlaylist': {
            'id': 'different-playlist',
            'name': 'Source',
            'type': 'xtream',
          },
          'favorites': [
            {
              'name': 'GR | ERT 1 FHD',
              'contentType': 'liveStream',
              'sourceId': 'old-ert',
            },
            {
              'name': 'The Matrix (1999) UHD',
              'contentType': 'vod',
              'sourceId': 'old-matrix',
            },
            {
              'name': 'House of the Dragon 4K',
              'contentType': 'series',
              'sourceId': 'old-series',
            },
            {
              'name': 'Missing channel',
              'contentType': 'liveStream',
              'sourceId': 'missing',
            },
          ],
          'channelNumbers': {
            '1': {
              'name': 'GR | ERT 1',
              'contentType': 'liveStream',
              'sourceId': 'old-ert',
            },
            '5': {
              'name': 'Provider-specific sports label',
              'contentType': 'liveStream',
              'sourceId': 'old-sport',
              'guideId': 'cosmote.sport.1',
            },
          },
          'channelNumberPages': {
            'S': {
              '1': {
                'name': 'Provider-specific sports label',
                'contentType': 'liveStream',
                'sourceId': 'old-sport',
                'guideId': 'cosmote.sport.1',
              },
            },
          },
        });
        final service = PortablePlaylistTransferService(
          database: database,
          shortcutStore: shortcutStore,
        );

        final result = await service.importIntoCurrentPlaylist(backup);

        expect(result.favoritesAdded, 3);
        expect(result.favoritesAlreadyPresent, 0);
        expect(result.channelNumbersAssigned, 3);
        expect(result.unmatchedNames, ['Missing channel']);
        expect(result.ambiguousNames, isEmpty);

        final favorites = await database.getFavoritesByPlaylist(playlist.id);
        expect(favorites.map((favorite) => favorite.streamId).toSet(), {
          'target-ert',
          'target-matrix',
          'target-series',
        });
        expect(shortcutStore.shortcuts[1]?.id, 'target-ert');
        expect(shortcutStore.shortcuts[5]?.id, 'target-sport');
        expect(shortcutStore.shortcuts[9]?.id, 'existing');
        expect(shortcutStore.shortcutsByPage['S']?[1]?.id, 'target-sport');
        expect(shortcutStore.shortcutsByPage['S']?[2]?.id, 'existing-s');

        final roundTrip =
            jsonDecode(await service.exportCurrentPlaylist())
                as Map<String, dynamic>;
        final roundTripFavorites = (roundTrip['favorites'] as List)
            .cast<Map<String, dynamic>>();
        expect(roundTripFavorites.map((entry) => entry['name']).toSet(), {
          'ERT 1 HD',
          'Matrix (1999)',
          'House of the Dragon',
        });
        expect((roundTrip['channelNumbers'] as Map).keys.toSet(), {
          '1',
          '5',
          '9',
        });
        final shortcutPages =
            roundTrip['channelNumberPages'] as Map<String, dynamic>;
        expect((shortcutPages['A'] as Map).keys.toSet(), {'1', '5', '9'});
        expect((shortcutPages['S'] as Map).keys.toSet(), {'1', '2'});

        final secondResult = await service.importIntoCurrentPlaylist(backup);
        expect(secondResult.favoritesAdded, 0);
        expect(secondResult.favoritesAlreadyPresent, 3);
      },
    );

    test(
      'imports duplicate channel names by stable ID on another PC',
      () async {
        await database.insertLiveStreams([
          LiveStream(
            streamId: 'target-ert-sd',
            name: 'ERT 1',
            streamIcon: '',
            categoryId: 'greek',
            epgChannelId: '',
            playlistId: playlist.id,
          ),
        ]);
        final backup = jsonEncode({
          'format': PortablePlaylistTransferService.formatName,
          'version': PortablePlaylistTransferService.formatVersion,
          'sourcePlaylist': {
            'id': 'same-provider-different-local-id',
            'name': 'Target',
            'type': 'xtream',
          },
          'favorites': [
            {
              'name': 'GR | ERT 1 HD',
              'contentType': 'liveStream',
              'sourceId': 'target-ert',
            },
          ],
          'channelNumbers': {
            '1': {
              'name': 'GR | ERT 1 HD',
              'contentType': 'liveStream',
              'sourceId': 'target-ert',
            },
          },
        });
        final service = PortablePlaylistTransferService(
          database: database,
          shortcutStore: shortcutStore,
        );

        final result = await service.importIntoCurrentPlaylist(backup);

        expect(result.favoritesAdded, 1);
        expect(result.channelNumbersAssigned, 1);
        expect(result.unmatchedNames, isEmpty);
        expect(result.ambiguousNames, isEmpty);
        final favorites = await database.getFavoritesByPlaylist(playlist.id);
        expect(favorites.single.streamId, 'target-ert');
        expect(shortcutStore.shortcuts[1]?.id, 'target-ert');
      },
    );

    test('exports a versioned backup without playlist credentials', () async {
      final service = PortablePlaylistTransferService(
        database: database,
        shortcutStore: shortcutStore,
      );
      final output = await service.exportCurrentPlaylist();
      final decoded = jsonDecode(output) as Map<String, dynamic>;

      expect(decoded['format'], PortablePlaylistTransferService.formatName);
      expect(decoded['version'], 1);
      expect(output, isNot(contains('target-password')));
      expect(output, isNot(contains('target-user')));
      expect(output, isNot(contains('https://target.invalid')));
    });

    test('exports and imports hidden categories', () async {
      await UserPreferences.setHiddenCategories([
        UserPreferences.hiddenCategoryKey(CategoryType.live, 'greek'),
        UserPreferences.hiddenCategoryKey(CategoryType.vod, 'movies'),
      ], playlistId: playlist.id);
      final service = PortablePlaylistTransferService(
        database: database,
        shortcutStore: shortcutStore,
      );

      final output = await service.exportCurrentPlaylist();
      final decoded = jsonDecode(output) as Map<String, dynamic>;
      final hiddenCategories = (decoded['hiddenCategories'] as List)
          .cast<Map<String, dynamic>>();

      expect(hiddenCategories, [
        {'categoryId': 'greek', 'type': 'live', 'name': 'Greek'},
        {'categoryId': 'movies', 'type': 'vod', 'name': 'Movies'},
      ]);

      await UserPreferences.setHiddenCategories([
        UserPreferences.hiddenCategoryKey(CategoryType.series, 'series'),
      ], playlistId: playlist.id);

      final result = await service.importIntoCurrentPlaylist(output);
      final hidden = await UserPreferences.getHiddenCategories(
        playlistId: playlist.id,
      );

      expect(result.hiddenCategoriesImported, 2);
      expect(hidden.toSet(), {
        UserPreferences.hiddenCategoryKey(CategoryType.live, 'greek'),
        UserPreferences.hiddenCategoryKey(CategoryType.vod, 'movies'),
        UserPreferences.hiddenCategoryKey(CategoryType.series, 'series'),
      });
    });

    test('exports and imports category order across changed IDs', () async {
      await UserPreferences.setHideRadioStations(
        playlistId: playlist.id,
        value: true,
      );
      await UserPreferences.setCategoryOrder(
        playlistId: playlist.id,
        type: CategoryType.live,
        categoryIds: ['sports', 'greek'],
      );
      final service = PortablePlaylistTransferService(
        database: database,
        shortcutStore: shortcutStore,
      );

      final decoded =
          jsonDecode(await service.exportCurrentPlaylist())
              as Map<String, dynamic>;
      final categoryOrder = (decoded['categoryOrder'] as List)
          .cast<Map<String, dynamic>>();
      expect(decoded['hideRadioStations'], isTrue);
      expect(
        categoryOrder
            .where((entry) => entry['type'] == 'live')
            .map((entry) => entry['name']),
        ['Sports', 'Greek'],
      );

      decoded['sourcePlaylist'] = {
        'id': 'source-playlist',
        'name': 'Source',
        'type': 'xtream',
      };
      for (final entry in categoryOrder) {
        entry['categoryId'] = 'source-${entry['categoryId']}';
      }
      await UserPreferences.setCategoryOrder(
        playlistId: playlist.id,
        type: CategoryType.live,
        categoryIds: ['greek', 'sports'],
      );
      await UserPreferences.setHideRadioStations(
        playlistId: playlist.id,
        value: false,
      );

      final result = await service.importIntoCurrentPlaylist(
        jsonEncode(decoded),
      );

      expect(result.categoryOrderImported, 4);
      expect(
        await UserPreferences.getHideRadioStations(playlistId: playlist.id),
        isTrue,
      );
      expect(
        await UserPreferences.getCategoryOrder(
          playlistId: playlist.id,
          type: CategoryType.live,
        ),
        ['sports', 'greek'],
      );
    });

    test('imports older backups without changing category order', () async {
      await UserPreferences.setCategoryOrder(
        playlistId: playlist.id,
        type: CategoryType.live,
        categoryIds: ['sports', 'greek'],
      );
      final service = PortablePlaylistTransferService(
        database: database,
        shortcutStore: shortcutStore,
      );
      final decoded =
          jsonDecode(await service.exportCurrentPlaylist())
                as Map<String, dynamic>
            ..remove('categoryOrder')
            ..remove('hideRadioStations');

      final result = await service.importIntoCurrentPlaylist(
        jsonEncode(decoded),
      );

      expect(result.categoryOrderImported, 0);
      expect(
        await UserPreferences.getCategoryOrder(
          playlistId: playlist.id,
          type: CategoryType.live,
        ),
        ['sports', 'greek'],
      );
    });

    test(
      'exports and imports category item sorts across changed IDs',
      () async {
        await UserPreferences.setCategoryItemSort(
          playlistId: playlist.id,
          type: CategoryType.vod,
          categoryId: 'movies',
          sort: CategoryItemSort.releaseDate,
        );
        final service = PortablePlaylistTransferService(
          database: database,
          shortcutStore: shortcutStore,
        );
        final decoded =
            jsonDecode(await service.exportCurrentPlaylist())
                as Map<String, dynamic>;
        final sorts = (decoded['categoryItemSorts'] as List)
            .cast<Map<String, dynamic>>();
        expect(sorts, [
          {
            'categoryId': 'movies',
            'type': 'vod',
            'name': 'Movies',
            'sort': 'releaseDate',
          },
        ]);

        sorts.single['categoryId'] = 'source-movies';
        await UserPreferences.setCategoryItemSort(
          playlistId: playlist.id,
          type: CategoryType.vod,
          categoryId: 'movies',
          sort: CategoryItemSort.provider,
        );
        final result = await service.importIntoCurrentPlaylist(
          jsonEncode(decoded),
        );

        expect(result.categoryItemSortsImported, 1);
        expect(
          await UserPreferences.getCategoryItemSort(
            playlistId: playlist.id,
            type: CategoryType.vod,
            categoryId: 'movies',
          ),
          CategoryItemSort.releaseDate,
        );
      },
    );
  });
}

class _FakeShortcutStore implements ChannelShortcutStore {
  final Map<int, ContentItem> shortcuts = {};
  final Map<String, Map<int, ContentItem>> shortcutsByPage = {};

  @override
  Future<Map<int, ContentItem>> getShortcuts() async {
    return getShortcutsForPage(ChannelShortcutService.defaultPage);
  }

  @override
  Future<Map<int, ContentItem>> getShortcutsForPage(String page) async {
    return Map<int, ContentItem>.from(
      page == ChannelShortcutService.defaultPage
          ? shortcuts
          : shortcutsByPage[page] ?? {},
    );
  }

  @override
  Future<void> saveShortcuts(Map<int, ContentItem> shortcuts) async {
    await saveShortcutsForPage(ChannelShortcutService.defaultPage, shortcuts);
  }

  @override
  Future<void> saveShortcutsForPage(
    String page,
    Map<int, ContentItem> shortcuts,
  ) async {
    final target = page == ChannelShortcutService.defaultPage
        ? this.shortcuts
        : shortcutsByPage.putIfAbsent(page, () => {});
    target
      ..clear()
      ..addAll(shortcuts);
  }
}
