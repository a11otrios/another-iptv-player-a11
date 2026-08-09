import 'dart:convert';

import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/models/category_type.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/favorite.dart';
import 'package:another_iptv_player/models/playlist_model.dart';
import 'package:another_iptv_player/models/watch_history.dart';
import 'package:another_iptv_player/models/api_configuration_model.dart';
import 'package:another_iptv_player/repositories/iptv_repository.dart';
import 'package:another_iptv_player/repositories/user_preferences.dart';
import 'package:another_iptv_player/services/watch_history_service.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:another_iptv_player/utils/radio_station_filter.dart';

class LanApiException implements Exception {
  const LanApiException(this.statusCode, this.code, this.message);

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => message;
}

class LanPlaybackDescriptor {
  const LanPlaybackDescriptor({
    required this.url,
    required this.mimeType,
    required this.isLive,
    this.headers = const {},
    this.startPositionMs = 0,
  });

  final String url;
  final String mimeType;
  final bool isLive;
  final Map<String, String> headers;
  final int startPositionMs;
}

class _ItemSnapshot {
  const _ItemSnapshot(this.createdAt, this.items);

  final DateTime createdAt;
  final List<Map<String, Object?>> items;
}

/// Database-facing boundary for the LAN API. Provider credentials and source
/// URLs are converted to playback descriptors only; library responses never
/// expose them.
class LanLibraryService {
  LanLibraryService(this.database) : _history = WatchHistoryService(database);

  final AppDatabase database;
  final WatchHistoryService _history;
  final Uuid _uuid = const Uuid();
  final Map<String, _ItemSnapshot> _itemSnapshots = {};

  static const _itemSnapshotLifetime = Duration(seconds: 30);

  Future<List<Map<String, Object?>>> playlists() async {
    final rows = await database.getAllPlaylists();
    return Future.wait(
      rows.map((playlist) async {
        final categories = await database.getCategoriesByPlaylist(playlist.id);
        return <String, Object?>{
          'id': playlist.id,
          'name': playlist.name,
          'type': playlist.type.name,
          'createdAt': playlist.createdAt.toUtc().toIso8601String(),
          'counts': <String, int>{
            for (final type in CategoryType.values)
              type.value: categories.where((item) => item.type == type).length,
          },
        };
      }),
    );
  }

  Future<List<Map<String, Object?>>> categories({
    required String playlistId,
    required ContentType contentType,
  }) async {
    final hidden = (await UserPreferences.getHiddenCategories(
      playlistId: playlistId,
    )).toSet();
    final categoryType = ContentType.toCategoryType(contentType);
    final hideRadio =
        contentType == ContentType.liveStream &&
        await UserPreferences.getHideRadioStations(playlistId: playlistId);
    final rows = await database.getCategoriesByTypeAndPlaylist(
      playlistId,
      categoryType,
    );
    await UserPreferences.syncCategoryOriginalOrder(
      playlistId: playlistId,
      type: categoryType,
      categoryIds: rows.map((category) => category.categoryId),
    );
    final order = await UserPreferences.getCategoryOrder(
      playlistId: playlistId,
      type: categoryType,
    );
    final orderedRows = UserPreferences.applyCategoryOrder(
      rows,
      order,
      (category) => category.categoryId,
    );
    return orderedRows.map((category) {
      final typedKey = UserPreferences.hiddenCategoryKey(
        categoryType,
        category.categoryId,
      );
      return <String, Object?>{
        'id': category.categoryId,
        'name': category.categoryName,
        'type': category.type.value,
        'parentId': category.parentId,
        'hidden':
            hidden.contains(typedKey) ||
            hidden.contains(category.categoryId) ||
            (hideRadio && isLikelyRadioStation('', category.categoryName)),
      };
    }).toList();
  }

