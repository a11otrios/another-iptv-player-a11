import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/models/content_type.dart' as app;
import 'package:another_iptv_player/models/category.dart';
import 'package:another_iptv_player/models/category_type.dart';
import 'package:another_iptv_player/models/m3u_item.dart';
import 'package:another_iptv_player/models/playlist_model.dart';
import 'package:another_iptv_player/models/series.dart';
import 'package:another_iptv_player/models/subtitle_search_result.dart';
import 'package:another_iptv_player/models/vod_streams.dart';
import 'package:another_iptv_player/services/lan_server/lan_server_controller.dart';
import 'package:another_iptv_player/services/open_subtitles_service.dart';
import 'package:another_iptv_player/services/service_locator.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase database;
  late LanServerController server;
  late HttpClient client;
  late HttpServer upstream;
  late Uri baseUri;
  late Directory tempDirectory;
  var largeStream = false;
  var producedChunks = 0;

  setUp(() async {
    largeStream = false;
    producedChunks = 0;
    SharedPreferences.setMockInitialValues({
      'channel_shortcuts_playlist-1': jsonEncode({
        '1': {'id': 'channel-1', 'name': 'Kids One', 'imagePath': null},
      }),
      'channel_shortcuts_playlist-1_S': jsonEncode({
        '2': {'id': 'channel-hls', 'name': 'Kids Two', 'imagePath': null},
      }),
    });
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      if (request.uri.path.endsWith('player_api.php') &&
          request.uri.queryParameters['action'] == 'get_series_info') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'info': {'name': 'Test Series', 'last_modified': '1767225600'},
            'seasons': [
              {'id': 10, 'name': 'Season 1', 'season_number': 1},
            ],
            'episodes': {
              '1': [
                {
                  'id': 'episode-1',
                  'episode_num': 1,
                  'title': 'Pilot',
                  'container_extension': 'mp4',
                  'season': 1,
                  'info': {'duration_secs': 1800},
                },
              ],
            },
          }),
        );
        await request.response.close();
        return;
      }
      if (request.uri.path.endsWith('index.m3u8') &&
          !request.uri.path.startsWith('/redirected/')) {
        await request.response.redirect(Uri.parse('/redirected/index.m3u8'));
        return;
      }
      if ((request.uri.path.endsWith('segment.ts') ||
              request.uri.path.endsWith('key.bin')) &&
          !request.uri.path.startsWith('/redirected/')) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      if (request.uri.path.endsWith('index.m3u8')) {
        request.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
        );
        request.response.write('''#EXTM3U
#EXT-X-TARGETDURATION:4
#EXT-X-KEY:METHOD=AES-128,URI="key.bin"
#EXTINF:4,
segment.ts
''');
        await request.response.close();
        return;
      }
      if (largeStream) {
        Stream<List<int>> chunks() async* {
          final chunk = List<int>.filled(64 * 1024, 0x47);
          for (var i = 0; i < 2048; i++) {
            producedChunks++;
            yield chunk;
          }
        }

        try {
          await request.response.addStream(chunks());
          await request.response.close();
        } catch (_) {
          /* Test client intentionally disconnects. */
        }
        return;
      }
      request.response.headers.contentType = ContentType('video', 'mp2t');
      request.response.add(const [0x47, 0x40, 0x00, 0x10]);
      await request.response.close();
    });
    database = AppDatabase(NativeDatabase.memory());
    if (getIt.isRegistered<AppDatabase>()) {
      await getIt.unregister<AppDatabase>();
    }
    getIt.registerSingleton<AppDatabase>(database);
    tempDirectory = await Directory.systemTemp.createTemp('aiptv-test-');
    final subtitleFile = File('${tempDirectory.path}/subtitle.srt');
    await subtitleFile.writeAsString(
      '1\n00:00:01,000 --> 00:00:02,000\nHello TV\n',
    );
    await database.insertPlaylist(
      Playlist(
        id: 'playlist-1',
        name: 'Living Room Library',
        type: PlaylistType.m3u,
        url: 'https://provider.invalid/private-list.m3u',
        createdAt: DateTime.utc(2026),
      ),
    );
    await database.insertPlaylist(
      Playlist(
        id: 'xtream-playlist',
        name: 'Xtream Library',
        type: PlaylistType.xtream,
        url: 'http://127.0.0.1:${upstream.port}',
        username: 'test-user',
        password: 'test-password',
        createdAt: DateTime.utc(2026),
      ),
    );
    await database.insertSeriesStreams([
      SeriesStream(
        playlistId: 'xtream-playlist',
        seriesId: 'series-1',
        name: 'Test Series',
        lastModified: '1767225600',
      ),
    ]);
    await database.insertVodStreams([
      VodStream(
        streamId: 'movie-4k',
        name: 'Test 4K Movie',
        streamIcon: '',
        categoryId: 'movies-4k',
        rating: '',
        rating5based: 0,
        containerExtension: 'mkv',
        playlistId: 'xtream-playlist',
        createdAt: DateTime.utc(2026),
      ),
    ]);
    await database.insertCategories([
      Category(
        categoryId: 'news',
        categoryName: 'News',
        parentId: 0,
        playlistId: 'playlist-1',
        type: CategoryType.live,
      ),
    ]);
    await database.insertM3uItem(
      M3uItem(
        id: 'channel-1',
        playlistId: 'playlist-1',
        name: 'News One',
        groupTitle: 'News',
        categoryId: 'news',
        url: 'http://127.0.0.1:${upstream.port}/live/private-token.ts',
        contentType: app.ContentType.liveStream,
      ),
    );
    await database.insertM3uItem(
      M3uItem(
        id: 'channel-hls',
        playlistId: 'playlist-1',
        name: 'News HLS',
        groupTitle: 'News',
        categoryId: 'news',
        url: 'http://127.0.0.1:${upstream.port}/hls/private/index.m3u8',
        contentType: app.ContentType.liveStream,
      ),
    );
    server = LanServerController(
      subtitlesService: _CachedSubtitleService(
        CachedSubtitle(
          contentKey: 'playlist-1:vod:movie-1',
          filePath: subtitleFile.path,
          title: 'English subtitle',
          language: 'en',
          offsetSeconds: 0,
        ),
      ),
    );
    await server.initialize(database, port: 0, enableDiscovery: false);
    expect(server.running, isTrue, reason: server.error);
    baseUri = Uri.parse('http://127.0.0.1:${server.port}/api/v1/');
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
    await upstream.close(force: true);
    if (getIt.isRegistered<AppDatabase>()) {
      await getIt.unregister<AppDatabase>();
    }
    await database.close();
    await tempDirectory.delete(recursive: true);
  });

  test('a paused TV applies backpressure to the provider', () async {
    final paired = await _request(
      client,
      baseUri.resolve('pair'),
      method: 'POST',
      body: {
        'code': server.pairing.pairingCode,
        'deviceName': 'Backpressure test',
      },
    );
    final token = paired.body['token'] as String;
    final playback = await _request(
      client,
      baseUri.resolve('playback'),
      method: 'POST',
      token: token,
      body: {'playlistId': 'playlist-1', 'type': 'live', 'itemId': 'channel-1'},
    );
    largeStream = true;
    final response = await (await client.getUrl(
      Uri.parse((playback.body['data'] as Map)['url'] as String),
    )).close();
    final received = Completer<void>();
    late StreamSubscription<List<int>> subscription;
    subscription = response.listen((_) {
      subscription.pause();
      if (!received.isCompleted) received.complete();
    });
    await received.future.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(
      producedChunks,
      lessThan(2048),
      reason:
          'The proxy must not buffer the entire movie while the TV is paused',
    );
    await subscription.cancel();
  });

  test(
    'pairs, syncs opaque catalog data, writes state, and revokes access',
    () async {
      final status = await _request(client, baseUri.resolve('status'));
      expect(status.statusCode, HttpStatus.ok);
      expect(status.body['pairingAvailable'], isTrue);

      final localPairing = await _request(
        client,
        baseUri.resolve('local/pairing'),
      );
      expect(localPairing.statusCode, HttpStatus.ok);
      expect(localPairing.body['pairingCode'], server.pairingCode);
      expect(localPairing.body['pairingCode'], matches(RegExp(r'^\d{6}$')));

      final unauthorized = await _request(client, baseUri.resolve('playlists'));
      expect(unauthorized.statusCode, HttpStatus.unauthorized);

      final unauthorizedMediaRelease = await _request(
        client,
        baseUri.resolve('media/missing-session'),
        method: 'DELETE',
      );
      expect(unauthorizedMediaRelease.statusCode, HttpStatus.unauthorized);

      final paired = await _request(
        client,
        baseUri.resolve('pair'),
        method: 'POST',
        body: {'code': server.pairingCode, 'deviceName': 'Test LG TV'},
      );
      expect(paired.statusCode, HttpStatus.ok);
      final token = paired.body['token'] as String;
      final deviceId = paired.body['deviceId'] as String;

      final missingMediaRelease = await _request(
        client,
        baseUri.resolve('media/missing-session'),
        method: 'DELETE',
        token: token,
      );
      expect(missingMediaRelease.statusCode, HttpStatus.notFound);
      expect(
        (missingMediaRelease.body['error'] as Map)['code'],
        'media_expired',
      );

      final defaultShortcuts = await _request(
        client,
        baseUri.resolve('shortcuts?playlistId=playlist-1&page=A'),
        token: token,
      );
      expect(
        ((defaultShortcuts.body['data'] as Map)['1'] as Map)['name'],
        'Kids One',
      );
      final secondPageShortcuts = await _request(
        client,
        baseUri.resolve('shortcuts?playlistId=playlist-1&page=S'),
        token: token,
      );
      expect(
        ((secondPageShortcuts.body['data'] as Map)['2'] as Map)['name'],
        'Kids Two',
      );
      final invalidShortcutPage = await _request(
        client,
        baseUri.resolve('shortcuts?playlistId=playlist-1&page=Z'),
        token: token,
      );
      expect(invalidShortcutPage.statusCode, HttpStatus.badRequest);
      expect(
        (invalidShortcutPage.body['error'] as Map)['code'],
        'invalid_shortcut_page',
      );

      final playlists = await _request(
        client,
        baseUri.resolve('playlists'),
        token: token,
      );
      expect(playlists.statusCode, HttpStatus.ok);
      expect(
        (playlists.body['data'] as List).map((item) => item['name']),
        contains('Living Room Library'),
      );
      expect(jsonEncode(playlists.body), isNot(contains('private-list.m3u')));

      final preferences = await _request(
        client,
        baseUri.resolve('preferences?playlistId=playlist-1'),
        token: token,
      );
      final subtitleStyle =
          (preferences.body['data'] as Map)['subtitleStyle'] as Map;
      expect(subtitleStyle['fontSize'], 32.0);
      expect(subtitleStyle['textColor'], 'rgba(255, 255, 255, 1.000)');

      final series = await _request(
        client,
        baseUri.resolve('series/series-1?playlistId=xtream-playlist'),
        token: token,
      );
      expect(series.statusCode, HttpStatus.ok);
      final seasons = (series.body['data'] as Map)['seasons'] as List;
      expect(seasons, hasLength(1));
      expect((seasons.single as Map)['seasonNumber'], 1);
      expect(
        ((seasons.single as Map)['episodes'] as List).single['title'],
        'Pilot',
      );

      final items = await _request(
        client,
        baseUri.resolve(
          'items?playlistId=playlist-1&type=live&offset=0&limit=20',
        ),
        token: token,
      );
      final item = ((items.body['data'] as Map)['items'] as List)
          .whereType<Map>()
          .firstWhere((entry) => entry['id'] == 'channel-1');
      expect(item['name'], 'News One');
      expect(jsonEncode(item), isNot(contains('private-token')));

      final sortedItems = await _request(
        client,
        baseUri.resolve(
          'items?playlistId=playlist-1&type=live&sort=descending&limit=20',
        ),
        token: token,
      );
      expect(
        ((sortedItems.body['data'] as Map)['items'] as List)
            .map((entry) => (entry as Map)['name'])
            .toList(),
        ['News One', 'News HLS'],
      );

      final singleItem = await _request(
        client,
        baseUri.resolve(
          'item?playlistId=playlist-1&type=live&itemId=channel-1',
        ),
        token: token,
      );
      expect((singleItem.body['data'] as Map)['name'], 'News One');
      expect(jsonEncode(singleItem.body), isNot(contains('private-token')));

      final shelves = await _request(
        client,
        baseUri.resolve('shelves?playlistId=playlist-1&type=live&limit=10'),
        token: token,
      );
      final shelf = (shelves.body['data'] as List).single as Map;
      expect((shelf['category'] as Map)['name'], 'News');
      expect(shelf['total'], 2);
      expect((shelf['items'] as List), hasLength(2));
      expect(jsonEncode(shelf), isNot(contains('private-token')));

      final playback = await _request(
        client,
        baseUri.resolve('playback'),
        method: 'POST',
        token: token,
        body: {
          'playlistId': 'playlist-1',
          'type': 'live',
          'itemId': 'channel-1',
        },
      );
      final descriptor = playback.body['data'] as Map;
      expect(descriptor['mode'], 'proxy');
      expect(descriptor['url'], startsWith('http://127.0.0.1:'));
      expect(descriptor['url'], isNot(contains('private-token')));
      expect(descriptor['url'], isNot(contains(token)));
      final playbackUri = Uri.parse(descriptor['url'] as String);
      final missingGrantRequest = await client.getUrl(
        playbackUri.replace(query: ''),
      );
      final missingGrantResponse = await missingGrantRequest.close();
      await missingGrantResponse.drain<void>();
      expect(missingGrantResponse.statusCode, HttpStatus.notFound);
      final mediaRequest = await client.getUrl(playbackUri);
      final mediaResponse = await mediaRequest.close();
      final mediaBytes = await mediaResponse.fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      );
      expect(mediaResponse.statusCode, HttpStatus.ok);
      expect(mediaBytes, const [0x47, 0x40, 0x00, 0x10]);

      final moviePlayback = await _request(
        client,
        baseUri.resolve('playback'),
        method: 'POST',
        token: token,
        body: {
          'playlistId': 'xtream-playlist',
          'type': 'vod',
          'itemId': 'movie-4k',
          'startPositionMs': 564191,
        },
      );
      final movieDescriptor = moviePlayback.body['data'] as Map;
      expect(movieDescriptor['mode'], 'proxy');
      expect(movieDescriptor['startPositionMs'], 564191);
      final moviePlaybackUri = Uri.parse(movieDescriptor['url'] as String);
      expect(moviePlaybackUri.path, endsWith('.mkv'));
      expect(movieDescriptor['url'], isNot(contains('test-password')));

      final legacyDirectRequest = await _request(
        client,
        baseUri.resolve('playback'),
        method: 'POST',
        token: token,
        body: {
          'playlistId': 'playlist-1',
          'type': 'live',
          'itemId': 'channel-1',
          'preferDirect': true,
        },
      );
      final legacyDescriptor = legacyDirectRequest.body['data'] as Map;
      expect(legacyDescriptor['mode'], 'proxy');
      expect(legacyDescriptor['url'], isNot(contains('private-token')));

      final hlsPlayback = await _request(
        client,
        baseUri.resolve('playback'),
        method: 'POST',
        token: token,
        body: {
          'playlistId': 'playlist-1',
          'type': 'live',
          'itemId': 'channel-hls',
        },
      );
      final hlsDescriptor = hlsPlayback.body['data'] as Map;
      expect(hlsDescriptor['mode'], 'hls');
      final manifestRequest = await client.getUrl(
        Uri.parse(hlsDescriptor['url'] as String),
      );
      final manifestResponse = await manifestRequest.close();
      final manifest = await utf8.decoder.bind(manifestResponse).join();
      expect(manifest, contains('#EXTM3U'));
      expect(manifest, isNot(contains('/hls/private/')));
      expect(manifest, isNot(contains(token)));
      expect(manifest, contains('URI="http://127.0.0.1:'));
      final segmentUrl = manifest
          .split('\n')
          .firstWhere((line) => line.startsWith('http://'));
      final segmentRequest = await client.getUrl(Uri.parse(segmentUrl));
      final segmentResponse = await segmentRequest.close();
      final segmentBytes = await segmentResponse.fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      );
      expect(segmentResponse.statusCode, HttpStatus.ok);
      expect(segmentBytes, const [0x47, 0x40, 0x00, 0x10]);

      final patchedPreferences = await _request(
        client,
        baseUri.resolve('preferences?playlistId=playlist-1'),
        method: 'PATCH',
        token: token,
        body: {
          'hiddenCategories': ['live:news'],
          'audioLanguage': 'en',
          'subtitleLanguage': '__off__',
        },
      );
      expect(
        (patchedPreferences.body['data'] as Map)['hiddenCategories'],
        contains('live:news'),
      );
      expect((patchedPreferences.body['data'] as Map)['audioLanguage'], 'en');
      expect(
        (patchedPreferences.body['data'] as Map)['subtitleLanguage'],
        '__off__',
      );
      final hiddenItems = await _request(
        client,
        baseUri.resolve(
          'items?playlistId=playlist-1&type=live&offset=0&limit=20',
        ),
        token: token,
      );
      expect((hiddenItems.body['data'] as Map)['items'], isEmpty);
      final hiddenSingleItem = await _request(
        client,
        baseUri.resolve(
          'item?playlistId=playlist-1&type=live&itemId=channel-1',
        ),
        token: token,
      );
      expect(hiddenSingleItem.body['data'], isNull);
      final hiddenSearch = await _request(
        client,
        baseUri.resolve('search?playlistId=playlist-1&query=News&limit=20'),
        token: token,
      );
      expect(hiddenSearch.body['data'], isEmpty);

      await _request(
        client,
        baseUri.resolve('favorites/live/channel-1'),
        method: 'PUT',
        token: token,
        body: {
          'playlistId': 'playlist-1',
          'name': 'News One',
          'imageUrl': null,
        },
      );
      final favorites = await _request(
        client,
        baseUri.resolve('favorites?playlistId=playlist-1'),
        token: token,
      );
      expect((favorites.body['data'] as List).single['name'], 'News One');

      await _request(
        client,
        baseUri.resolve('history/live/channel-1'),
        method: 'PUT',
        token: token,
        body: {
          'playlistId': 'playlist-1',
          'title': 'News One',
          'positionMs': 12000,
          'durationMs': 60000,
        },
      );
      final history = await _request(
        client,
        baseUri.resolve('history?playlistId=playlist-1'),
        token: token,
      );
      expect((history.body['data'] as List).single['positionMs'], 12000);

      final clearHistory = await _request(
        client,
        baseUri.resolve('history?playlistId=playlist-1'),
        method: 'DELETE',
        token: token,
      );
      expect(clearHistory.statusCode, HttpStatus.noContent);
      final clearedHistory = await _request(
        client,
        baseUri.resolve('history?playlistId=playlist-1'),
        token: token,
      );
      expect(clearedHistory.body['data'], isEmpty);

      final cachedSubtitle = await _request(
        client,
        baseUri.resolve(
          'subtitles/cached?playlistId=playlist-1&type=vod&itemId=movie-1',
        ),
        token: token,
      );
      final subtitleUrl = (cachedSubtitle.body['data'] as Map)['url'] as String;
      expect(subtitleUrl, isNot(contains(token)));
      final subtitleUri = Uri.parse(subtitleUrl);
      final missingSubtitleGrant = await client.getUrl(
        subtitleUri.replace(query: ''),
      );
      final missingSubtitleResponse = await missingSubtitleGrant.close();
      await missingSubtitleResponse.drain<void>();
      expect(missingSubtitleResponse.statusCode, HttpStatus.notFound);
      final subtitleRequest = await client.getUrl(subtitleUri);
      final subtitleResponse = await subtitleRequest.close();
      final subtitleText = await utf8.decoder.bind(subtitleResponse).join();
      expect(subtitleResponse.statusCode, HttpStatus.ok);
      expect(subtitleText, contains('WEBVTT'));
      expect(subtitleText, contains('Hello TV'));

      await server.revokeDevice(deviceId);
      final revokedMediaRequest = await client.getUrl(playbackUri);
      final revokedMediaResponse = await revokedMediaRequest.close();
      await revokedMediaResponse.drain<void>();
      expect(revokedMediaResponse.statusCode, HttpStatus.unauthorized);
      final revokedSubtitleRequest = await client.getUrl(subtitleUri);
      final revokedSubtitleResponse = await revokedSubtitleRequest.close();
      await revokedSubtitleResponse.drain<void>();
      expect(revokedSubtitleResponse.statusCode, HttpStatus.unauthorized);
      final revoked = await _request(
        client,
        baseUri.resolve('playlists'),
        token: token,
      );
      expect(revoked.statusCode, HttpStatus.unauthorized);
    },
  );
}

class _CachedSubtitleService extends OpenSubtitlesService {
  _CachedSubtitleService(this.subtitle);

  final CachedSubtitle subtitle;

  @override
  Future<CachedSubtitle?> cachedForKey(String contentKey) async => subtitle;
}

Future<({int statusCode, Map<String, dynamic> body})> _request(
  HttpClient client,
  Uri uri, {
  String method = 'GET',
  String? token,
  Map<String, Object?>? body,
}) async {
  final request = await client.openUrl(method, uri);
  if (token != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  }
  if (body != null) {
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
  }
  final response = await request.close();
  final text = await utf8.decoder.bind(response).join();
  return (
    statusCode: response.statusCode,
    body: text.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(text) as Map),
  );
}
