import 'dart:convert';

import 'package:another_iptv_player/models/category_type.dart';
import 'package:another_iptv_player/models/player_aspect_ratio_mode.dart';
import 'package:another_iptv_player/models/subtitle_search_result.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:another_iptv_player/utils/category_item_sort.dart';

class UserPreferences {
  static const String subtitleOff = '__off__';
  static const String _keyLastPlaylist = 'last_playlist';
  static const String _keyVolume = 'volume';
  static const String _keyAudioTrack = 'audio_track';
  static const String _keySubtitleTrack = 'subtitle_track';
  static const String _keyVideoQuality = 'video_quality';
  static const String _keyBackgroundPlay = 'background_play';
  static const String _keySubtitleFontSize = 'subtitle_font_size';
  static const String _keySubtitleHeight = 'subtitle_height';
  static const String _keySubtitleLetterSpacing = 'subtitle_letter_spacing';
  static const String _keySubtitleWordSpacing = 'subtitle_word_spacing';
  static const String _keySubtitleTextColor = 'subtitle_text_color';
  static const String _keySubtitleBackgroundColor = 'subtitle_background_color';
  static const String _keySubtitleFontWeight = 'subtitle_font_weight';
  static const String _keySubtitleTextAlign = 'subtitle_text_align';
  static const String _keySubtitlePadding = 'subtitle_padding';
  static const String _keyLocale = 'locale';
  static const String _hiddenCategoriesKey = 'hidden_categories';
  static const String _hiddenCategoriesPrefix = 'hidden_categories.';
  static const String _categoryOrderPrefix = 'category_order.';
  static const String _categoryOriginalOrderPrefix = 'category_original_order.';
  static const String _categoryItemSortPrefix = 'category_item_sort.';
  static const String _hideRadioStationsPrefix = 'hide_radio_stations.';
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyBrightnessGesture = 'brightness_gesture';
  static const String _keyVolumeGesture = 'volume_gesture';
  static const String _keySeekGesture = 'seek_gesture';
  static const String _keySpeedUpOnLongPress = 'speed_up_on_long_press';
  static const String _keySeekOnDoubleTap = 'seek_on_double_tap';
  static const String _keyLegacyPlayerAspectRatio = 'player_aspect_ratio';
  static const String _keyPlayerAspectRatioPrefix = 'player_aspect_ratio.';
  static const String _keyBorderlessWindow = 'borderless_window';
  static const String _keyAlwaysOnTop = 'always_on_top';
  static const String _keyOpenSubtitlesApiKey = 'opensubtitles_api_key';
  static const String _keyOpenSubtitlesUsername = 'opensubtitles_username';
  static const String _keyOpenSubtitlesPassword = 'opensubtitles_password';
  static const String _keyOpenSubtitlesToken = 'opensubtitles_token';
  static const String _keyOpenSubtitlesBaseUrl = 'opensubtitles_base_url';
  static const String _keyOpenSubtitlesLanguages = 'opensubtitles_languages';
  static const String _keyCachedSubtitles = 'cached_subtitles';

