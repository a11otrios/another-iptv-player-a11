import 'dart:convert';

import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/models/category.dart';
import 'package:another_iptv_player/models/category_type.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/favorite.dart';
import 'package:another_iptv_player/models/live_stream.dart';
import 'package:another_iptv_player/models/m3u_item.dart';
import 'package:another_iptv_player/models/m3u_series.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/models/playlist_model.dart';
import 'package:another_iptv_player/models/series.dart';
import 'package:another_iptv_player/models/vod_streams.dart';
import 'package:another_iptv_player/repositories/user_preferences.dart';
import 'package:another_iptv_player/services/app_state.dart';
import 'package:another_iptv_player/services/channel_shortcut_service.dart';
import 'package:another_iptv_player/services/service_locator.dart';
import 'package:uuid/uuid.dart';

class PortablePlaylistTransferService {
  PortablePlaylistTransferService({
    AppDatabase? database,
    ChannelShortcutStore? shortcutStore,
  }) : _database = database ?? getIt<AppDatabase>(),
       _shortcutStore = shortcutStore ?? ChannelShortcutService();

  static const formatName = 'another-iptv-player-portable';
  static const formatVersion = 1;

  final AppDatabase _database;
  final ChannelShortcutStore _shortcutStore;
  final Uuid _uuid = const Uuid();

  Future<String> exportCurrentPlaylist() async {
    final playlist = _currentPlaylist;
    final categories = await _categoryNames(playlist.id);
    final favorites = await _database.getFavoritesByPlaylist(playlist.id);
    final hiddenCategories = await _hiddenCategoryEntries(playlist.id);
    final categoryOrder = await _categoryOrderEntries(playlist.id);
    final hideRadioStations = await UserPreferences.getHideRadioStations(
      playlistId: playlist.id,
    );

    final portableFavorites = <PortableTransferEntry>[];
    for (final favorite in favorites) {
      portableFavorites.add(
        await _entryFromFavorite(favorite, playlist, categories),
      );
    }

    final portableShortcutPages = <String, dynamic>{};
    for (final page in ChannelShortcutService.pages) {
      final shortcuts = await _shortcutStore.getShortcutsForPage(page);
      final portableShortcuts = <String, dynamic>{};
      for (final entry in shortcuts.entries) {
        portableShortcuts[entry.key.toString()] = _entryFromContentItem(
          entry.value,
          categories,
        ).toJson();
      }
      portableShortcutPages[page] = portableShortcuts;
    }
    final portableShortcuts =
        portableShortcutPages[ChannelShortcutService.defaultPage]
            as Map<String, dynamic>;

    return const JsonEncoder.withIndent('  ').convert({
      'format': formatName,
      'version': formatVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'sourcePlaylist': {
        'id': playlist.id,
        'name': playlist.name,
        'type': playlist.type.name,
      },
      'favorites': portableFavorites.map((entry) => entry.toJson()).toList(),
      'channelNumbers': portableShortcuts,
      'channelNumberPages': portableShortcutPages,
      'hiddenCategories': hiddenCategories
          .map((entry) => entry.toJson())
          .toList(),
      'categoryOrder': categoryOrder.map((entry) => entry.toJson()).toList(),
      'hideRadioStations': hideRadioStations,
    });
  }

