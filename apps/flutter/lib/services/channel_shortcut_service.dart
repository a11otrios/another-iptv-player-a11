import 'dart:convert';

import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/live_stream.dart';
import 'package:another_iptv_player/models/m3u_item.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/services/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ChannelShortcutStore {
  Future<Map<int, ContentItem>> getShortcuts();

  Future<Map<int, ContentItem>> getShortcutsForPage(String page);

  Future<void> saveShortcuts(Map<int, ContentItem> shortcuts);

  Future<void> saveShortcutsForPage(
    String page,
    Map<int, ContentItem> shortcuts,
  );
}

class ChannelShortcutService implements ChannelShortcutStore {
  static const String _keyPrefix = 'channel_shortcuts';
  static const String defaultPage = 'A';
  static const List<String> pages = ['A', 'S', 'D', 'F', 'G'];

  @override
  Future<Map<int, ContentItem>> getShortcuts() async {
    return getShortcutsForPage(defaultPage);
  }

  @override
  Future<Map<int, ContentItem>> getShortcutsForPage(String page) async {
    _validatePage(page);
    final playlist = AppState.currentPlaylist;
    if (playlist == null) return {};

    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey(playlist.id, page));
    if (encoded == null || encoded.isEmpty) return {};

    try {
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final shortcuts = <int, ContentItem>{};

      for (final entry in decoded.entries) {
        final number = int.tryParse(entry.key);
        if (number == null || number < 0 || number > 9) continue;
        final data = Map<String, dynamic>.from(entry.value as Map);
        shortcuts[number] = _contentItemFromJson(data, playlist.id);
      }

      return shortcuts;
    } catch (_) {
      return {};
    }
  }

  Future<ContentItem?> getShortcut(
    int number, {
    String page = defaultPage,
  }) async {
    return (await getShortcutsForPage(page))[number];
  }

  Future<void> assignShortcut(
    int number,
    ContentItem contentItem, {
    String page = defaultPage,
  }) async {
    _validatePage(page);
    if (number < 0 || number > 9) {
      throw ArgumentError.value(number, 'number', 'Must be from 0 to 9');
    }
    if (contentItem.contentType != ContentType.liveStream) {
      throw ArgumentError('Only live channels can have number shortcuts');
    }

    final playlist = AppState.currentPlaylist;
    if (playlist == null) return;

    final shortcuts = await getShortcutsForPage(page);
    shortcuts[number] = contentItem;
    await _saveShortcuts(playlist.id, shortcuts, page: page);
  }

  Future<void> removeShortcut(int number, {String page = defaultPage}) async {
    _validatePage(page);
    final playlist = AppState.currentPlaylist;
    if (playlist == null) return;

    final shortcuts = await getShortcutsForPage(page);
    shortcuts.remove(number);
    await _saveShortcuts(playlist.id, shortcuts, page: page);
  }

  @override
  Future<void> saveShortcuts(Map<int, ContentItem> shortcuts) async {
    await saveShortcutsForPage(defaultPage, shortcuts);
  }

  @override
  Future<void> saveShortcutsForPage(
    String page,
    Map<int, ContentItem> shortcuts,
  ) async {
    final playlist = AppState.currentPlaylist;
    if (playlist == null) return;

    await _saveShortcuts(playlist.id, shortcuts, page: page);
  }

  Future<void> _saveShortcuts(
    String playlistId,
    Map<int, ContentItem> shortcuts, {
    required String page,
  }) async {
    _validatePage(page);
    final encoded = jsonEncode({
      for (final entry in shortcuts.entries)
        entry.key.toString(): _contentItemToJson(entry.value),
    });
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey(playlistId, page), encoded);
  }

  String _storageKey(String playlistId, String page) {
    return page == defaultPage
        ? '${_keyPrefix}_$playlistId'
        : '${_keyPrefix}_${playlistId}_$page';
  }

  void _validatePage(String page) {
    if (!pages.contains(page)) {
      throw ArgumentError.value(page, 'page', 'Must be one of $pages');
    }
  }

  Map<String, dynamic> _contentItemToJson(ContentItem contentItem) {
    final m3uItem = contentItem.m3uItem;
    final liveStream = contentItem.liveStream;

    return {
      'id': contentItem.id,
      'name': contentItem.name,
      'imagePath': contentItem.imagePath,
      'source': m3uItem == null ? 'xtream' : 'm3u',
      'categoryId': liveStream?.categoryId ?? m3uItem?.categoryId,
      'epgChannelId': liveStream?.epgChannelId,
      'm3uId': m3uItem?.id,
      'tvgId': m3uItem?.tvgId,
      'tvgName': m3uItem?.tvgName,
      'url': m3uItem?.url,
      'groupTitle': m3uItem?.groupTitle,
      'userAgent': m3uItem?.userAgent,
      'referrer': m3uItem?.referrer,
    };
  }

  ContentItem _contentItemFromJson(
    Map<String, dynamic> data,
    String playlistId,
  ) {
    final id = data['id'] as String? ?? '';
    final name = data['name'] as String? ?? '';
    final imagePath = data['imagePath'] as String? ?? '';
    final categoryId = data['categoryId'] as String?;

    if (data['source'] == 'm3u') {
      final m3uItem = M3uItem(
        id: data['m3uId'] as String? ?? id,
        playlistId: playlistId,
        url: data['url'] as String? ?? id,
        contentType: ContentType.liveStream,
        name: name,
        tvgId: data['tvgId'] as String?,
        tvgName: data['tvgName'] as String?,
        tvgLogo: imagePath,
        groupTitle: data['groupTitle'] as String?,
        userAgent: data['userAgent'] as String?,
        referrer: data['referrer'] as String?,
        categoryId: categoryId,
      );
      return ContentItem(
        id,
        name,
        imagePath,
        ContentType.liveStream,
        m3uItem: m3uItem,
      );
    }

    final liveStream = LiveStream(
      streamId: id,
      name: name,
      streamIcon: imagePath,
      categoryId: categoryId ?? '',
      epgChannelId: data['epgChannelId'] as String? ?? '',
      playlistId: playlistId,
    );
    return ContentItem(
      id,
      name,
      imagePath,
      ContentType.liveStream,
      liveStream: liveStream,
    );
  }
}