  static Future<void> setLastPlaylist(String playlistId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastPlaylist, playlistId);
  }

  static Future<String?> getLastPlaylist() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastPlaylist);
  }

  static Future<void> removeLastPlaylist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastPlaylist);
  }

  static Future<void> setVolume(double volume) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyVolume, volume);
  }

  static Future<double> getVolume() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyVolume) ?? 100;
  }

  static Future<void> setAudioTrack(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAudioTrack, language);
  }

  static Future<String> getAudioTrack() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAudioTrack) ?? 'auto';
  }

  static Future<void> setSubtitleTrack(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySubtitleTrack, language);
  }

  static Future<String> getSubtitleTrack() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySubtitleTrack) ?? 'auto';
  }

  static Future<void> setVideoTrack(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyVideoQuality, id);
  }

  static Future<String> getVideoTrack() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyVideoQuality) ?? 'auto';
  }

  static Future<void> setBackgroundPlay(bool backgroundPlay) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBackgroundPlay, backgroundPlay);
  }

  static Future<bool> getBackgroundPlay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBackgroundPlay) ?? true;
  }

  static Future<void> setBorderlessWindow(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBorderlessWindow, value);
  }

  static Future<bool> getBorderlessWindow() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBorderlessWindow) ?? false;
  }

  static Future<void> setAlwaysOnTop(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAlwaysOnTop, value);
  }

  static Future<bool> getAlwaysOnTop() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAlwaysOnTop) ?? false;
  }

  static Future<void> setOpenSubtitlesApiKey(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyOpenSubtitlesApiKey, value.trim());
  }

  static Future<String> getOpenSubtitlesApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyOpenSubtitlesApiKey) ?? '';
  }

  static Future<void> setOpenSubtitlesUsername(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyOpenSubtitlesUsername, value.trim());
  }

  static Future<String> getOpenSubtitlesUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyOpenSubtitlesUsername) ?? '';
  }

  static Future<void> setOpenSubtitlesPassword(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyOpenSubtitlesPassword, value);
  }

  static Future<String> getOpenSubtitlesPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyOpenSubtitlesPassword) ?? '';
  }

  static Future<void> setOpenSubtitlesToken(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyOpenSubtitlesToken, value);
  }

  static Future<String> getOpenSubtitlesToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyOpenSubtitlesToken) ?? '';
  }

  static Future<void> setOpenSubtitlesBaseUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyOpenSubtitlesBaseUrl, value);
  }

  static Future<String> getOpenSubtitlesBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyOpenSubtitlesBaseUrl) ??
        'https://api.opensubtitles.com/api/v1';
  }

  static Future<void> setOpenSubtitlesLanguages(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = value
        .split(',')
        .map((part) => part.trim().toLowerCase())
        .where((part) => part.isNotEmpty)
        .join(',');
    await prefs.setString(_keyOpenSubtitlesLanguages, normalized);
  }

  static Future<String> getOpenSubtitlesLanguages() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyOpenSubtitlesLanguages) ?? 'en';
  }

  static Future<bool> hasOpenSubtitlesCredentials() async {
    final apiKey = await getOpenSubtitlesApiKey();
    final username = await getOpenSubtitlesUsername();
    final password = await getOpenSubtitlesPassword();
    return apiKey.isNotEmpty && username.isNotEmpty && password.isNotEmpty;
  }

  static Future<CachedSubtitle?> getCachedSubtitle(String contentKey) async {
    final prefs = await SharedPreferences.getInstance();
    final subtitles = _cachedSubtitleMap(prefs);
    final data = subtitles[contentKey];
    if (data is Map<String, dynamic>) {
      return CachedSubtitle.fromJson(data);
    }
    if (data is Map) {
      return CachedSubtitle.fromJson(Map<String, dynamic>.from(data));
    }
    return null;
  }

  static Future<void> setCachedSubtitle(CachedSubtitle subtitle) async {
    final prefs = await SharedPreferences.getInstance();
    final subtitles = _cachedSubtitleMap(prefs);
    subtitles[subtitle.contentKey] = subtitle.toJson();
    await prefs.setString(_keyCachedSubtitles, jsonEncode(subtitles));
  }

  static Future<void> setCachedSubtitleOffset(
    String contentKey,
    double offsetSeconds,
  ) async {
    final cached = await getCachedSubtitle(contentKey);
    if (cached == null) return;
    await setCachedSubtitle(
      CachedSubtitle(
        contentKey: cached.contentKey,
        filePath: cached.filePath,
        title: cached.title,
        language: cached.language,
        offsetSeconds: offsetSeconds,
      ),
    );
  }

  static Map<String, dynamic> _cachedSubtitleMap(SharedPreferences prefs) {
    final raw = prefs.getString(_keyCachedSubtitles);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return {};
  }

  static Future<double> getSubtitleFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keySubtitleFontSize) ?? 32.0;
  }

  static Future<void> setSubtitleFontSize(double fontSize) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySubtitleFontSize, fontSize);
  }

  static Future<double> getSubtitleHeight() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keySubtitleHeight) ?? 1.4;
  }

  static Future<void> setSubtitleHeight(double height) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySubtitleHeight, height);
  }

  static Future<double> getSubtitleLetterSpacing() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keySubtitleLetterSpacing) ?? 0.0;
  }

  static Future<void> setSubtitleLetterSpacing(double letterSpacing) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySubtitleLetterSpacing, letterSpacing);
  }

  static Future<double> getSubtitleWordSpacing() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keySubtitleWordSpacing) ?? 0.0;
  }

  static Future<void> setSubtitleWordSpacing(double wordSpacing) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySubtitleWordSpacing, wordSpacing);
  }

  static Future<Color> getSubtitleTextColor() async {
    final prefs = await SharedPreferences.getInstance();
    final colorValue = prefs.getInt(_keySubtitleTextColor) ?? 0xffffffff;
    return Color(colorValue);
  }

  static Future<void> setSubtitleTextColor(Color textColor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySubtitleTextColor, textColor.toARGB32());
  }

  static Future<Color> getSubtitleBackgroundColor() async {
    final prefs = await SharedPreferences.getInstance();
    final colorValue = prefs.getInt(_keySubtitleBackgroundColor) ?? 0xaa000000;
    return Color(colorValue);
  }

  static Future<void> setSubtitleBackgroundColor(Color backgroundColor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySubtitleBackgroundColor, backgroundColor.toARGB32());
  }

  static Future<FontWeight> getSubtitleFontWeight() async {
    final prefs = await SharedPreferences.getInstance();
    final savedWeight = prefs.getInt(_keySubtitleFontWeight);
    if (savedWeight == null) return FontWeight.normal;
    if (savedWeight >= 0 && savedWeight < FontWeight.values.length) {
      return FontWeight.values[savedWeight];
    }
    return FontWeight.values.firstWhere(
      (weight) => weight.value == savedWeight,
      orElse: () => FontWeight.normal,
    );
  }

  static Future<void> setSubtitleFontWeight(FontWeight fontWeight) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySubtitleFontWeight, fontWeight.value);
  }

  static Future<TextAlign> getSubtitleTextAlign() async {
    final prefs = await SharedPreferences.getInstance();
    final alignIndex =
        prefs.getInt(_keySubtitleTextAlign) ?? TextAlign.center.index;
    return TextAlign.values[alignIndex];
  }

  static Future<void> setSubtitleTextAlign(TextAlign textAlign) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySubtitleTextAlign, textAlign.index);
  }

  static Future<double> getSubtitlePadding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keySubtitlePadding) ?? 24.0;
  }

  static Future<void> setSubtitlePadding(double padding) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySubtitlePadding, padding);
  }

  static Future<String?> getLocale() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLocale);
  }

  static Future<void> setLocale(String locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLocale, locale);
  }

  static Future<void> removeLocale() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLocale);
  }

  static Future<void> setHiddenCategories(
    List<String> categoryIds, {
    String? playlistId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _hiddenCategoriesPreferenceKey(playlistId),
      categoryIds,
    );
  }

  static Future<bool> getHiddenCategory(
    String categoryId, {
    String? playlistId,
    CategoryType? categoryType,
  }) async {
    final hidden = await getHiddenCategories(playlistId: playlistId);
    final key = categoryType == null
        ? categoryId
        : hiddenCategoryKey(categoryType, categoryId);
    return hidden.contains(key) || hidden.contains(categoryId);
  }

  static Future<List<String>> getHiddenCategories({String? playlistId}) async {
    final prefs = await SharedPreferences.getInstance();
    final hidden =
        prefs.getStringList(_hiddenCategoriesPreferenceKey(playlistId)) ?? [];
    if (playlistId == null || hidden.isNotEmpty) {
      return hidden;
    }
    return prefs.getStringList(_hiddenCategoriesKey) ?? [];
  }

  static String hiddenCategoryKey(CategoryType type, String categoryId) {
    return '${type.value}:$categoryId';
  }

  static String _hiddenCategoriesPreferenceKey(String? playlistId) {
    if (playlistId == null || playlistId.isEmpty) {
      return _hiddenCategoriesKey;
    }
    final encodedId = base64Url
        .encode(utf8.encode(playlistId))
        .replaceAll('=', '');
    return '$_hiddenCategoriesPrefix$encodedId';
  }

  static Future<void> setCategoryOrder({
    required String playlistId,
    required CategoryType type,
    required List<String> categoryIds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _categoryOrderPreferenceKey(playlistId, type),
      categoryIds,
    );
  }

  static Future<void> setHideRadioStations({
    required String playlistId,
    required bool value,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      _playlistPreferenceKey(_hideRadioStationsPrefix, playlistId),
      value,
    );
  }

  static Future<bool> getHideRadioStations({required String playlistId}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(
          _playlistPreferenceKey(_hideRadioStationsPrefix, playlistId),
        ) ??
        false;
  }

  static Future<List<String>> getCategoryOrder({
    required String playlistId,
    required CategoryType type,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_categoryOrderPreferenceKey(playlistId, type)) ??
        const [];
  }

  static Future<void> setCategoryItemSort({
    required String playlistId,
    required CategoryType type,
    required String categoryId,
    required CategoryItemSort sort,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _categoryItemSortPreferenceKey(playlistId, type, categoryId);
    if (sort == CategoryItemSort.provider) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, sort.name);
    }
  }

  static Future<CategoryItemSort> getCategoryItemSort({
    required String playlistId,
    required CategoryType type,
    required String categoryId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return CategoryItemSort.fromPreference(
      prefs.getString(
        _categoryItemSortPreferenceKey(playlistId, type, categoryId),
      ),
    );
  }

  static Future<List<String>> syncCategoryOriginalOrder({
    required String playlistId,
    required CategoryType type,
    required Iterable<String> categoryIds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _categoryOrderPreferenceKey(
      playlistId,
      type,
      prefix: _categoryOriginalOrderPrefix,
    );
    final current = categoryIds.toSet();
    final existing = prefs.getStringList(key) ?? const [];
    final merged = <String>[
      ...existing.where(current.contains),
      ...current.where((id) => !existing.contains(id)),
    ];
    if (!_sameStrings(existing, merged)) {
      await prefs.setStringList(key, merged);
    }
    return merged;
  }

  static Future<List<String>> getCategoryOriginalOrder({
    required String playlistId,
    required CategoryType type,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(
          _categoryOrderPreferenceKey(
            playlistId,
            type,
            prefix: _categoryOriginalOrderPrefix,
          ),
        ) ??
        const [];
  }

  static List<T> applyCategoryOrder<T>(
    Iterable<T> categories,
    List<String> categoryOrder,
    String Function(T category) categoryId,
  ) {
    final source = categories.toList();
    if (categoryOrder.isEmpty || source.length < 2) return source;

    final byId = <String, T>{for (final item in source) categoryId(item): item};
    final result = <T>[];
    final added = <String>{};
    for (final id in categoryOrder) {
      final item = byId[id];
      if (item != null && added.add(id)) result.add(item);
    }
    for (final item in source) {
      if (added.add(categoryId(item))) result.add(item);
    }
    return result;
  }

  static String _categoryOrderPreferenceKey(
    String playlistId,
    CategoryType type, {
    String prefix = _categoryOrderPrefix,
  }) {
    final encodedId = base64Url
        .encode(utf8.encode(playlistId))
        .replaceAll('=', '');
    return '$prefix$encodedId.${type.value}';
  }

  static String _categoryItemSortPreferenceKey(
    String playlistId,
    CategoryType type,
    String categoryId,
  ) {
    final encodedPlaylistId = base64Url
        .encode(utf8.encode(playlistId))
        .replaceAll('=', '');
    final encodedCategoryId = base64Url
        .encode(utf8.encode(categoryId))
        .replaceAll('=', '');
    return '$_categoryItemSortPrefix$encodedPlaylistId.${type.value}.$encodedCategoryId';
  }

  static bool _sameStrings(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  static String _playlistPreferenceKey(String prefix, String playlistId) {
    final encodedId = base64Url
        .encode(utf8.encode(playlistId))
        .replaceAll('=', '');
    return '$prefix$encodedId';
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, mode.toString().split('.').last);
  }

  static Future<ThemeMode> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(_keyThemeMode) ?? 'system';
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  // Player gesture settings
  static Future<bool> getBrightnessGesture() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBrightnessGesture) ?? false;
  }

  static Future<void> setBrightnessGesture(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBrightnessGesture, value);
  }

  static Future<bool> getVolumeGesture() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyVolumeGesture) ?? false;
  }

  static Future<void> setVolumeGesture(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyVolumeGesture, value);
  }

  static Future<bool> getSeekGesture() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySeekGesture) ?? false;
  }

  static Future<void> setSeekGesture(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySeekGesture, value);
  }

  static Future<bool> getSpeedUpOnLongPress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySpeedUpOnLongPress) ?? true;
  }

  static Future<void> setSpeedUpOnLongPress(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySpeedUpOnLongPress, value);
  }

  static Future<bool> getSeekOnDoubleTap() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySeekOnDoubleTap) ?? true;
  }

  static Future<void> setSeekOnDoubleTap(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySeekOnDoubleTap, value);
  }

  static Future<PlayerAspectRatioMode> getPlayerAspectRatio(
    String streamKey,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final preferenceKey = _playerAspectRatioPreferenceKey(streamKey);
    final scopedValue = prefs.getString(preferenceKey);
    if (scopedValue != null) {
      return _parsePlayerAspectRatio(scopedValue) ??
          PlayerAspectRatioMode.original;
    }

    final legacyValue = prefs.getString(_keyLegacyPlayerAspectRatio);
    final legacyMode = _parsePlayerAspectRatio(legacyValue);
    if (legacyValue != null) {
      await prefs.remove(_keyLegacyPlayerAspectRatio);
    }
    if (legacyMode != null) {
      await prefs.setString(preferenceKey, legacyMode.name);
      return legacyMode;
    }

    return PlayerAspectRatioMode.original;
  }

  static Future<void> setPlayerAspectRatio(
    String streamKey,
    PlayerAspectRatioMode aspectRatio,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _playerAspectRatioPreferenceKey(streamKey),
      aspectRatio.name,
    );
  }

  static String _playerAspectRatioPreferenceKey(String streamKey) {
    final encodedKey = base64Url
        .encode(utf8.encode(streamKey))
        .replaceAll('=', '');
    return '$_keyPlayerAspectRatioPrefix$encodedKey';
  }

  static PlayerAspectRatioMode? _parsePlayerAspectRatio(String? value) {
    if (value == null) return null;
    for (final mode in PlayerAspectRatioMode.values) {
      if (mode.name == value) return mode;
    }
    return null;
  }
}