  Future<Map<String, Object?>> items({
    required String playlistId,
    required ContentType contentType,
    String? itemId,
    String? categoryId,
    String query = '',
    String sort = '',
    int offset = 0,
    int limit = 100,
  }) async {
    final playlist = await _requirePlaylist(playlistId);
    final normalizedQuery = query.trim().toLowerCase();
    final all = <Map<String, Object?>>[];
    final categoryType = ContentType.toCategoryType(contentType);
    final hideRadio =
        contentType == ContentType.liveStream &&
        await UserPreferences.getHideRadioStations(playlistId: playlistId);
    final hiddenCategories = (await UserPreferences.getHiddenCategories(
      playlistId: playlistId,
    )).toSet();
    final hiddenKey = hiddenCategories.toList()..sort();
    final radioCategoryIds = hideRadio
        ? (await database.getCategoriesByTypeAndPlaylist(
                playlistId,
                categoryType,
              ))
              .where(
                (category) => isLikelyRadioStation('', category.categoryName),
              )
              .map((category) => category.categoryId)
              .toSet()
        : const <String>{};
    final cacheKey = jsonEncode(<Object?>[
      playlistId,
      contentType.index,
      itemId,
      categoryId,
      normalizedQuery,
      sort,
      hiddenKey,
      hideRadio,
    ]);
    final now = DateTime.now();
    _itemSnapshots.removeWhere(
      (_, snapshot) =>
          now.difference(snapshot.createdAt) > _itemSnapshotLifetime,
    );
    final cached = _itemSnapshots[cacheKey];
    if (cached != null) {
      return _pageItems(cached.items, offset: offset, limit: limit);
    }

    bool isHiddenCategory(Object? value) {
      final id = value?.toString();
      if (id == null || id.isEmpty) return false;
      return hiddenCategories.contains(id) ||
          radioCategoryIds.contains(id) ||
          hiddenCategories.contains(
            UserPreferences.hiddenCategoryKey(categoryType, id),
          );
    }

    if (playlist.type == PlaylistType.xtream) {
      switch (contentType) {
        case ContentType.liveStream:
          final rows = categoryId == null
              ? await database.getLiveStreams(playlistId)
              : await database.getLiveStreamsByCategoryId(
                  playlistId,
                  categoryId,
                );
          all.addAll(
            rows.map(
              (item) => <String, Object?>{
                'id': item.streamId,
                'playlistId': playlistId,
                'type': 'live',
                'name': item.name,
                'imageUrl': item.streamIcon,
                'categoryId': item.categoryId,
                'epgChannelId': item.epgChannelId,
                'isLive': true,
              },
            ),
          );
          break;
        case ContentType.vod:
          final rows = categoryId == null
              ? await database.getVodStreamsByPlaylistId(playlistId)
              : await database.getVodStreamsByCategoryAndPlaylistId(
                  playlistId: playlistId,
                  categoryId: categoryId,
                );
          all.addAll(
            rows.map(
              (item) => <String, Object?>{
                'id': item.streamId,
                'playlistId': playlistId,
                'type': 'vod',
                'name': item.name,
                'imageUrl': item.streamIcon,
                'categoryId': item.categoryId,
                'rating': item.rating,
                'genre': item.genre,
                'containerExtension': item.containerExtension,
                'createdAt': item.createdAt == null
                    ? null
                    : (item.createdAt!.millisecondsSinceEpoch ~/ 1000)
                          .toString(),
                'isLive': false,
              },
            ),
          );
          break;
        case ContentType.series:
          final rows = categoryId == null
              ? await database.getSeriesStreamsByPlaylistId(playlistId)
              : await database.getSeriesStreamsByCategoryAndPlaylistId(
                  playlistId: playlistId,
                  categoryId: categoryId,
                );
          all.addAll(
            rows.map(
              (item) => <String, Object?>{
                'id': item.seriesId,
                'playlistId': playlistId,
                'type': 'series',
                'name': item.name,
                'imageUrl': item.cover,
                'categoryId': item.categoryId,
                'rating': item.rating,
                'genre': item.genre,
                'plot': item.plot,
                'releaseDate': item.releaseDate,
                'lastModified': item.lastModified,
                'isLive': false,
              },
            ),
          );
          break;
      }
    } else if (contentType == ContentType.series) {
      final rows = categoryId == null
          ? await database.getM3uSeriesByPlaylistId(playlistId)
          : await database.getM3uSeriesByCategoryId(playlistId, categoryId);
      all.addAll(
        rows.map(
          (item) => <String, Object?>{
            'id': item.seriesId,
            'playlistId': playlistId,
            'type': 'series',
            'name': item.name,
            'imageUrl': item.cover,
            'categoryId': item.categoryId,
            'isLive': false,
          },
        ),
      );
    } else {
      final rows = categoryId == null
          ? await database.getM3uItemsByPlaylist(playlistId)
          : await database.getM3uItemsByCategoryId(
              playlistId,
              categoryId,
              contentType: contentType,
            );
      all.addAll(
        rows
            .where((item) => item.contentType == contentType)
            .map(
              (item) => <String, Object?>{
                'id': item.id,
                'playlistId': playlistId,
                'type': _wireType(contentType),
                'name': item.name ?? item.tvgName ?? 'Untitled',
                'imageUrl': item.tvgLogo,
                'categoryId': item.categoryId,
                'epgChannelId': item.tvgId,
                'isLive': contentType == ContentType.liveStream,
              },
            ),
      );
    }

    final visible = all
        .where(
          (item) =>
              !isHiddenCategory(item['categoryId']) &&
              (!hideRadio ||
                  !isLikelyRadioStation(item['name']?.toString() ?? '')),
        )
        .toList();
    final matchingItem = itemId == null
        ? visible
        : visible.where((item) => item['id']?.toString() == itemId).toList();
    final categoryNames = normalizedQuery.isEmpty
        ? const <String, String>{}
        : <String, String>{
            for (final category in await categories(
              playlistId: playlistId,
              contentType: contentType,
            ))
              if (category['hidden'] != true)
                category['id'].toString(): (category['name'] as String? ?? '')
                    .toLowerCase(),
          };
    final filtered = normalizedQuery.isEmpty
        ? matchingItem
        : matchingItem.where((item) {
            final name = (item['name'] as String? ?? '').toLowerCase();
            final categoryName =
                categoryNames[item['categoryId']?.toString()] ?? '';
            return name.contains(normalizedQuery) ||
                categoryName.contains(normalizedQuery);
          }).toList();
    final sorted = filtered.toList();
    switch (sort) {
      case 'ascending':
        sorted.sort(
          (a, b) => (a['name']?.toString().toLowerCase() ?? '').compareTo(
            b['name']?.toString().toLowerCase() ?? '',
          ),
        );
        break;
      case 'descending':
        sorted.sort(
          (a, b) => (b['name']?.toString().toLowerCase() ?? '').compareTo(
            a['name']?.toString().toLowerCase() ?? '',
          ),
        );
        break;
      case 'release':
        sorted.sort((a, b) => _releaseSort(b).compareTo(_releaseSort(a)));
        break;
      case 'rating':
        sorted.sort(
          (a, b) => (double.tryParse(b['rating']?.toString() ?? '') ?? 0)
              .compareTo(double.tryParse(a['rating']?.toString() ?? '') ?? 0),
        );
        break;
    }
    _itemSnapshots[cacheKey] = _ItemSnapshot(now, sorted);
    return _pageItems(sorted, offset: offset, limit: limit);
  }

