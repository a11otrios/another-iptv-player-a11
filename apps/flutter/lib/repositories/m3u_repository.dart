import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/models/category.dart';
import 'package:another_iptv_player/models/category_type.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/live_stream.dart';
import 'package:another_iptv_player/models/m3u_series.dart';
import 'package:another_iptv_player/services/app_state.dart';
import 'package:another_iptv_player/repositories/user_preferences.dart';

import '../models/m3u_item.dart';
import '../models/series.dart';
import '../models/vod_streams.dart';
import '../services/service_locator.dart';
import '../utils/radio_station_filter.dart';

class M3uRepository {
  final String _playlistId = AppState.currentPlaylist!.id;
  final _database = getIt<AppDatabase>();

  M3uRepository();

  Future<List<Category>?> getCategories() async {
    final categories = await _database.getCategoriesByPlaylist(_playlistId);
    final result = <Category>[];
    final hideRadio = await UserPreferences.getHideRadioStations(
      playlistId: _playlistId,
    );
    for (final type in CategoryType.values) {
      final originalTypeCategories = categories
          .where((category) => category.type == type)
          .toList();
      final typeCategories = hideRadio && type == CategoryType.live
          ? originalTypeCategories.where(
              (category) => !isLikelyRadioStation('', category.categoryName),
            )
          : originalTypeCategories;
      await UserPreferences.syncCategoryOriginalOrder(
        playlistId: _playlistId,
        type: type,
        categoryIds: originalTypeCategories.map(
          (category) => category.categoryId,
        ),
      );
      final order = await UserPreferences.getCategoryOrder(
        playlistId: _playlistId,
        type: type,
      );
      result.addAll(
        UserPreferences.applyCategoryOrder(
          typeCategories,
          order,
          (category) => category.categoryId,
        ),
      );
    }
    return result;
  }

  Future<List<M3uItem>?> getM3uItemsByCategoryId({
    required String categoryId,
    int? top,
    ContentType? contentType,
  }) async {
    var liveStreams = await _database.getM3uItemsByCategoryId(
      _playlistId,
      categoryId,
      top: top,
      contentType: contentType,
    );

    if (liveStreams.isNotEmpty) {
      return _filterRadioItems(liveStreams);
    }
    return null;
  }

  Future<M3uItem?> getM3uItemById({required String id}) async {
    var m3uItem = await _database.getM3uItemsByIdAndPlaylist(_playlistId, id);
    return m3uItem;
  }

  Future<M3uItem?> getM3uItemByUrl({required String url}) async {
    var m3uItem = await _database.getM3uItemsByUrlAndPlaylist(_playlistId, url);
    return m3uItem;
  }

  Future<List<M3uItem>?> getM3uItems({
    int? top,
    ContentType? contentType,
  }) async {
    var liveStreams = await _database.getM3uItemsByPlaylist(_playlistId);

    if (liveStreams.isNotEmpty) {
      return _filterRadioItems(liveStreams);
    }
    return null;
  }

  Future<List<M3uItem>> _filterRadioItems(List<M3uItem> items) async {
    final hideRadio = await UserPreferences.getHideRadioStations(
      playlistId: _playlistId,
    );
    if (!hideRadio) return items;
    return items
        .where(
          (item) =>
              item.contentType != ContentType.liveStream ||
              !isLikelyRadioStation(item.name ?? '', item.groupTitle),
        )
        .toList();
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

  Future<List<M3uSerie>?> getSeriesByCategoryId({
    required String categoryId,
    int? top,
  }) async {
    var liveStreams = await _database.getM3uSeriesByCategoryId(
      _playlistId,
      categoryId,
      top: top,
    );

    if (liveStreams.isNotEmpty) {
      return liveStreams;
    }
    return null;
  }

  Future<List<M3uEpisode>?> getM3uEpisodesBySeriesId({
    required String seriesId,
  }) async {
    var episodes = await _database.getM3uEpisodesBySeriesId(
      _playlistId,
      seriesId,
    );

    if (episodes.isNotEmpty) {
      return episodes;
    }
    return null;
  }
}
