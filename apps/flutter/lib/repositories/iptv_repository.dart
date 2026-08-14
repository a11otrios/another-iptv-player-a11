import 'dart:convert';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/models/api_configuration_model.dart';
import 'package:another_iptv_player/models/api_response.dart';
import 'package:another_iptv_player/models/category.dart';
import 'package:another_iptv_player/models/epg_program.dart';
import 'package:another_iptv_player/models/live_stream.dart';
import 'package:another_iptv_player/models/series_response.dart';
import 'package:another_iptv_player/models/vod_streams.dart';
import 'package:another_iptv_player/models/series.dart';
import 'package:another_iptv_player/utils/type_convertions.dart';
import '../models/category_type.dart';
import 'user_preferences.dart';
import '../services/service_locator.dart';
import '../services/xmltv_guide_service.dart';
import '../utils/radio_station_filter.dart';

typedef IptvHttpGet =
    Future<http.Response> Function(Uri uri, {Map<String, String>? headers});

class IptvRepository {
  final ApiConfig _config;
  final String _playlistId;
  final IptvHttpGet _httpGet;
  AppDatabase get _database => getIt<AppDatabase>();

  IptvRepository(this._config, this._playlistId, {IptvHttpGet? httpGet})
    : _httpGet = httpGet ?? http.get;