  int _releaseSort(Map<String, Object?> item) {
    for (final key in const ['createdAt', 'lastModified']) {
      final parsed = int.tryParse(item[key]?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return DateTime.tryParse(
          item['releaseDate']?.toString() ?? '',
        )?.millisecondsSinceEpoch ??
        0;
  }

  Future<List<Map<String, Object?>>> shelves({
    required String playlistId,
    required ContentType contentType,
    int limit = 30,
  }) async {
    final safeLimit = limit.clamp(1, 100);
    final visibleCategories = (await categories(
      playlistId: playlistId,
      contentType: contentType,
    )).where((category) => category['hidden'] != true).toList();
    final categoriesById = <String, Map<String, Object?>>{
      for (final category in visibleCategories)
        if (category['id'] != null) category['id'].toString(): category,
    };
    final totals = <String, int>{};
    final samples = <String, List<Object?>>{};
    var offset = 0;
    while (true) {
      final page = await items(
        playlistId: playlistId,
        contentType: contentType,
        offset: offset,
        limit: 1000,
      );
      final pageItems = page['items'] as List;
      for (final value in pageItems) {
        if (value is! Map) continue;
        final categoryId = value['categoryId']?.toString();
        if (categoryId == null || !categoriesById.containsKey(categoryId)) {
          continue;
        }
        totals[categoryId] = (totals[categoryId] ?? 0) + 1;
        final sample = samples.putIfAbsent(categoryId, () => <Object?>[]);
        if (sample.length < safeLimit) sample.add(value);
      }
      if (page['hasMore'] != true || pageItems.isEmpty) break;
      offset += pageItems.length;
    }
    return visibleCategories
        .where((category) => (totals[category['id']?.toString()] ?? 0) > 0)
        .map((category) {
          final id = category['id'].toString();
          return <String, Object?>{
            'category': category,
            'items': samples[id] ?? const <Object?>[],
            'total': totals[id] ?? 0,
          };
        })
        .toList();
  }

  Future<Map<String, Object?>?> item({
    required String playlistId,
    required ContentType contentType,
    required String itemId,
  }) async {
    final playlist = await _requirePlaylist(playlistId);
    final categoryType = ContentType.toCategoryType(contentType);
    final hiddenCategories = (await UserPreferences.getHiddenCategories(
      playlistId: playlistId,
    )).toSet();
    bool isHidden(Object? categoryId) {
      final id = categoryId?.toString();
      if (id == null || id.isEmpty) return false;
      return hiddenCategories.contains(id) ||
          hiddenCategories.contains(
            UserPreferences.hiddenCategoryKey(categoryType, id),
          );
    }

    if (playlist.type == PlaylistType.m3u) {
      final value = await database.getM3uItemsByIdAndPlaylist(
        playlistId,
        itemId,
      );
      if (value == null) return null;
      if (isHidden(value.categoryId)) return null;
      return <String, Object?>{
        'id': value.id,
        'playlistId': playlistId,
        'type': _wireType(contentType),
        'name': value.name ?? value.tvgName ?? 'Untitled',
        'imageUrl': value.tvgLogo,
        'categoryId': value.categoryId,
        'epgChannelId': value.tvgId,
        'isLive': contentType == ContentType.liveStream,
      };
    }
    switch (contentType) {
      case ContentType.liveStream:
        final value = await database.findLiveStreamById(itemId, playlistId);
        if (value == null) return null;
        if (isHidden(value.categoryId)) return null;
        return <String, Object?>{
          'id': value.streamId,
          'playlistId': playlistId,
          'type': 'live',
          'name': value.name,
          'imageUrl': value.streamIcon,
          'categoryId': value.categoryId,
          'epgChannelId': value.epgChannelId,
          'isLive': true,
        };
      case ContentType.vod:
        final value = await database.findMovieById(itemId, playlistId);
        if (value == null) return null;
        if (isHidden(value.categoryId)) return null;
        return <String, Object?>{
          'id': value.streamId,
          'playlistId': playlistId,
          'type': 'vod',
          'name': value.name,
          'imageUrl': value.streamIcon,
          'categoryId': value.categoryId,
          'rating': value.rating,
          'genre': value.genre,
          'containerExtension': value.containerExtension,
          'createdAt': value.createdAt == null
              ? null
              : (value.createdAt!.millisecondsSinceEpoch ~/ 1000).toString(),
          'isLive': false,
        };
      case ContentType.series:
        final value = await database.findSeriesById(itemId, playlistId);
        if (value == null) return null;
        if (isHidden(value.categoryId)) return null;
        return <String, Object?>{
          'id': value.seriesId,
          'playlistId': playlistId,
          'type': 'series',
          'name': value.name,
          'imageUrl': value.cover,
          'categoryId': value.categoryId,
          'rating': value.rating,
          'genre': value.genre,
          'plot': value.plot,
          'releaseDate': value.releaseDate,
          'lastModified': value.lastModified,
          'isLive': false,
        };
    }
  }

  Map<String, Object?> _pageItems(
    List<Map<String, Object?>> items, {
    required int offset,
    required int limit,
  }) {
    final safeOffset = offset.clamp(0, items.length);
    final safeLimit = limit.clamp(1, 1000);
    final end = (safeOffset + safeLimit).clamp(safeOffset, items.length);
    return <String, Object?>{
      'items': items.sublist(safeOffset, end),
      'offset': safeOffset,
      'limit': safeLimit,
      'total': items.length,
      'hasMore': end < items.length,
    };
  }

  Future<Map<String, Object?>> seriesDetails({
    required String playlistId,
    required String seriesId,
  }) async {
    final playlist = await _requirePlaylist(playlistId);
    if (playlist.type == PlaylistType.m3u) {
      final series = await database.findM3uSeriesById(playlistId, seriesId);
      if (series == null) {
        throw const LanApiException(404, 'not_found', 'Series not found');
      }
      final episodes = await database.getM3uEpisodesBySeriesId(
        playlistId,
        seriesId,
      );
      return <String, Object?>{
        'id': series.seriesId,
        'name': series.name,
        'imageUrl': series.cover,
        'seasons': _groupEpisodes(
          episodes.map(
            (episode) => <String, Object?>{
              'id': '${episode.seasonNumber}:${episode.episodeNumber}',
              'title': episode.name,
              'seasonNumber': episode.seasonNumber,
              'episodeNumber': episode.episodeNumber,
              'imageUrl': episode.cover,
            },
          ),
        ),
      };
    }

    final series = await database.findSeriesById(seriesId, playlistId);
    if (series == null) {
      throw const LanApiException(404, 'not_found', 'Series not found');
    }
    var episodes = await database.getEpisodesBySeriesId(seriesId, playlistId);
    if (episodes.isEmpty) {
      final repository = IptvRepository(
        ApiConfig(
          baseUrl: playlist.url ?? '',
          username: playlist.username ?? '',
          password: playlist.password ?? '',
        ),
        playlistId,
      );
      final details = await repository.getSeriesInfo(
        seriesId,
        forceRefresh: true,
      );
      episodes =
          details?.episodes ??
          await database.getEpisodesBySeriesId(seriesId, playlistId);
    }
    return <String, Object?>{
      'id': series.seriesId,
      'name': series.name,
      'imageUrl': series.cover,
      'plot': series.plot,
      'cast': series.cast,
      'director': series.director,
      'genre': series.genre,
      'rating': series.rating,
      'releaseDate': series.releaseDate,
      'seasons': _groupEpisodes(
        episodes.map(
          (episode) => <String, Object?>{
            'id': episode.episodeId,
            'title': episode.title,
            'seasonNumber': episode.season,
            'episodeNumber': episode.episodeNum,
            'containerExtension': episode.containerExtension,
            'plot': episode.plot,
            'durationMs': episode.durationSecs == null
                ? null
                : episode.durationSecs! * 1000,
            'imageUrl': episode.movieImage,
          },
        ),
      ),
    };
  }

  Future<Map<String, Object?>> vodDetails({
    required String playlistId,
    required String vodId,
  }) async {
    final playlist = await _requirePlaylist(playlistId);
    if (playlist.type != PlaylistType.xtream) return const {};
    final repository = IptvRepository(
      ApiConfig(
        baseUrl: playlist.url ?? '',
        username: playlist.username ?? '',
        password: playlist.password ?? '',
      ),
      playlistId,
    );
    final raw = await repository.getVodInfo(vodId);
    if (raw == null) return const {};
    final info = _map(raw['info']);
    final movie = _map(raw['movie_data']);
    return <String, Object?>{
      'plot': info['plot'] ?? info['description'] ?? info['overview'],
      'cast': info['cast'],
      'director': info['director'],
      'genre': info['genre'],
      'releaseDate': info['releasedate'] ?? info['releaseDate'],
      'rating': info['rating'],
      'backdropPath': info['backdrop_path'],
      'youtubeTrailer': info['youtube_trailer'],
      'duration': info['duration'],
      'durationSecs': info['duration_secs'],
      'tmdbId': info['tmdb_id'],
      'containerExtension': movie['container_extension'],
    };
  }

  Future<List<Map<String, Object?>>> favorites({String? playlistId}) async {
    final rows = playlistId == null
        ? await database.getAllFavorites()
        : await database.getFavoritesByPlaylist(playlistId);
    return rows.map(_favoriteJson).toList();
  }

  Future<List<Map<String, Object?>>> epg({
    required String playlistId,
    required String streamId,
    int limit = 8,
  }) async {
    final playlist = await _requirePlaylist(playlistId);
    if (playlist.type != PlaylistType.xtream) return const [];
    final repository = IptvRepository(
      ApiConfig(
        baseUrl: playlist.url ?? '',
        username: playlist.username ?? '',
        password: playlist.password ?? '',
      ),
      playlistId,
    );
    final programs = await repository.getShortEpg(streamId, limit: limit);
    final now = DateTime.now();
    return (programs ?? const [])
        .map(
          (program) => <String, Object?>{
            'id': program.id,
            'title': program.title,
            'description': program.description,
            'startTime': program.startTime?.toUtc().toIso8601String(),
            'endTime': program.endTime?.toUtc().toIso8601String(),
            'nowPlaying': program.nowPlaying || program.isAiringAt(now),
          },
        )
        .toList();
  }

  Future<Map<String, Object?>> preferences(String playlistId) async {
    final textColor = await UserPreferences.getSubtitleTextColor();
    final backgroundColor = await UserPreferences.getSubtitleBackgroundColor();
    return <String, Object?>{
      'hiddenCategories': await UserPreferences.getHiddenCategories(
        playlistId: playlistId,
      ),
      'hideRadioStations': await UserPreferences.getHideRadioStations(
        playlistId: playlistId,
      ),
      'audioLanguage': await UserPreferences.getAudioTrack(),
      'subtitleLanguage': await UserPreferences.getSubtitleTrack(),
      'subtitleStyle': <String, Object?>{
        'fontSize': await UserPreferences.getSubtitleFontSize(),
        'lineHeight': await UserPreferences.getSubtitleHeight(),
        'letterSpacing': await UserPreferences.getSubtitleLetterSpacing(),
        'wordSpacing': await UserPreferences.getSubtitleWordSpacing(),
        'textColor': _cssColor(textColor.toARGB32()),
        'backgroundColor': _cssColor(backgroundColor.toARGB32()),
        'fontWeight': (await UserPreferences.getSubtitleFontWeight()).value,
        'textAlign': (await UserPreferences.getSubtitleTextAlign()).name,
        'padding': await UserPreferences.getSubtitlePadding(),
      },
    };
  }

  Future<Map<String, Object?>> patchPreferences(
    String playlistId,
    Map<String, Object?> values,
  ) async {
    await _requirePlaylist(playlistId);
    if (values.containsKey('hiddenCategories')) {
      final raw = values['hiddenCategories'];
      if (raw is! List || raw.any((item) => item is! String)) {
        throw const LanApiException(
          400,
          'invalid_preferences',
          'hiddenCategories must be a list of strings',
        );
      }
      await UserPreferences.setHiddenCategories(
        raw.cast<String>(),
        playlistId: playlistId,
      );
    }
    if (values.containsKey('hideRadioStations')) {
      final value = values['hideRadioStations'];
      if (value is! bool) {
        throw const LanApiException(
          400,
          'invalid_preferences',
          'hideRadioStations must be a boolean',
        );
      }
      await UserPreferences.setHideRadioStations(
        playlistId: playlistId,
        value: value,
      );
    }
    if (values.containsKey('audioLanguage')) {
      final language = values['audioLanguage'];
      if (language is! String) {
        throw const LanApiException(
          400,
          'invalid_preferences',
          'audioLanguage must be a string',
        );
      }
      await UserPreferences.setAudioTrack(language);
    }
    if (values.containsKey('subtitleLanguage')) {
      final language = values['subtitleLanguage'];
      if (language is! String) {
        throw const LanApiException(
          400,
          'invalid_preferences',
          'subtitleLanguage must be a string',
        );
      }
      await UserPreferences.setSubtitleTrack(language);
    }
    return preferences(playlistId);
  }

  Future<Map<String, Object?>> shortcuts(
    String playlistId, {
    String page = 'A',
  }) async {
    final normalizedPage = page.trim().toUpperCase();
    if (!const ['A', 'S', 'D', 'F', 'G'].contains(normalizedPage)) {
      throw const LanApiException(
        400,
        'invalid_shortcut_page',
        'Shortcut page must be one of A, S, D, F, or G',
      );
    }
    final preferences = await SharedPreferences.getInstance();
    final result = <String, Object?>{};
    final key = normalizedPage == 'A'
        ? 'channel_shortcuts_$playlistId'
        : 'channel_shortcuts_${playlistId}_$normalizedPage';
    final raw = preferences.getString(key);
    if (raw == null || raw.isEmpty) return result;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return result;
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        result[entry.key.toString()] = <String, Object?>{
          'itemId': value['m3uId'] ?? value['id'],
          'name': value['name'],
          'imageUrl': value['imagePath'],
        };
      }
    } catch (_) {}
    return result;
  }