  Future<PortableImportResult> importIntoCurrentPlaylist(String json) async {
    final playlist = _currentPlaylist;
    final backup = PortablePlaylistBackup.fromJsonString(json);
    final entries = [
      ...backup.favorites,
      for (final shortcuts in backup.channelNumberPages.values)
        ...shortcuts.values,
    ];
    final contentTypes = entries.map((entry) => entry.contentType).toSet();
    final catalog = await _loadCatalog(playlist, contentTypes);
    final matcher = PortablePlaylistMatcher(
      catalog.items.map((item) => item.candidate),
    );
    final samePlaylist = backup.sourcePlaylistId == playlist.id;
    final hiddenCategoriesImported = await _importHiddenCategories(
      playlist.id,
      backup.hiddenCategories,
    );
    final categoryOrderImported = await _importCategoryOrder(
      playlist.id,
      backup.categoryOrder,
    );
    if (backup.hideRadioStations != null) {
      await UserPreferences.setHideRadioStations(
        playlistId: playlist.id,
        value: backup.hideRadioStations!,
      );
    }

    var favoritesAdded = 0;
    var favoritesAlreadyPresent = 0;
    var channelNumbersAssigned = 0;
    final unmatched = <String>{};
    final ambiguous = <String>{};

    for (final entry in backup.favorites) {
      final match = matcher.match(entry, samePlaylist: samePlaylist);
      if (!match.isMatched) {
        _recordMiss(match, entry, unmatched, ambiguous);
        continue;
      }

      final contentItem = catalog.byKey[match.candidate!.key]!;
      final exists = await _database.isFavorite(
        playlist.id,
        contentItem.id,
        contentItem.contentType,
        null,
      );
      if (exists) {
        favoritesAlreadyPresent++;
        continue;
      }

      await _database.insertFavorite(
        Favorite(
          id: _uuid.v4(),
          playlistId: playlist.id,
          contentType: contentItem.contentType,
          streamId: contentItem.id,
          m3uItemId: contentItem.m3uItem?.id,
          name: contentItem.name,
          imagePath: contentItem.imagePath,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      favoritesAdded++;
    }

    for (final pageEntry in backup.channelNumberPages.entries) {
      final mergedShortcuts = await _shortcutStore.getShortcutsForPage(
        pageEntry.key,
      );
      var pageAssignments = 0;
      for (final entry in pageEntry.value.entries) {
        final match = matcher.match(entry.value, samePlaylist: samePlaylist);
        if (!match.isMatched) {
          _recordMiss(match, entry.value, unmatched, ambiguous);
          continue;
        }

        final contentItem = catalog.byKey[match.candidate!.key]!;
        if (contentItem.contentType != ContentType.liveStream) {
          unmatched.add(entry.value.name);
          continue;
        }

        mergedShortcuts[entry.key] = contentItem;
        pageAssignments++;
        channelNumbersAssigned++;
      }

      if (pageAssignments > 0) {
        await _shortcutStore.saveShortcutsForPage(
          pageEntry.key,
          mergedShortcuts,
        );
      }
    }

    return PortableImportResult(
      favoritesAdded: favoritesAdded,
      favoritesAlreadyPresent: favoritesAlreadyPresent,
      channelNumbersAssigned: channelNumbersAssigned,
      hiddenCategoriesImported: hiddenCategoriesImported,
      categoryOrderImported: categoryOrderImported,
      unmatchedNames: unmatched.toList()..sort(),
      ambiguousNames: ambiguous.toList()..sort(),
    );
  }

  Playlist get _currentPlaylist {
    final playlist = AppState.currentPlaylist;
    if (playlist == null) {
      throw StateError('No playlist is currently selected.');
    }
    return playlist;
  }

  Future<Map<String, String>> _categoryNames(String playlistId) async {
    final categories = await _database.getCategoriesByPlaylist(playlistId);
    return {
      for (final category in categories)
        _categoryKey(category.type, category.categoryId): category.categoryName,
    };
  }

  Future<List<PortableHiddenCategoryEntry>> _hiddenCategoryEntries(
    String playlistId,
  ) async {
    final hidden = await UserPreferences.getHiddenCategories(
      playlistId: playlistId,
    );
    if (hidden.isEmpty) return [];

    final categories = await _database.getCategoriesByPlaylist(playlistId);
    final byTypedKey = {
      for (final category in categories)
        UserPreferences.hiddenCategoryKey(category.type, category.categoryId):
            category,
    };
    final byId = <String, List<Category>>{};
    for (final category in categories) {
      (byId[category.categoryId] ??= []).add(category);
    }

    final entries = <PortableHiddenCategoryEntry>[];
    final seen = <String>{};
    for (final hiddenKey in hidden) {
      final typedCategory = byTypedKey[hiddenKey];
      if (typedCategory != null) {
        _addHiddenCategoryEntry(entries, seen, typedCategory);
        continue;
      }

      final legacyCategories = byId[hiddenKey] ?? const <Category>[];
      if (legacyCategories.isEmpty) {
        final key = '\u0000$hiddenKey';
        if (seen.add(key)) {
          entries.add(PortableHiddenCategoryEntry(categoryId: hiddenKey));
        }
        continue;
      }

      for (final category in legacyCategories) {
        _addHiddenCategoryEntry(entries, seen, category);
      }
    }
    return entries;
  }

  Future<List<PortableCategoryOrderEntry>> _categoryOrderEntries(
    String playlistId,
  ) async {
    final categories = await _database.getCategoriesByPlaylist(playlistId);
    final entries = <PortableCategoryOrderEntry>[];
    for (final type in CategoryType.values) {
      final typeCategories = categories
          .where((category) => category.type == type)
          .toList();
      await UserPreferences.syncCategoryOriginalOrder(
        playlistId: playlistId,
        type: type,
        categoryIds: typeCategories.map((category) => category.categoryId),
      );
      final savedOrder = await UserPreferences.getCategoryOrder(
        playlistId: playlistId,
        type: type,
      );
      final ordered = UserPreferences.applyCategoryOrder(
        typeCategories,
        savedOrder,
        (category) => category.categoryId,
      );
      for (final indexed in ordered.indexed) {
        entries.add(
          PortableCategoryOrderEntry(
            categoryId: indexed.$2.categoryId,
            categoryType: type,
            name: indexed.$2.categoryName,
            position: indexed.$1,
          ),
        );
      }
    }
    return entries;
  }

  void _addHiddenCategoryEntry(
    List<PortableHiddenCategoryEntry> entries,
    Set<String> seen,
    Category category,
  ) {
    final key = '${category.type.name}\u0000${category.categoryId}';
    if (!seen.add(key)) return;
    entries.add(
      PortableHiddenCategoryEntry(
        categoryId: category.categoryId,
        categoryType: category.type,
        name: category.categoryName,
      ),
    );
  }

  Future<int> _importHiddenCategories(
    String playlistId,
    List<PortableHiddenCategoryEntry> entries,
  ) async {
    if (entries.isEmpty) return 0;

    final categories = await _database.getCategoriesByPlaylist(playlistId);
    final byTypedId = {
      for (final category in categories)
        '${category.type.name}\u0000${category.categoryId}': category,
    };
    final byTypedName = <String, List<Category>>{};
    for (final category in categories) {
      final normalizedName = _normalizeCategoryName(category.categoryName);
      if (normalizedName.isEmpty) continue;
      (byTypedName['${category.type.name}\u0000$normalizedName'] ??= []).add(
        category,
      );
    }

    final hidden = (await UserPreferences.getHiddenCategories(
      playlistId: playlistId,
    )).toSet();
    final originalCount = hidden.length;

    for (final entry in entries) {
      final categoryType = entry.categoryType;
      if (categoryType == null) {
        hidden.add(entry.categoryId);
        continue;
      }

      final idMatch =
          byTypedId['${categoryType.name}\u0000${entry.categoryId}'];
      if (idMatch != null) {
        hidden.add(
          UserPreferences.hiddenCategoryKey(idMatch.type, idMatch.categoryId),
        );
        continue;
      }

      final normalizedName = _normalizeCategoryName(entry.name ?? '');
      final nameMatches = normalizedName.isEmpty
          ? const <Category>[]
          : byTypedName['${categoryType.name}\u0000$normalizedName'] ??
                const <Category>[];
      if (nameMatches.length == 1) {
        final match = nameMatches.single;
        hidden.add(
          UserPreferences.hiddenCategoryKey(match.type, match.categoryId),
        );
      }
    }

    await UserPreferences.setHiddenCategories(
      hidden.toList()..sort(),
      playlistId: playlistId,
    );
    return hidden.length - originalCount;
  }

  Future<int> _importCategoryOrder(
    String playlistId,
    List<PortableCategoryOrderEntry> entries,
  ) async {
    if (entries.isEmpty) return 0;

    final categories = await _database.getCategoriesByPlaylist(playlistId);
    var imported = 0;
    for (final type in CategoryType.values) {
      final target = categories
          .where((category) => category.type == type)
          .toList();
      if (target.isEmpty) continue;

      final byId = {
        for (final category in target) category.categoryId: category,
      };
      final byName = <String, List<Category>>{};
      for (final category in target) {
        final name = _normalizeCategoryName(category.categoryName);
        if (name.isNotEmpty) (byName[name] ??= []).add(category);
      }

      final source =
          entries.where((entry) => entry.categoryType == type).toList()..sort(
            (first, second) => first.position.compareTo(second.position),
          );
      final orderedIds = <String>[];
      final added = <String>{};
      for (final entry in source) {
        Category? match = byId[entry.categoryId];
        if (match == null) {
          final normalizedName = _normalizeCategoryName(entry.name);
          final nameMatches = byName[normalizedName] ?? const <Category>[];
          if (nameMatches.length == 1) match = nameMatches.single;
        }
        if (match != null && added.add(match.categoryId)) {
          orderedIds.add(match.categoryId);
          imported++;
        }
      }
      if (orderedIds.isEmpty) continue;
      orderedIds.addAll(
        target
            .map((category) => category.categoryId)
            .where((categoryId) => added.add(categoryId)),
      );
      await UserPreferences.setCategoryOrder(
        playlistId: playlistId,
        type: type,
        categoryIds: orderedIds,
      );
    }
    return imported;
  }

  Future<PortableTransferEntry> _entryFromFavorite(
    Favorite favorite,
    Playlist playlist,
    Map<String, String> categories,
  ) async {
    if (playlist.type == PlaylistType.xtream) {
      switch (favorite.contentType) {
        case ContentType.liveStream:
          final stream = await _database.findLiveStreamById(
            favorite.streamId,
            playlist.id,
          );
          if (stream != null) {
            return _entryFromLiveStream(stream, categories);
          }
        case ContentType.vod:
          final movie = await _database.findMovieById(
            favorite.streamId,
            playlist.id,
          );
          if (movie != null) {
            return _entryFromMovie(movie, categories);
          }
        case ContentType.series:
          final series = await _database.findSeriesById(
            favorite.streamId,
            playlist.id,
          );
          if (series != null) {
            return _entryFromSeries(series, categories);
          }
      }
    } else {
      final itemId = favorite.m3uItemId ?? favorite.streamId;
      final item = await _database.getM3uItemsByIdAndPlaylist(
        playlist.id,
        itemId,
      );
      if (item != null) {
        return _entryFromM3uItem(item);
      }

      if (favorite.contentType == ContentType.series) {
        final series = await _database.findM3uSeriesById(
          playlist.id,
          favorite.streamId,
        );
        if (series != null) {
          return _entryFromM3uSeries(series);
        }
      }
    }

    return PortableTransferEntry(
      name: favorite.name,
      contentType: favorite.contentType,
      sourceId: favorite.streamId,
      sourceM3uItemId: favorite.m3uItemId,
    );
  }

  PortableTransferEntry _entryFromContentItem(
    ContentItem item,
    Map<String, String> categories,
  ) {
    final liveStream = item.liveStream;
    final m3uItem = item.m3uItem;
    final categoryId =
        liveStream?.categoryId ??
        item.vodStream?.categoryId ??
        item.seriesStream?.categoryId;

    return PortableTransferEntry(
      name: item.name,
      contentType: item.contentType,
      sourceId: item.id,
      sourceM3uItemId: m3uItem?.id,
      guideId: _firstNonEmpty([
        liveStream?.epgChannelId,
        m3uItem?.tvgId,
        m3uItem?.tvgName,
      ]),
      groupName:
          m3uItem?.groupTitle ??
          (categoryId == null
              ? null
              : categories[_categoryKeyForContent(
                  item.contentType,
                  categoryId,
                )]),
    );
  }

  PortableTransferEntry _entryFromLiveStream(
    LiveStream stream,
    Map<String, String> categories,
  ) {
    return PortableTransferEntry(
      name: stream.name,
      contentType: ContentType.liveStream,
      sourceId: stream.streamId,
      guideId: _emptyToNull(stream.epgChannelId),
      groupName: categories[_categoryKey(CategoryType.live, stream.categoryId)],
    );
  }

  PortableTransferEntry _entryFromMovie(
    VodStream movie,
    Map<String, String> categories,
  ) {
    return PortableTransferEntry(
      name: movie.name,
      contentType: ContentType.vod,
      sourceId: movie.streamId,
      groupName: categories[_categoryKey(CategoryType.vod, movie.categoryId)],
    );
  }

  PortableTransferEntry _entryFromSeries(
    SeriesStream series,
    Map<String, String> categories,
  ) {
    return PortableTransferEntry(
      name: series.name,
      contentType: ContentType.series,
      sourceId: series.seriesId,
      groupName: series.categoryId == null
          ? null
          : categories[_categoryKey(CategoryType.series, series.categoryId!)],
    );
  }

  PortableTransferEntry _entryFromM3uItem(M3uItem item) {
    return PortableTransferEntry(
      name: item.name ?? '',
      contentType: item.contentType,
      sourceId: item.id,
      sourceM3uItemId: item.id,
      guideId: _firstNonEmpty([item.tvgId, item.tvgName]),
      groupName: item.groupTitle,
    );
  }

  PortableTransferEntry _entryFromM3uSeries(M3uSerie series) {
    return PortableTransferEntry(
      name: series.name,
      contentType: ContentType.series,
      sourceId: series.seriesId,
    );
  }

  Future<_PortableCatalog> _loadCatalog(
    Playlist playlist,
    Set<ContentType> contentTypes,
  ) async {
    final categories = await _categoryNames(playlist.id);
    final items = <_PortableCatalogItem>[];

    if (playlist.type == PlaylistType.xtream) {
      if (contentTypes.contains(ContentType.liveStream)) {
        final streams = await _database.getLiveStreams(playlist.id);
        items.addAll(
          streams.map(
            (stream) => _catalogItem(
              ContentItem(
                stream.streamId,
                stream.name,
                stream.streamIcon,
                ContentType.liveStream,
                liveStream: stream,
              ),
              guideId: stream.epgChannelId,
              groupName:
                  categories[_categoryKey(
                    CategoryType.live,
                    stream.categoryId,
                  )],
            ),
          ),
        );
      }

      if (contentTypes.contains(ContentType.vod)) {
        final movies = await _database.getVodStreamsByPlaylistId(playlist.id);
        items.addAll(
          movies.map(
            (movie) => _catalogItem(
              ContentItem(
                movie.streamId,
                movie.name,
                movie.streamIcon,
                ContentType.vod,
                containerExtension: movie.containerExtension,
                vodStream: movie,
              ),
              groupName:
                  categories[_categoryKey(CategoryType.vod, movie.categoryId)],
            ),
          ),
        );
      }

      if (contentTypes.contains(ContentType.series)) {
        final series = await _database.getSeriesStreamsByPlaylistId(
          playlist.id,
        );
        items.addAll(
          series.map(
            (item) => _catalogItem(
              ContentItem(
                item.seriesId,
                item.name,
                item.cover ?? '',
                ContentType.series,
                seriesStream: item,
              ),
              groupName: item.categoryId == null
                  ? null
                  : categories[_categoryKey(
                      CategoryType.series,
                      item.categoryId!,
                    )],
            ),
          ),
        );
      }
    } else {
      final m3uItems = await _database.getM3uItemsByPlaylist(playlist.id);
      items.addAll(
        m3uItems
            .where((item) => contentTypes.contains(item.contentType))
            .map(
              (item) => _catalogItem(
                ContentItem(
                  item.id,
                  item.name ?? '',
                  item.tvgLogo ?? '',
                  item.contentType,
                  m3uItem: item,
                ),
                guideId: _firstNonEmpty([item.tvgId, item.tvgName]),
                groupName: item.groupTitle,
              ),
            ),
      );

      if (contentTypes.contains(ContentType.series)) {
        final series = await _database.getM3uSeriesByPlaylistId(playlist.id);
        items.addAll(
          series.map(
            (item) => _catalogItem(
              ContentItem(
                item.seriesId,
                item.name,
                item.cover ?? '',
                ContentType.series,
              ),
            ),
          ),
        );
      }
    }

    return _PortableCatalog(items);
  }

  _PortableCatalogItem _catalogItem(
    ContentItem contentItem, {
    String? guideId,
    String? groupName,
  }) {
    final key = '${contentItem.contentType.name}\u0000${contentItem.id}';
    return _PortableCatalogItem(
      contentItem,
      PortableMatchCandidate(
        key: key,
        sourceId: contentItem.id,
        name: contentItem.name,
        contentType: contentItem.contentType,
        guideId: _emptyToNull(guideId),
        groupName: _emptyToNull(groupName),
      ),
    );
  }

  void _recordMiss(
    PortableMatchResult result,
    PortableTransferEntry entry,
    Set<String> unmatched,
    Set<String> ambiguous,
  ) {
    if (result.status == PortableMatchStatus.ambiguous) {
      ambiguous.add(entry.name);
    } else {
      unmatched.add(entry.name);
    }
  }

  static String _categoryKey(CategoryType type, String categoryId) {
    return '${type.name}\u0000$categoryId';
  }

  static String _categoryKeyForContent(ContentType type, String categoryId) {
    return _categoryKey(ContentType.toCategoryType(type), categoryId);
  }

  static String _normalizeCategoryName(String value) {
    final normalized = PortablePlaylistMatcher.normalizeName(value);
    if (normalized.isNotEmpty) return normalized;
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String? _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final normalized = _emptyToNull(value);
      if (normalized != null) return normalized;
    }
    return null;
  }

  static String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class PortablePlaylistBackup {
  const PortablePlaylistBackup({
    required this.sourcePlaylistId,
    required this.favorites,
    required this.channelNumberPages,
    required this.hiddenCategories,
    required this.categoryOrder,
    required this.hideRadioStations,
  });

  final String sourcePlaylistId;
  final List<PortableTransferEntry> favorites;
  final Map<String, Map<int, PortableTransferEntry>> channelNumberPages;
  final List<PortableHiddenCategoryEntry> hiddenCategories;
  final List<PortableCategoryOrderEntry> categoryOrder;
  final bool? hideRadioStations;

  factory PortablePlaylistBackup.fromJsonString(String input) {
    final decoded = jsonDecode(input);
    if (decoded is! Map) {
      throw const FormatException('The backup must contain a JSON object.');
    }
    final json = Map<String, dynamic>.from(decoded);
    if (json['format'] != PortablePlaylistTransferService.formatName ||
        json['version'] != PortablePlaylistTransferService.formatVersion) {
      throw const FormatException('Unsupported playlist backup format.');
    }

    final source = json['sourcePlaylist'];
    final sourceJson = source is Map
        ? Map<String, dynamic>.from(source)
        : const <String, dynamic>{};
    final favoriteJson = json['favorites'];
    final favorites = favoriteJson is List
        ? favoriteJson
              .whereType<Map>()
              .map(
                (entry) => PortableTransferEntry.fromJson(
                  Map<String, dynamic>.from(entry),
                ),
              )
              .where((entry) => entry.name.isNotEmpty)
              .take(10000)
              .toList()
        : <PortableTransferEntry>[];

    final shortcuts = _shortcutMapFromJson(json['channelNumbers']);
    final shortcutPages = <String, Map<int, PortableTransferEntry>>{};
    final shortcutPagesJson = json['channelNumberPages'];
    if (shortcutPagesJson is Map) {
      for (final entry in shortcutPagesJson.entries) {
        final page = entry.key.toString();
        if (!ChannelShortcutService.pages.contains(page)) continue;
        shortcutPages[page] = _shortcutMapFromJson(entry.value);
      }
    }
    if (shortcuts.isNotEmpty &&
        (shortcutPages[ChannelShortcutService.defaultPage]?.isEmpty ?? true)) {
      shortcutPages[ChannelShortcutService.defaultPage] = shortcuts;
    }
    for (final page in ChannelShortcutService.pages) {
      shortcutPages.putIfAbsent(page, () => <int, PortableTransferEntry>{});
    }
    final hiddenCategoryJson = json['hiddenCategories'];
    final hiddenCategories = hiddenCategoryJson is List
        ? hiddenCategoryJson
              .whereType<Map>()
              .map(
                (entry) => PortableHiddenCategoryEntry.fromJson(
                  Map<String, dynamic>.from(entry),
                ),
              )
              .where((entry) => entry.categoryId.isNotEmpty)
              .take(10000)
              .toList()
        : <PortableHiddenCategoryEntry>[];
    final categoryOrderJson = json['categoryOrder'];
    final categoryOrder = categoryOrderJson is List
        ? categoryOrderJson
              .whereType<Map>()
              .map(
                (entry) => PortableCategoryOrderEntry.fromJson(
                  Map<String, dynamic>.from(entry),
                ),
              )
              .where((entry) => entry.categoryId.isNotEmpty)
              .take(10000)
              .toList()
        : <PortableCategoryOrderEntry>[];

    return PortablePlaylistBackup(
      sourcePlaylistId: sourceJson['id'] as String? ?? '',
      favorites: favorites,
      channelNumberPages: shortcutPages,
      hiddenCategories: hiddenCategories,
      categoryOrder: categoryOrder,
      hideRadioStations: json['hideRadioStations'] is bool
          ? json['hideRadioStations'] as bool
          : null,
    );
  }

  static Map<int, PortableTransferEntry> _shortcutMapFromJson(dynamic input) {
    final shortcuts = <int, PortableTransferEntry>{};
    final shortcutJson = input;
    if (shortcutJson is Map) {
      for (final entry in shortcutJson.entries) {
        final number = int.tryParse(entry.key.toString());
        if (number == null || number < 0 || number > 9 || entry.value is! Map) {
          continue;
        }
        final portableEntry = PortableTransferEntry.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
        if (portableEntry.name.isNotEmpty &&
            portableEntry.contentType == ContentType.liveStream) {
          shortcuts[number] = portableEntry;
        }
      }
    }
    return shortcuts;
  }
}

class PortableCategoryOrderEntry {
  const PortableCategoryOrderEntry({
    required this.categoryId,
    required this.categoryType,
    required this.name,
    required this.position,
  });

  final String categoryId;
  final CategoryType categoryType;
  final String name;
  final int position;

  factory PortableCategoryOrderEntry.fromJson(Map<String, dynamic> json) {
    return PortableCategoryOrderEntry(
      categoryId: json['categoryId'] as String? ?? '',
      categoryType: CategoryType.fromString(json['type'] as String? ?? ''),
      name: json['name'] as String? ?? '',
      position: json['position'] is int ? json['position'] as int : 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'categoryId': categoryId,
    'type': categoryType.value,
    'name': name,
    'position': position,
  };
}

class PortableHiddenCategoryEntry {
  const PortableHiddenCategoryEntry({
    required this.categoryId,
    this.categoryType,
    this.name,
  });

  final String categoryId;
  final CategoryType? categoryType;
  final String? name;

  factory PortableHiddenCategoryEntry.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String?;
    CategoryType? categoryType;
    if (typeName != null && typeName.isNotEmpty) {
      categoryType = CategoryType.fromString(typeName);
    }

    return PortableHiddenCategoryEntry(
      categoryId: json['categoryId'] as String? ?? '',
      categoryType: categoryType,
      name: json['name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'categoryId': categoryId,
      if (categoryType != null) 'type': categoryType!.value,
      if (name != null && name!.isNotEmpty) 'name': name,
    };
  }
}

class PortableTransferEntry {
  const PortableTransferEntry({
    required this.name,
    required this.contentType,
    this.sourceId,
    this.sourceM3uItemId,
    this.guideId,
    this.groupName,
  });

  final String name;
  final ContentType contentType;
  final String? sourceId;
  final String? sourceM3uItemId;
  final String? guideId;
  final String? groupName;

  factory PortableTransferEntry.fromJson(Map<String, dynamic> json) {
    final contentTypeName = json['contentType'] as String? ?? '';
    final contentType = ContentType.values.where(
      (type) => type.name == contentTypeName,
    );
    if (contentType.isEmpty) {
      throw FormatException('Unknown content type: $contentTypeName');
    }

    return PortableTransferEntry(
      name: json['name'] as String? ?? '',
      contentType: contentType.first,
      sourceId: json['sourceId'] as String?,
      sourceM3uItemId: json['sourceM3uItemId'] as String?,
      guideId: json['guideId'] as String?,
      groupName: json['groupName'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'contentType': contentType.name,
      if (sourceId != null) 'sourceId': sourceId,
      if (sourceM3uItemId != null) 'sourceM3uItemId': sourceM3uItemId,
      if (guideId != null) 'guideId': guideId,
      if (groupName != null) 'groupName': groupName,
    };
  }
}

class PortableImportResult {
  const PortableImportResult({
    required this.favoritesAdded,
    required this.favoritesAlreadyPresent,
    required this.channelNumbersAssigned,
    required this.hiddenCategoriesImported,
    required this.categoryOrderImported,
    required this.unmatchedNames,
    required this.ambiguousNames,
  });

  final int favoritesAdded;
  final int favoritesAlreadyPresent;
  final int channelNumbersAssigned;
  final int hiddenCategoriesImported;
  final int categoryOrderImported;
  final List<String> unmatchedNames;
  final List<String> ambiguousNames;

  int get notImportedCount => unmatchedNames.length + ambiguousNames.length;
}

enum PortableMatchStatus { matched, notFound, ambiguous }

class PortableMatchResult {
  const PortableMatchResult(this.status, [this.candidate]);

  final PortableMatchStatus status;
  final PortableMatchCandidate? candidate;

  bool get isMatched =>
      status == PortableMatchStatus.matched && candidate != null;
}

class PortableMatchCandidate {
  const PortableMatchCandidate({
    required this.key,
    required this.sourceId,
    required this.name,
    required this.contentType,
    this.guideId,
    this.groupName,
  });

  final String key;
  final String sourceId;
  final String name;
  final ContentType contentType;
  final String? guideId;
  final String? groupName;
}

class PortablePlaylistMatcher {
  PortablePlaylistMatcher(Iterable<PortableMatchCandidate> candidates)
    : _candidates = candidates.toList() {
    for (final candidate in _candidates) {
      final type = candidate.contentType.name;
      _bySourceId['$type\u0000${candidate.sourceId}'] = candidate;

      final guideId = _normalizeIdentity(candidate.guideId);
      if (guideId.isNotEmpty) {
        (_byGuideId['$type\u0000$guideId'] ??= []).add(candidate);
      }

      final normalizedName = normalizeName(candidate.name);
      if (normalizedName.isEmpty) continue;
      (_byName['$type\u0000$normalizedName'] ??= []).add(candidate);
      for (final token in _tokens(normalizedName)) {
        (_byToken['$type\u0000$token'] ??= []).add(candidate);
      }
    }
  }

  final List<PortableMatchCandidate> _candidates;
  final Map<String, PortableMatchCandidate> _bySourceId = {};
  final Map<String, List<PortableMatchCandidate>> _byGuideId = {};
  final Map<String, List<PortableMatchCandidate>> _byName = {};
  final Map<String, List<PortableMatchCandidate>> _byToken = {};

  PortableMatchResult match(
    PortableTransferEntry entry, {
    required bool samePlaylist,
  }) {
    final type = entry.contentType.name;
    if (entry.sourceId != null) {
      final candidate = _bySourceId['$type\u0000${entry.sourceId}'];
      if (candidate != null &&
          (samePlaylist || _sourceIdentityMatches(entry, candidate))) {
        return PortableMatchResult(PortableMatchStatus.matched, candidate);
      }
    }

    final guideId = _normalizeIdentity(entry.guideId);
    if (guideId.isNotEmpty) {
      final guideMatches = _byGuideId['$type\u0000$guideId'] ?? const [];
      final guideMatch = _selectUnique(guideMatches, entry);
      if (guideMatch != null) {
        return PortableMatchResult(PortableMatchStatus.matched, guideMatch);
      }
      if (guideMatches.length > 1) {
        return const PortableMatchResult(PortableMatchStatus.ambiguous);
      }
    }

    final normalizedName = normalizeName(entry.name);
    if (normalizedName.isEmpty) {
      return const PortableMatchResult(PortableMatchStatus.notFound);
    }

    final exactMatches = _byName['$type\u0000$normalizedName'] ?? const [];
    final exactMatch = _selectUnique(exactMatches, entry);
    if (exactMatch != null) {
      return PortableMatchResult(PortableMatchStatus.matched, exactMatch);
    }
    if (exactMatches.length > 1) {
      return const PortableMatchResult(PortableMatchStatus.ambiguous);
    }

    final pool = <PortableMatchCandidate>{};
    for (final token in _tokens(normalizedName)) {
      pool.addAll(_byToken['$type\u0000$token'] ?? const []);
    }
    if (pool.isEmpty) {
      return const PortableMatchResult(PortableMatchStatus.notFound);
    }

    PortableMatchCandidate? best;
    var bestScore = 0.0;
    var secondScore = 0.0;
    final normalizedGroup = normalizeName(entry.groupName ?? '');

    for (final candidate in pool) {
      final candidateName = normalizeName(candidate.name);
      var score = _similarity(normalizedName, candidateName);
      if (normalizedGroup.isNotEmpty &&
          normalizedGroup == normalizeName(candidate.groupName ?? '')) {
        score = (score + 0.04).clamp(0.0, 1.0);
      }

      if (score > bestScore) {
        secondScore = bestScore;
        bestScore = score;
        best = candidate;
      } else if (score > secondScore) {
        secondScore = score;
      }
    }

    final threshold = normalizedName.length < 5 ? 0.96 : 0.88;
    if (best == null || bestScore < threshold) {
      return const PortableMatchResult(PortableMatchStatus.notFound);
    }
    if (bestScore - secondScore < 0.06) {
      return const PortableMatchResult(PortableMatchStatus.ambiguous);
    }
    return PortableMatchResult(PortableMatchStatus.matched, best);
  }

  static String normalizeName(String input) {
    final buffer = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final character = String.fromCharCode(rune);
      buffer.write(_characterReplacements[character] ?? character);
    }

    final tokens = buffer
        .toString()
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[^a-z0-9\u0370-\u03ff]+'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty && !_noiseTokens.contains(token));
    return tokens.join(' ');
  }

  PortableMatchCandidate? _selectUnique(
    List<PortableMatchCandidate> candidates,
    PortableTransferEntry entry,
  ) {
    if (candidates.length == 1) return candidates.first;
    if (candidates.isEmpty) return null;

    final group = normalizeName(entry.groupName ?? '');
    if (group.isEmpty) return null;
    final groupMatches = candidates
        .where((candidate) => normalizeName(candidate.groupName ?? '') == group)
        .toList();
    return groupMatches.length == 1 ? groupMatches.first : null;
  }

  static Iterable<String> _tokens(String normalizedName) {
    return normalizedName
        .split(' ')
        .where(
          (token) => token.length >= 2 && !_searchStopWords.contains(token),
        );
  }

  static String _normalizeIdentity(String? value) {
    return value?.trim().toLowerCase() ?? '';
  }

  static bool _sourceIdentityMatches(
    PortableTransferEntry entry,
    PortableMatchCandidate candidate,
  ) {
    final entryGuideId = _normalizeIdentity(entry.guideId);
    final candidateGuideId = _normalizeIdentity(candidate.guideId);
    if (entryGuideId.isNotEmpty &&
        candidateGuideId.isNotEmpty &&
        entryGuideId == candidateGuideId) {
      return true;
    }

    final entryName = normalizeName(entry.name);
    return entryName.isNotEmpty && entryName == normalizeName(candidate.name);
  }

  static double _similarity(String left, String right) {
    if (left == right) return 1;
    if (left.isEmpty || right.isEmpty) return 0;

    final maxLength = left.length > right.length ? left.length : right.length;
    final characterScore = 1 - (_levenshtein(left, right) / maxLength);
    final leftTokens = left.split(' ').toSet();
    final rightTokens = right.split(' ').toSet();
    final intersection = leftTokens.intersection(rightTokens).length;
    final union = leftTokens.union(rightTokens).length;
    final tokenScore = union == 0 ? 0.0 : intersection / union;
    return (characterScore * 0.7) + (tokenScore * 0.3);
  }

  static int _levenshtein(String left, String right) {
    var previous = List<int>.generate(right.length + 1, (index) => index);
    for (var leftIndex = 0; leftIndex < left.length; leftIndex++) {
      final current = List<int>.filled(right.length + 1, 0);
      current[0] = leftIndex + 1;
      for (var rightIndex = 0; rightIndex < right.length; rightIndex++) {
        final substitutionCost =
            left.codeUnitAt(leftIndex) == right.codeUnitAt(rightIndex) ? 0 : 1;
        final deletion = previous[rightIndex + 1] + 1;
        final insertion = current[rightIndex] + 1;
        final substitution = previous[rightIndex] + substitutionCost;
        current[rightIndex + 1] = [
          deletion,
          insertion,
          substitution,
        ].reduce((a, b) => a < b ? a : b);
      }
      previous = current;
    }
    return previous.last;
  }

  static const _noiseTokens = {
    'a',
    'an',
    'the',
    'hd',
    'fhd',
    'uhd',
    'sd',
    '4k',
    '8k',
    'hevc',
    'h264',
    'h265',
    '50fps',
    '60fps',
    'backup',
    'bkup',
    'test',
    'raw',
    'vip',
    'gr',
    'grc',
    'greek',
    'greece',
    'uk',
    'us',
    'usa',
  };

  static const _searchStopWords = {'and', 'channel', 'tv'};

  static const _characterReplacements = {
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'å': 'a',
    'ā': 'a',
    'ă': 'a',
    'ą': 'a',
    'ç': 'c',
    'ć': 'c',
    'č': 'c',
    'ď': 'd',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ē': 'e',
    'ė': 'e',
    'ę': 'e',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ī': 'i',
    'į': 'i',
    'ł': 'l',
    'ñ': 'n',
    'ń': 'n',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ø': 'o',
    'ō': 'o',
    'ř': 'r',
    'ś': 's',
    'š': 's',
    'ß': 'ss',
    'ť': 't',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ū': 'u',
    'ý': 'y',
    'ÿ': 'y',
    'ž': 'z',
    'ź': 'z',
    'ż': 'z',
    'ά': 'α',
    'έ': 'ε',
    'ή': 'η',
    'ί': 'ι',
    'ϊ': 'ι',
    'ΐ': 'ι',
    'ό': 'ο',
    'ύ': 'υ',
    'ϋ': 'υ',
    'ΰ': 'υ',
    'ώ': 'ω',
    'ς': 'σ',
  };
}

class _PortableCatalog {
  _PortableCatalog(this.items)
    : byKey = {for (final item in items) item.candidate.key: item.contentItem};

  final List<_PortableCatalogItem> items;
  final Map<String, ContentItem> byKey;
}

class _PortableCatalogItem {
  const _PortableCatalogItem(this.contentItem, this.candidate);

  final ContentItem contentItem;
  final PortableMatchCandidate candidate;
}