  Future<http.Response> _makeRequest(
    String endpoint, {
    Map<String, String>? additionalParams,
    bool cacheBuster = false, // only add timestamp when true
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final params = Map<String, String>.from(_config.baseParams);
    if (additionalParams != null) {
      params.addAll(additionalParams);
    }

    if (cacheBuster) {
      params['_t'] = DateTime.now().millisecondsSinceEpoch.toString();
    }

    final uri = Uri.parse(
      '${_config.baseUrl}/$endpoint',
    ).replace(queryParameters: params);

    final requestUri = kIsWeb
        ? Uri.parse(
            '/__proxy',
          ).replace(queryParameters: {'url': uri.toString()})
        : uri;

    return await _httpGet(
      requestUri,
      headers: {'Content-Type': 'application/json'},
    ).timeout(timeout);
  }

  Future<ApiResponse?> getPlayerInfo({
    bool forceRefresh = false,
    bool cacheResult = true,
  }) async {
    try {
      if (!forceRefresh) {
        var userInfo = await _database.getUserInfoByPlaylistId(_playlistId);
        var serverInfo = await _database.getServerInfoByPlaylistId(_playlistId);

        if (userInfo != null && serverInfo != null) {
          return ApiResponse(
            userInfo: userInfo,
            serverInfo: serverInfo,
            playlistId: _playlistId,
          );
        }
      }

      final response = await _makeRequest(
        'player_api.php',
        cacheBuster: false,
        timeout: const Duration(seconds: 30),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        var apiResponse = ApiResponse.fromJson(jsonData, _playlistId);

        if (cacheResult) {
          await cachePlayerInfo(apiResponse);
        }

        return apiResponse;
      } else {
        throw Exception(
          'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      debugPrint('Player Info Error: $e');
      return null;
    }
  }

  Future<void> cachePlayerInfo(ApiResponse response) async {
    final boundResponse = response.playlistId == _playlistId
        ? response
        : response.withPlaylistId(_playlistId);
    await _database.insertOrUpdateUserInfo(boundResponse.userInfo);
    await _database.insertOrUpdateServerInfo(boundResponse.serverInfo);
  }

  Future<List<LiveStream>?> getLiveChannelsFromApi({
    String? categoryId,
    bool forceRefresh = false,
  }) async {
    try {
      final additionalParams = <String, String>{'action': 'get_live_streams'};

      if (categoryId != null) {
        additionalParams['category_id'] = categoryId;
      }

      final response = await _makeRequest(
        'player_api.php',
        additionalParams: additionalParams,
        cacheBuster: true,
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = json.decode(response.body);
        var liveStreams = jsonData
            .map((json) => LiveStream.fromJson(json, _playlistId))
            .toList();

        await _database.deleteLiveStreamsByPlaylistId(_playlistId);
        await _database.insertLiveStreams(liveStreams);
        return liveStreams;
      } else {
        throw Exception(
          'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      debugPrint('Live Channels Error: $e');
      return null;
    }
  }

  Future<List<LiveStream>?> getLiveChannels({
    String? categoryId,
    bool forceRefresh = false,
  }) async {
    try {
      var liveStreams = await _database.getLiveStreams(_playlistId);

      if (liveStreams.isNotEmpty) {
        final hideRadio = await UserPreferences.getHideRadioStations(
          playlistId: _playlistId,
        );
        return hideRadio
            ? liveStreams
                  .where((stream) => !isLikelyRadioStation(stream.name))
                  .toList()
            : liveStreams;
      }
    } catch (e) {
      debugPrint('Live Channels Error: $e');
      return null;
    }
    return null;
  }

  Future<List<LiveStream>?> getLiveChannelsByCategoryId({
    required String categoryId,
    bool forceRefresh = false,
    int? top,
  }) async {
    try {
      var liveStreams = await _database.getLiveStreamsByCategoryId(
        _playlistId,
        categoryId,
        top: top,
      );

      if (liveStreams.isNotEmpty) {
        return liveStreams;
      }
    } catch (e) {
      debugPrint('Live Channels Error: $e');
      return null;
    }
    return null;
  }

  Future<LiveStream?> findLiveStreamById(String streamId) async {
    try {
      var liveStream = await _database.findLiveStreamById(
        streamId,
        _playlistId,
      );
      return liveStream;
    } catch (e) {
      debugPrint('Live Channels Error: $e');
      return null;
    }
  }

  Future<List<EpgProgram>?> getShortEpg(
    String streamId, {
    int limit = 2,
  }) async {
    List<EpgProgram> providerPrograms = const [];
    try {
      var listings = await _getEpgListings(
        streamId,
        action: 'get_short_epg',
        limit: limit,
      );

      if (listings.isEmpty) {
        listings = await _getEpgListings(
          streamId,
          action: 'get_simple_data_table',
        );
      }

      final programs =
          listings
              .whereType<Map>()
              .map(
                (item) =>
                    EpgProgram.fromXtreamJson(Map<String, dynamic>.from(item)),
              )
              .where((program) => program.title.isNotEmpty)
              .toList()
            ..sort((a, b) {
              final left = a.startTime;
              final right = b.startTime;
              if (left == null && right == null) return 0;
              if (left == null) return 1;
              if (right == null) return -1;
              return left.compareTo(right);
            });

      final now = DateTime.now();
      final relevant = programs.where((program) {
        if (program.nowPlaying || program.isAiringAt(now)) return true;
        final start = program.startTime;
        if (start != null) return start.isAfter(now);
        return program.endTime == null;
      });

      providerPrograms = relevant.take(limit).toList();
    } catch (e) {
      debugPrint('Short EPG Error: $e');
    }

    if (providerPrograms.isNotEmpty) return providerPrograms;
    return _getXmltvFallback(streamId, limit: limit);
  }

  Future<List<EpgProgram>?> _getXmltvFallback(
    String streamId, {
    required int limit,
  }) async {
    try {
      final source = await UserPreferences.getXmltvFallbackSource(_playlistId);
      if (source == null) return const [];
      final stream = await findLiveStreamById(streamId);
      if (stream == null) return const [];
      return XmltvGuideService.instance.programsFor(
        source: source,
        channelId: stream.epgChannelId,
        channelName: stream.name,
        limit: limit,
      );
    } catch (e) {
      debugPrint('XMLTV fallback error: $e');
      return const [];
    }
  }

  Future<List<dynamic>> _getEpgListings(
    String streamId, {
    required String action,
    int? limit,
  }) async {
    final params = <String, String>{
      'action': action,
      'stream_id': streamId,
      if (limit != null) 'limit': limit.toString(),
    };
    final response = await _makeRequest(
      'player_api.php',
      additionalParams: params,
      cacheBuster: true,
      timeout: const Duration(seconds: 20),
    );

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
    }

    final jsonData = json.decode(response.body);
    final listings = jsonData is Map ? jsonData['epg_listings'] : null;
    return listings is List ? listings : const [];
  }

  Future<List<VodStream>?> getMoviesFromApi({
    String? categoryId,
    bool forceRefresh = false,
    int? top,
  }) async {
    try {
      final additionalParams = <String, String>{'action': 'get_vod_streams'};

      if (categoryId != null) {
        additionalParams['category_id'] = categoryId;
      }

      final response = await _makeRequest(
        'player_api.php',
        additionalParams: additionalParams,
        cacheBuster: true,
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = json.decode(response.body);
        var vodStreams = jsonData
            .map((json) => VodStream.fromJson(json, _playlistId))
            .toList();

        await _database.deleteVodStreamsByPlaylistId(_playlistId);
        await _database.insertVodStreams(vodStreams);

        return vodStreams;
      } else {
        throw Exception(
          'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      debugPrint('Movies Error: $e');
      return null;
    }
  }

  Future<List<VodStream>?> getMovies({
    String? categoryId,
    bool forceRefresh = false,
    int? top,
  }) async {
    try {
      if (categoryId != null) {
        var vodStreams = await _database.getVodStreamsByCategoryAndPlaylistId(
          categoryId: categoryId,
          playlistId: _playlistId,
          top: top,
        );

        if (vodStreams.isNotEmpty) {
          return vodStreams;
        }
      } else {
        var vodStreams = await _database.getVodStreamsByPlaylistId(_playlistId);

        if (vodStreams.isNotEmpty) {
          return vodStreams;
        }
      }
    } catch (e) {
      debugPrint('Movies Error: $e');
      return null;
    }
    return null;
  }

  Future<List<SeriesStream>?> getSeriesFromApi({
    String? categoryId,
    bool forceRefresh = false,
    int? top,
  }) async {
    try {
      final additionalParams = <String, String>{'action': 'get_series'};

      if (categoryId != null) {
        additionalParams['category_id'] = categoryId;
      }

      final response = await _makeRequest(
        'player_api.php',
        additionalParams: additionalParams,
        cacheBuster: true,
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = json.decode(response.body);
        var series = jsonData
            .map((json) => SeriesStream.fromJson(json, _playlistId))
            .toList();

        await _database.deleteSeriesStreamsByPlaylistId(_playlistId);
        await _database.insertSeriesStreams(series);

        return series;
      } else {
        throw Exception(
          'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      debugPrint('Series Error: $e');
      return null;
    }
  }

  Future<List<SeriesStream>?> getSeries({
    String? categoryId,
    bool forceRefresh = false,
    int? top,
  }) async {
    try {
      if (categoryId != null) {
        var series = await _database.getSeriesStreamsByCategoryAndPlaylistId(
          categoryId: categoryId,
          playlistId: _playlistId,
          top: top,
        );

        if (series.isNotEmpty) {
          return series;
        }
      } else {
        var series = await _database.getSeriesStreamsByPlaylistId(_playlistId);

        if (series.isNotEmpty) {
          return series;
        }
      }
    } catch (e) {
      debugPrint('Series Error: $e');
      return null;
    }
    return null;
  }

  /// Fetch VOD movie info from API
  Future<Map<String, dynamic>?> getVodInfo(String vodId) async {
    try {
      final response = await _makeRequest(
        'player_api.php',
        additionalParams: {'action': 'get_vod_info', 'vod_id': vodId},
        cacheBuster: true,
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        if (jsonData is Map<String, dynamic>) {
          return jsonData;
        } else if (jsonData is Map) {
          return Map<String, dynamic>.from(jsonData);
        }
        return null;
      } else {
        throw Exception(
          'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      debugPrint('VOD Info Error: $e');
      return null;
    }
  }

  Future<List<Category>?> getLiveCategories({bool forceRefresh = false}) async {
    return _getCategories(
      CategoryType.live,
      'get_live_categories',
      forceRefresh,
    );
  }

  Future<List<Category>?> getVodCategories({bool forceRefresh = false}) async {
    return _getCategories(CategoryType.vod, 'get_vod_categories', forceRefresh);
  }

  Future<List<Category>?> getSeriesCategories({
    bool forceRefresh = false,
  }) async {
    return _getCategories(
      CategoryType.series,
      'get_series_categories',
      forceRefresh,
    );
  }

  Future<List<Category>?> _getCategories(
    CategoryType type,
    String action,
    bool forceRefresh,
  ) async {
    try {
      if (!forceRefresh) {
        final cachedCategories = await _database.getCategoriesByTypeAndPlaylist(
          _playlistId,
          type,
        );
        if (cachedCategories.isNotEmpty) {
          return _orderedCategories(cachedCategories, type);
        }
      }

      final additionalParams = <String, String>{'action': action};

      final response = await _makeRequest(
        'player_api.php',
        additionalParams: additionalParams,
        cacheBuster: true,
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = json.decode(response.body);
        final categories = jsonData
            .map((json) => Category.fromJson(json, _playlistId, type))
            .toList();

        await _database.deleteCategoriesByTypeAndPlaylist(_playlistId, type);
        await _database.insertCategories(categories);

        return _orderedCategories(categories, type);
      } else {
        throw Exception(
          'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      debugPrint('${type.value} Categories Error: $e');
      // Hata durumunda cache'den dön
      final cachedCategories = await _database.getCategoriesByTypeAndPlaylist(
        _playlistId,
        type,
      );
      return cachedCategories.isNotEmpty
          ? _orderedCategories(cachedCategories, type)
          : null;
    }
  }

  Future<List<Category>> _orderedCategories(
    List<Category> categories,
    CategoryType type,
  ) async {
    final hideRadio =
        type == CategoryType.live &&
        await UserPreferences.getHideRadioStations(playlistId: _playlistId);
    final visibleCategories = hideRadio
        ? categories
              .where(
                (category) => !isLikelyRadioStation('', category.categoryName),
              )
              .toList()
        : categories;
    await UserPreferences.syncCategoryOriginalOrder(
      playlistId: _playlistId,
      type: type,
      categoryIds: categories.map((category) => category.categoryId),
    );
    final order = await UserPreferences.getCategoryOrder(
      playlistId: _playlistId,
      type: type,
    );
    return UserPreferences.applyCategoryOrder(
      visibleCategories,
      order,
      (category) => category.categoryId,
    );
  }

  Future<Map<CategoryType, List<Category>>?> getAllCategories({
    bool forceRefresh = false,
  }) async {
    try {
      final results = await Future.wait([
        getLiveCategories(forceRefresh: forceRefresh),
        getVodCategories(forceRefresh: forceRefresh),
        getSeriesCategories(forceRefresh: forceRefresh),
      ]);

      return {
        CategoryType.live: results[0] ?? [],
        CategoryType.vod: results[1] ?? [],
        CategoryType.series: results[2] ?? [],
      };
    } catch (e) {
      debugPrint('Get All Categories Error: $e');
      return await _database.getAllCategoriesByPlaylist(_playlistId);
    }
  }

  Future<void> clearCategoriesCache({CategoryType? type}) async {
    if (type != null) {
      await _database.deleteCategoriesByTypeAndPlaylist(_playlistId, type);
    } else {
      await _database.deleteAllCategoriesByPlaylist(_playlistId);
    }
  }

  Future<List<Category>> searchCategories(
    CategoryType type,
    String query,
  ) async {
    return await _database.searchCategories(_playlistId, type, query);
  }

  Future<List<LiveStream>> searchLiveStreams(String query) async {
    final streams = await _database.searchLiveStreams(_playlistId, query);
    final hideRadio = await UserPreferences.getHideRadioStations(
      playlistId: _playlistId,
    );
    return hideRadio
        ? streams.where((stream) => !isLikelyRadioStation(stream.name)).toList()
        : streams;
  }

  Future<List<VodStream>> searchMovies(String query) async {
    return await _database.searchMovie(_playlistId, query);
  }

  Future<List<SeriesStream>> searchSeries(String query) async {
    return await _database.searchSeries(_playlistId, query);
  }

  Future<SeriesDetailResponse?> getSeriesInfo(
    String seriesId, {
    bool forceRefresh = false,
  }) async {
    try {
      // --- SMART CACHE: check cached series + lastModified + episodes presence ---
      if (!forceRefresh) {
        final seriesInfo = await _database.getSeriesInfo(seriesId, _playlistId);

        if (seriesInfo != null) {
          // fetch main list to compare lastModified
          final allSeries = await _database.getSeriesStreamsByPlaylistId(
            _playlistId,
          );

          bool isStale = false;
          try {
            final seriesItem = allSeries.firstWhere(
              (s) => s.seriesId == seriesId,
            );

            final cachedLast = (seriesItem.lastModified ?? '')
                .toString()
                .trim();
            final infoLast = (seriesInfo.lastModified ?? '').toString().trim();

            if (cachedLast.isEmpty ||
                infoLast.isEmpty ||
                cachedLast != infoLast) {
              isStale = true;
            }
          } catch (e) {
            // series not found in list -> conservative: treat as stale
            isStale = true;
          }

          if (!isStale) {
            final seasons = await _database.getSeasonsBySeriesId(
              seriesId,
              _playlistId,
            );
            final episodes = await _database.getEpisodesBySeriesId(
              seriesId,
              _playlistId,
            );

            if (seasons.isNotEmpty && episodes.isNotEmpty) {
              return SeriesDetailResponse(
                seriesInfo: seriesInfo,
                seasons: seasons,
                episodes: episodes,
                playlistId: _playlistId,
              );
            }
          }
        }
      }

      final response = await _makeRequest(
        'player_api.php',
        additionalParams: {'action': 'get_series_info', 'series_id': seriesId},
        cacheBuster: true,
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);

        await _saveSeriesDataToDatabase(seriesId, jsonData);

        final seriesInfo = await _database.getSeriesInfo(seriesId, _playlistId);
        final seasons = await _database.getSeasonsBySeriesId(
          seriesId,
          _playlistId,
        );
        final episodes = await _database.getEpisodesBySeriesId(
          seriesId,
          _playlistId,
        );

        return SeriesDetailResponse(
          seriesInfo: seriesInfo!,
          seasons: seasons,
          episodes: episodes,
          playlistId: _playlistId,
        );
      } else {
        throw Exception(
          'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      debugPrint('Series Info Error: $e');
      return null;
    }
  }

  Future<List<EpisodesData>> getSeriesEpisodesBySeason(
    String seriesId,
    int seasonNumber, {
    bool forceRefresh = false,
  }) async {
    try {
      if (!forceRefresh) {
        final episodes = await _database.getEpisodesBySeason(
          seriesId,
          seasonNumber,
          _playlistId,
        );
        if (episodes.isNotEmpty) {
          return episodes;
        }
      }

      // Eğer episodlar yok ise series info'yu çek
      await getSeriesInfo(seriesId, forceRefresh: true);

      return await _database.getEpisodesBySeason(
        seriesId,
        seasonNumber,
        _playlistId,
      );
    } catch (e) {
      debugPrint('Get Episodes By Season Error: $e');
      return [];
    }
  }

  Future<void> _saveSeriesDataToDatabase(
    String seriesId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _database.clearSeriesData(seriesId, _playlistId);

      final info = data['info'];
      if (info != null) {
        final seriesInfoCompanion = SeriesInfosCompanion(
          seriesId: drift.Value(seriesId),
          playlistId: drift.Value(_playlistId),
          name: drift.Value(safeString(info['name'])),
          cover: drift.Value(safeString(info['cover'])),
          plot: drift.Value(safeString(info['plot'])),
          cast: drift.Value(safeString(info['cast'])),
          director: drift.Value(safeString(info['director'])),
          genre: drift.Value(safeString(info['genre'])),
          releaseDate: drift.Value(safeString(info['releaseDate'])),
          lastModified: drift.Value(safeString(info['last_modified'])),
          rating: drift.Value(safeString(info['rating'])),
          rating5based: drift.Value(safeInt(info['rating_5based'])),
          backdropPath: drift.Value(
            getFirstBackdropPath(info['backdrop_path']),
          ),
          youtubeTrailer: drift.Value(safeString(info['youtube_trailer'])),
          episodeRunTime: drift.Value(safeString(info['episode_run_time'])),
          categoryId: drift.Value(safeString(info['category_id'])),
        );

        await _database.insertSeriesInfo(seriesInfoCompanion);
      }

      final seasons = data['seasons'];
      if (seasons is List && seasons.isNotEmpty) {
        for (final season in seasons) {
          final seasonCompanion = SeasonsCompanion(
            seriesId: drift.Value(seriesId),
            playlistId: drift.Value(_playlistId),
            airDate: drift.Value(safeString(season['air_date'])),
            episodeCount: drift.Value(safeInt(season['episode_count'])),
            seasonId: drift.Value(safeInt(season['id'])),
            name: drift.Value(safeString(season['name'])),
            overview: drift.Value(safeString(season['overview'])),
            seasonNumber: drift.Value(safeInt(season['season_number'])),
            voteAverage: drift.Value(safeInt(season['vote_average'])),
            cover: drift.Value(safeString(season['cover'])),
            coverBig: drift.Value(safeString(season['cover_big'])),
          );

          await _database.insertSeason(seasonCompanion);
        }
      }

      final episodes = data['episodes'];
      Set<int> seasonNumbersFromEpisodes = {};

      if (episodes is Map<String, dynamic>) {
        for (final seasonKey in episodes.keys) {
          final seasonEpisodes = episodes[seasonKey];

          if (seasonEpisodes is List) {
            for (final episode in seasonEpisodes) {
              dynamic info = episode['info'];

              // Get season number from episodes, fallback to seasonKey if needed
              int seasonNumber = safeInt(episode['season']);
              if (seasonNumber == 0) {
                seasonNumber = safeInt(seasonKey);
              }
              if (seasonNumber == 0) {
                seasonNumber = 1;
              }
              seasonNumbersFromEpisodes.add(seasonNumber);

              final episodeCompanion = EpisodesCompanion(
                seriesId: drift.Value(seriesId),
                playlistId: drift.Value(_playlistId),
                episodeId: drift.Value(safeString(episode['id'])),
                episodeNum: drift.Value(safeInt(episode['episode_num'])),
                title: drift.Value(safeString(episode['title'])),
                containerExtension: drift.Value(
                  safeString(episode['container_extension']),
                ),
                season: drift.Value(seasonNumber),
                customSid: drift.Value(safeString(episode['custom_sid'])),
                added: drift.Value(safeString(episode['added'])),
                directSource: drift.Value(safeString(episode['direct_source'])),

                tmdbId: drift.Value(
                  safeInt(info is Map ? info['tmdb_id'] : null),
                ),
                releasedate: drift.Value(
                  safeString(info is Map ? info['releasedate'] : null),
                ),
                plot: drift.Value(
                  safeString(info is Map ? info['plot'] : null),
                ),
                durationSecs: drift.Value(
                  safeInt(info is Map ? info['duration_secs'] : null),
                ),
                duration: drift.Value(
                  safeString(info is Map ? info['duration'] : null),
                ),
                movieImage: drift.Value(
                  safeString(info is Map ? info['movie_image'] : null),
                ),
                bitrate: drift.Value(
                  safeInt(info is Map ? info['bitrate'] : null),
                ),
                rating: drift.Value(
                  safeDouble(info is Map ? info['rating'] : null),
                ),
              );

              try {
                await _database.insertEpisode(episodeCompanion);
              } catch (e) {
                debugPrint(
                  'Error inserting episode ${episode['id']} for series $seriesId: $e',
                );
              }
            }
          }
        }
      }

      // Compare season numbers from episodes with existing seasons
      // Create missing seasons
      if (seasonNumbersFromEpisodes.isNotEmpty) {
        // Get existing seasons
        final existingSeasons = await _database.getSeasonsBySeriesId(
          seriesId,
          _playlistId,
        );
        final existingSeasonNumbers = existingSeasons
            .map((s) => s.seasonNumber)
            .toSet();

        // Compare season numbers from episodes with existing seasons
        for (final seasonNumber in seasonNumbersFromEpisodes) {
          if (!existingSeasonNumbers.contains(seasonNumber)) {
            // Calculate episode count for this season
            int episodeCount = 0;
            if (episodes is Map<String, dynamic>) {
              for (final seasonKey in episodes.keys) {
                final seasonEpisodes = episodes[seasonKey];
                if (seasonEpisodes is List) {
                  for (final episode in seasonEpisodes) {
                    var epSeason = safeInt(episode['season']);
                    if (epSeason == 0) {
                      epSeason = safeInt(seasonKey);
                    }
                    if (epSeason == 0) {
                      epSeason = 1;
                    }
                    if (epSeason == seasonNumber) {
                      episodeCount++;
                    }
                  }
                }
              }
            }

            final seasonCompanion = SeasonsCompanion(
              seriesId: drift.Value(seriesId),
              playlistId: drift.Value(_playlistId),
              airDate: drift.Value(null),
              episodeCount: drift.Value(episodeCount),
              seasonId: drift.Value(0),
              name: drift.Value('$seasonNumber'),
              overview: drift.Value(null),
              seasonNumber: drift.Value(seasonNumber),
              voteAverage: drift.Value(null),
              cover: drift.Value(null),
              coverBig: drift.Value(null),
            );

            await _database.insertSeason(seasonCompanion);
            debugPrint(
              'Created missing season: $seasonNumber with $episodeCount episodes',
            );
          }
        }
      }

      debugPrint('Series data saved to database successfully');
    } catch (e) {
      debugPrint('Save series data to database error: $e');
      rethrow;
    }
  }
}