  Future<Map<String, Object?>> putFavorite({
    required String playlistId,
    required ContentType contentType,
    required String itemId,
    required String name,
    String? imageUrl,
    String? m3uItemId,
  }) async {
    final existing = await database.getFavoritesByPlaylist(playlistId);
    for (final favorite in existing) {
      if (favorite.contentType == contentType && favorite.streamId == itemId) {
        return _favoriteJson(favorite);
      }
    }
    final now = DateTime.now().toUtc();
    final favorite = Favorite(
      id: _uuid.v4(),
      playlistId: playlistId,
      contentType: contentType,
      streamId: itemId,
      m3uItemId: m3uItemId,
      name: name,
      imagePath: imageUrl,
      createdAt: now,
      updatedAt: now,
    );
    await database.insertFavorite(favorite);
    return _favoriteJson(favorite);
  }

  Future<void> deleteFavorite({
    required String playlistId,
    required ContentType contentType,
    required String itemId,
  }) async {
    final rows = await database.getFavoritesByPlaylist(playlistId);
    for (final favorite in rows) {
      if (favorite.contentType == contentType && favorite.streamId == itemId) {
        await database.deleteFavorite(favorite.id);
      }
    }
  }

  Future<List<Map<String, Object?>>> history({
    required String playlistId,
  }) async {
    final rows = await _history.getWatchHistoryByPlaylist(playlistId);
    return rows.map(_historyJson).toList();
  }

