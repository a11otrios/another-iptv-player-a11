import 'dart:convert';
import 'dart:io';

import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/models/subtitle_search_result.dart';
import 'package:another_iptv_player/repositories/user_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class OpenSubtitlesService {
  static const String _defaultBaseUrl = 'https://api.opensubtitles.com/api/v1';

  Future<List<SubtitleSearchResult>> searchForContent(
    ContentItem content, {
    String? query,
    String? languages,
  }) {
    return search(
      title: content.name,
      contentType: content.contentType,
      query: query,
      languages: languages,
      imdbId: _imdbId(content),
      season: content.season,
    );
  }

  Future<List<SubtitleSearchResult>> search({
    required String title,
    required ContentType contentType,
    String? query,
    String? languages,
    String? imdbId,
    int? season,
  }) async {
    final apiKey = await UserPreferences.getOpenSubtitlesApiKey();
    if (apiKey.isEmpty) {
      throw const OpenSubtitlesException('OpenSubtitles API key is missing.');
    }

    final params = <String, String>{
      'languages':
          (languages ?? await UserPreferences.getOpenSubtitlesLanguages())
              .trim(),
      'order_by': 'download_count',
      'order_direction': 'desc',
    };

    if (imdbId != null) {
      params['imdb_id'] = imdbId.replaceFirst(RegExp(r'^tt'), '');
    } else {
      params['query'] = query?.trim().isNotEmpty == true
          ? query!.trim()
          : _cleanTitle(title);
    }

    final year = _year(title);
    if (year != null) {
      params['year'] = year;
    }

    switch (contentType) {
      case ContentType.vod:
        params['type'] = 'movie';
        break;
      case ContentType.series:
        params['type'] = 'episode';
        if (season != null) {
          params['season_number'] = season.toString();
        }
        break;
      case ContentType.liveStream:
        params['type'] = 'all';
        break;
    }

    final response = await http.get(
      await _uri('/subtitles', params),
      headers: await _headers(apiKey: apiKey),
    );

    if (response.statusCode != 200) {
      throw OpenSubtitlesException(_errorMessage(response));
    }

    final body = jsonDecode(response.body);
    final data = body is Map ? body['data'] : null;
    if (data is! List) return const [];

    final results = <SubtitleSearchResult>[];
    for (final item in data.whereType<Map>()) {
      final normalizedItem = Map<String, dynamic>.from(item);
      final attributes = _asMap(normalizedItem['attributes']);
      final files = attributes['files'];
      if (files is! List) continue;

      for (final file in files.whereType<Map>()) {
        final normalizedFile = Map<String, dynamic>.from(file);
        final result = SubtitleSearchResult.fromOpenSubtitles(
          normalizedItem,
          normalizedFile,
        );
        if (result.fileId > 0) {
          results.add(result);
        }
      }
    }

    return results;
  }

  Future<CachedSubtitle> downloadForContent(
    ContentItem content,
    SubtitleSearchResult subtitle,
  ) {
    return download(
      contentKey: contentKey(content),
      contentName: content.name,
      subtitle: subtitle,
    );
  }

  Future<CachedSubtitle> download({
    required String contentKey,
    required String contentName,
    required SubtitleSearchResult subtitle,
    String? preferredFormat,
  }) async {
    final apiKey = await UserPreferences.getOpenSubtitlesApiKey();
    if (apiKey.isEmpty) {
      throw const OpenSubtitlesException('OpenSubtitles API key is missing.');
    }

    final token = await _ensureToken(apiKey);
    final response = await http.post(
      await _uri('/download'),
      headers: await _headers(
        apiKey: apiKey,
        token: token,
        contentType: 'application/json',
      ),
      body: jsonEncode({
        'file_id': subtitle.fileId,
        'sub_format': preferredFormat ?? _preferredFormat(subtitle.format),
      }),
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      await UserPreferences.setOpenSubtitlesToken('');
    }

    if (response.statusCode != 200) {
      throw OpenSubtitlesException(_errorMessage(response));
    }

    final body = jsonDecode(response.body);
    if (body is! Map || body['link'] == null) {
      throw const OpenSubtitlesException(
        'OpenSubtitles did not return a link.',
      );
    }

    final downloadResponse = await http.get(Uri.parse(body['link'].toString()));
    if (downloadResponse.statusCode != 200) {
      throw OpenSubtitlesException(
        'Subtitle download failed (${downloadResponse.statusCode}).',
      );
    }

    final directory = await _subtitleDirectory();
    final fileName = _safeFileName(
      body['file_name']?.toString().trim().isNotEmpty == true
          ? body['file_name'].toString()
          : '$contentName.${subtitle.language}.${preferredFormat ?? subtitle.format}',
    );
    final file = File(p.join(directory.path, fileName));
    await file.writeAsBytes(downloadResponse.bodyBytes, flush: true);

    final cached = CachedSubtitle(
      contentKey: contentKey,
      filePath: file.path,
      title: subtitle.releaseName,
      language: subtitle.language.isEmpty ? 'auto' : subtitle.language,
      offsetSeconds: 0.0,
    );
    await UserPreferences.setCachedSubtitle(cached);
    return cached;
  }

  Future<CachedSubtitle?> cachedForContent(ContentItem content) async {
    return cachedForKey(contentKey(content));
  }

  Future<CachedSubtitle?> cachedForKey(String contentKey) async {
    final cached = await UserPreferences.getCachedSubtitle(contentKey);
    if (cached == null || cached.filePath.isEmpty) return null;
    if (!await File(cached.filePath).exists()) return null;
    return cached;
  }

  Future<void> saveOffset(ContentItem content, double offsetSeconds) {
    return saveOffsetForKey(contentKey(content), offsetSeconds);
  }

  Future<void> saveOffsetForKey(String contentKey, double offsetSeconds) {
    return UserPreferences.setCachedSubtitleOffset(contentKey, offsetSeconds);
  }

  static String contentKey(ContentItem content) {
    final playlistId =
        content.vodStream?.playlistId ??
        content.seriesStream?.playlistId ??
        content.m3uItem?.playlistId ??
        'current';
    final streamId = content.m3uItem?.id ?? content.id;
    return '$playlistId:${content.contentType.name}:$streamId';
  }

  Future<String> _ensureToken(String apiKey) async {
    final existing = await UserPreferences.getOpenSubtitlesToken();
    if (existing.isNotEmpty) return existing;

    final username = await UserPreferences.getOpenSubtitlesUsername();
    final password = await UserPreferences.getOpenSubtitlesPassword();
    if (username.isEmpty || password.isEmpty) {
      throw const OpenSubtitlesException(
        'OpenSubtitles username or password is missing.',
      );
    }

    final response = await http.post(
      await _uri('/login'),
      headers: await _headers(apiKey: apiKey, contentType: 'application/json'),
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode != 200) {
      throw OpenSubtitlesException(_errorMessage(response));
    }

    final body = jsonDecode(response.body);
    if (body is! Map || body['token'] == null) {
      throw const OpenSubtitlesException(
        'OpenSubtitles login did not return a token.',
      );
    }

    final baseUrl = body['base_url']?.toString();
    if (baseUrl != null && baseUrl.isNotEmpty) {
      final normalized = baseUrl.startsWith('http')
          ? '$baseUrl/api/v1'
          : 'https://$baseUrl/api/v1';
      await UserPreferences.setOpenSubtitlesBaseUrl(normalized);
    }

    final token = body['token'].toString();
    await UserPreferences.setOpenSubtitlesToken(token);
    return token;
  }

  Future<Map<String, String>> _headers({
    required String apiKey,
    String? token,
    String? contentType,
  }) async {
    final headers = <String, String>{
      'Api-Key': apiKey,
      'User-Agent': await _userAgent(),
      'Accept': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (contentType != null) {
      headers['Content-Type'] = contentType;
    }
    return headers;
  }

  Future<Uri> _uri(String path, [Map<String, String>? query]) async {
    var baseUrl = await UserPreferences.getOpenSubtitlesBaseUrl();
    if (baseUrl.isEmpty) baseUrl = _defaultBaseUrl;
    return Uri.parse('$baseUrl$path').replace(queryParameters: query);
  }

  Future<String> _userAgent() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return 'Another IPTV Player v${info.version}';
    } catch (_) {
      return 'Another IPTV Player v1';
    }
  }

  Future<Directory> _subtitleDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'subtitles'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  String _preferredFormat(String format) {
    final normalized = format.toLowerCase().trim();
    if (normalized == 'srt' || normalized == 'vtt' || normalized == 'ass') {
      return normalized;
    }
    return 'srt';
  }

  String _safeFileName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    final fileName = cleaned.isEmpty ? 'subtitle.srt' : cleaned;
    if (fileName.contains('.')) return fileName;
    return '$fileName.srt';
  }

  String _cleanTitle(String value) {
    return value
        .replaceAll(RegExp(r'\[[^\]]+\]'), ' ')
        .replaceAll(
          RegExp(
            r'\([^\)]*(1080|720|2160|4k|uhd|bluray|web)[^\)]*\)',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'\b(4k|uhd|hdr|x264|x265|h264|h265|hevc|bluray|web[- ]?dl|webrip|brrip|dvdrip|proper|repack)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String? _year(String value) {
    return RegExp(r'\b(19\d{2}|20\d{2})\b').firstMatch(value)?.group(1);
  }

  String? _imdbId(ContentItem content) {
    final candidates = [
      content.vodStream?.streamId,
      content.seriesStream?.seriesId,
      content.id,
    ];
    for (final candidate in candidates) {
      if (candidate == null) continue;
      final match = RegExp(r'tt\d{7,8}').firstMatch(candidate);
      if (match != null) return match.group(0);
    }
    return null;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  String _errorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map) {
        final message = body['message'] ?? body['error'];
        if (message != null) return message.toString();
      }
    } catch (_) {
      // Fall back to status text below.
    }
    return 'OpenSubtitles request failed (${response.statusCode}).';
  }
}

class OpenSubtitlesException implements Exception {
  final String message;

  const OpenSubtitlesException(this.message);

  @override
  String toString() => message;
}
