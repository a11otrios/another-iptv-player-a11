import 'package:another_iptv_player/controllers/iptv_controller.dart';
import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/models/api_configuration_model.dart';
import 'package:another_iptv_player/models/api_response.dart';
import 'package:another_iptv_player/models/category.dart';
import 'package:another_iptv_player/models/category_type.dart';
import 'package:another_iptv_player/models/live_stream.dart';
import 'package:another_iptv_player/models/series.dart';
import 'package:another_iptv_player/models/server_info.dart';
import 'package:another_iptv_player/models/user_info.dart';
import 'package:another_iptv_player/models/vod_streams.dart';
import 'package:another_iptv_player/repositories/iptv_repository.dart';
import 'package:another_iptv_player/services/service_locator.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first load reuses and caches prevalidated player info', () async {
    final database = AppDatabase(NativeDatabase.memory());
    getIt.registerSingleton<AppDatabase>(database);
    addTearDown(() async {
      await getIt.reset();
      await database.close();
    });

    final repository = _FakeIptvRepository();
    final controller = IptvController(
      repository,
      false,
      initialPlayerInfo: _playerInfo('new-playlist'),
    );
    addTearDown(controller.dispose);

    final success = await controller.loadAllData();

    expect(success, isTrue);
    expect(repository.getPlayerInfoCalls, 0);
    expect(repository.cachePlayerInfoCalls, 1);
    expect(repository.cachedPlaylistId, 'new-playlist');
    expect(controller.userInfo?.playlistId, 'new-playlist');
  });

  test('rebinding player info updates all nested playlist IDs', () {
    final rebound = _playerInfo(
      'temporary-name',
    ).withPlaylistId('generated-id');

    expect(rebound.playlistId, 'generated-id');
    expect(rebound.userInfo.playlistId, 'generated-id');
    expect(rebound.serverInfo.playlistId, 'generated-id');
  });
}

ApiResponse _playerInfo(String playlistId) {
  return ApiResponse(
    playlistId: playlistId,
    userInfo: UserInfo(
      playlistId: playlistId,
      username: 'user',
      password: 'password',
      message: '',
      auth: 1,
      status: 'Active',
      expDate: '',
      isTrial: '0',
      activeCons: '0',
      createdAt: '',
      maxConnections: '1',
      allowedOutputFormats: const ['ts'],
    ),
    serverInfo: ServerInfo(
      playlistId: playlistId,
      url: 'provider.invalid',
      port: '80',
      httpsPort: '443',
      serverProtocol: 'http',
      rtmpPort: '',
      timezone: 'UTC',
      timestampNow: 0,
      timeNow: '',
    ),
  );
}

class _FakeIptvRepository extends IptvRepository {
  _FakeIptvRepository()
    : super(
        const ApiConfig(
          baseUrl: 'https://provider.invalid',
          username: 'user',
          password: 'password',
        ),
        'new-playlist',
      );

  int getPlayerInfoCalls = 0;
  int cachePlayerInfoCalls = 0;
  String? cachedPlaylistId;

  @override
  Future<ApiResponse?> getPlayerInfo({
    bool forceRefresh = false,
    bool cacheResult = true,
  }) async {
    getPlayerInfoCalls++;
    return null;
  }

  @override
  Future<void> cachePlayerInfo(ApiResponse response) async {
    cachePlayerInfoCalls++;
    cachedPlaylistId = response.playlistId;
  }

  @override
  Future<Map<CategoryType, List<Category>>?> getAllCategories({
    bool forceRefresh = false,
  }) async {
    return {
      CategoryType.live: [],
      CategoryType.vod: [],
      CategoryType.series: [],
    };
  }

  @override
  Future<List<LiveStream>?> getLiveChannelsFromApi({
    String? categoryId,
    bool forceRefresh = false,
  }) async {
    return [];
  }

  @override
  Future<List<VodStream>?> getMoviesFromApi({
    String? categoryId,
    bool forceRefresh = false,
    int? top,
  }) async {
    return [];
  }

  @override
  Future<List<SeriesStream>?> getSeriesFromApi({
    String? categoryId,
    bool forceRefresh = false,
    int? top,
  }) async {
    return [];
  }
}