  Future<Map<String, Object?>> putHistory({
    required String playlistId,
    required ContentType contentType,
    required String itemId,
    required String title,
    String? seriesId,
    String? imageUrl,
    int positionMs = 0,
    int durationMs = 0,
  }) async {
    final history = WatchHistory(
      playlistId: playlistId,
      contentType: contentType,
      streamId: itemId,
      seriesId: seriesId,
      watchDuration: Duration(milliseconds: positionMs.clamp(0, 1 << 53)),
      totalDuration: Duration(milliseconds: durationMs.clamp(0, 1 << 53)),
      lastWatched: DateTime.now().toUtc(),
      imagePath: imageUrl,
      title: title,
    );
    await _history.saveWatchHistory(history);
    return _historyJson(history);
  }

  Future<void> deleteHistory({
    required String playlistId,
    required String itemId,
  }) {
    return _history.deleteWatchHistory(playlistId, itemId);
  }

  Future<void> clearHistory(String playlistId) async {
    await _requirePlaylist(playlistId);
    await _history.deletePlaylistHistory(playlistId);
  }

  Future<LanPlaybackDescriptor> playback({
    required String playlistId,
    required ContentType contentType,
    required String itemId,
    String? episodeId,
  }) async {
    final playlist = await _requirePlaylist(playlistId);
    final history = await _history.getWatchHistory(
      playlistId,
      episodeId ?? itemId,
    );

    if (playlist.type == PlaylistType.m3u) {
      if (contentType == ContentType.series) {
        final parts = (episodeId ?? '').split(':');
        if (parts.length != 2) {
          throw const LanApiException(
            400,
            'invalid_episode',
            'Episode identity is required',
          );
        }
        final episodes = await database.getM3uEpisodesBySeriesId(
          playlistId,
          itemId,
        );
        final episode = episodes
            .where(
              (entry) =>
                  entry.seasonNumber.toString() == parts[0] &&
                  entry.episodeNumber.toString() == parts[1],
            )
            .firstOrNull;
        if (episode == null) {
          throw const LanApiException(404, 'not_found', 'Episode not found');
        }
        return LanPlaybackDescriptor(
          url: episode.url,
          mimeType: _mimeForUrl(episode.url),
          isLive: false,
          startPositionMs: history?.watchDuration?.inMilliseconds ?? 0,
        );
      }
      final item = await database.getM3uItemsByIdAndPlaylist(
        playlistId,
        itemId,
      );
      if (item == null) {
        throw const LanApiException(404, 'not_found', 'Item not found');
      }
      final headers = <String, String>{
        if ((item.userAgent ?? '').isNotEmpty) 'User-Agent': item.userAgent!,
        if ((item.referrer ?? '').isNotEmpty) 'Referer': item.referrer!,
      };
      return LanPlaybackDescriptor(
        url: item.url,
        mimeType: _mimeForUrl(item.url),
        isLive: contentType == ContentType.liveStream,
        headers: headers,
        startPositionMs: history?.watchDuration?.inMilliseconds ?? 0,
      );
    }

    final baseUrl = (playlist.url ?? '').replaceAll(RegExp(r'/+$'), '');
    final username = Uri.encodeComponent(playlist.username ?? '');
    final password = Uri.encodeComponent(playlist.password ?? '');
    if (baseUrl.isEmpty || username.isEmpty || password.isEmpty) {
      throw const LanApiException(
        409,
        'playlist_incomplete',
        'Playlist credentials are incomplete',
      );
    }
    switch (contentType) {
      case ContentType.liveStream:
        return LanPlaybackDescriptor(
          url: '$baseUrl/live/$username/$password/$itemId.ts',
          mimeType: 'video/mp2t',
          isLive: true,
        );
      case ContentType.vod:
        final movie = await database.findMovieById(itemId, playlistId);
        if (movie == null) {
          throw const LanApiException(404, 'not_found', 'Movie not found');
        }
        final ext = movie.containerExtension.isEmpty
            ? 'mp4'
            : movie.containerExtension;
        return LanPlaybackDescriptor(
          url: '$baseUrl/movie/$username/$password/$itemId.$ext',
          mimeType: _mimeForExtension(ext),
          isLive: false,
          startPositionMs: history?.watchDuration?.inMilliseconds ?? 0,
        );
      case ContentType.series:
        final targetEpisodeId = episodeId ?? itemId;
        final episode = await database.findEpisodesById(
          targetEpisodeId,
          playlistId,
        );
        if (episode == null) {
          throw const LanApiException(404, 'not_found', 'Episode not found');
        }
        final ext = (episode.containerExtension ?? '').isEmpty
            ? 'mp4'
            : episode.containerExtension!;
        return LanPlaybackDescriptor(
          url: '$baseUrl/series/$username/$password/$targetEpisodeId.$ext',
          mimeType: _mimeForExtension(ext),
          isLive: false,
          startPositionMs: history?.watchDuration?.inMilliseconds ?? 0,
        );
    }
  }

  Future<Playlist> _requirePlaylist(String playlistId) async {
    final playlist = await database.getPlaylistById(playlistId);
    if (playlist == null) {
      throw const LanApiException(
        404,
        'playlist_not_found',
        'Playlist not found',
      );
    }
    return playlist;
  }
}

ContentType contentTypeFromWire(String value) {
  switch (value) {
    case 'live':
      return ContentType.liveStream;
    case 'vod':
      return ContentType.vod;
    case 'series':
      return ContentType.series;
    default:
      throw const LanApiException(
        400,
        'invalid_type',
        'Content type must be live, vod, or series',
      );
  }
}

String _wireType(ContentType type) {
  switch (type) {
    case ContentType.liveStream:
      return 'live';
    case ContentType.vod:
      return 'vod';
    case ContentType.series:
      return 'series';
  }
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : const <String, Object?>{};

Map<String, Object?> _favoriteJson(Favorite favorite) => <String, Object?>{
  'id': favorite.id,
  'playlistId': favorite.playlistId,
  'type': _wireType(favorite.contentType),
  'itemId': favorite.streamId,
  'm3uItemId': favorite.m3uItemId,
  'name': favorite.name,
  'imageUrl': favorite.imagePath,
  'createdAt': favorite.createdAt.toUtc().toIso8601String(),
  'updatedAt': favorite.updatedAt.toUtc().toIso8601String(),
};

Map<String, Object?> _historyJson(WatchHistory history) => <String, Object?>{
  'playlistId': history.playlistId,
  'type': _wireType(history.contentType),
  'itemId': history.streamId,
  'seriesId': history.seriesId,
  'title': history.title,
  'imageUrl': history.imagePath,
  'positionMs': history.watchDuration?.inMilliseconds ?? 0,
  'durationMs': history.totalDuration?.inMilliseconds ?? 0,
  'updatedAt': history.lastWatched.toUtc().toIso8601String(),
};

List<Map<String, Object?>> _groupEpisodes(
  Iterable<Map<String, Object?>> episodes,
) {
  final grouped = <int, List<Map<String, Object?>>>{};
  for (final episode in episodes) {
    final season = episode['seasonNumber'] as int? ?? 0;
    grouped.putIfAbsent(season, () => <Map<String, Object?>>[]).add(episode);
  }
  final seasons = grouped.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return seasons.map((entry) {
    entry.value.sort(
      (a, b) => (a['episodeNumber'] as int? ?? 0).compareTo(
        b['episodeNumber'] as int? ?? 0,
      ),
    );
    return <String, Object?>{
      'seasonNumber': entry.key,
      'episodes': entry.value,
    };
  }).toList();
}

String _mimeForUrl(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  final dot = path.lastIndexOf('.');
  return _mimeForExtension(dot < 0 ? '' : path.substring(dot + 1));
}

String _mimeForExtension(String extension) {
  switch (extension.toLowerCase()) {
    case 'm3u8':
      return 'application/vnd.apple.mpegurl';
    case 'ts':
    case 'm2ts':
      return 'video/mp2t';
    case 'mkv':
      return 'video/x-matroska';
    case 'webm':
      return 'video/webm';
    case 'avi':
      return 'video/x-msvideo';
    case 'mov':
      return 'video/quicktime';
    default:
      return 'video/mp4';
  }
}

String _cssColor(int argb) {
  final alpha = ((argb >> 24) & 0xff) / 255;
  final red = (argb >> 16) & 0xff;
  final green = (argb >> 8) & 0xff;
  final blue = argb & 0xff;
  return 'rgba($red, $green, $blue, ${alpha.toStringAsFixed(3)})';
}
