import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:another_iptv_player/models/epg_program.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

typedef XmltvHttpGet =
    Future<http.Response> Function(Uri uri, {Map<String, String>? headers});

/// Reads an XMLTV guide from a local file or remote URL.
///
/// Remote guides are shared by all channel lookups, refreshed periodically,
/// and conditionally requested when the server supplies cache validators.
class XmltvGuideService {
  XmltvGuideService({
    XmltvHttpGet? httpGet,
    this.remoteRefreshInterval = const Duration(hours: 6),
    this.remoteFailureRetryInterval = const Duration(minutes: 1),
    DateTime Function()? now,
  }) : _httpGet = httpGet ?? http.get,
       _now = now ?? DateTime.now;

  static final XmltvGuideService instance = XmltvGuideService();

  final XmltvHttpGet _httpGet;
  final DateTime Function() _now;
  final Duration remoteRefreshInterval;
  final Duration remoteFailureRetryInterval;
  final Map<String, _CachedGuide> _guides = {};
  final Map<String, Future<_CachedGuide>> _remoteLoads = {};
  final Map<String, DateTime> _remoteFailures = {};

  Future<List<EpgProgram>> programsFor({
    required String source,
    required String channelId,
    required String channelName,
    required int limit,
    DateTime? now,
  }) async {
    final normalizedSource = source.trim();
    if (normalizedSource.isEmpty || limit <= 0) return const [];

    final guide = isRemoteUrl(normalizedSource)
        ? await _remoteGuide(normalizedSource)
        : await _localGuide(normalizedSource);
    if (guide == null) return const [];

    final normalizedId = channelId.trim();
    final matchedId = guide.programsByChannel.containsKey(normalizedId)
        ? normalizedId
        : guide.channelIdsByName[_normalizeName(channelName)];
    if (matchedId == null) return const [];

    final reference = now ?? _now();
    return (guide.programsByChannel[matchedId] ?? const <EpgProgram>[])
        .where((program) {
          if (program.nowPlaying || program.isAiringAt(reference)) return true;
          return program.startTime?.isAfter(reference) ?? false;
        })
        .take(limit)
        .toList(growable: false);
  }

  void invalidate(String source) {
    final normalizedSource = source.trim();
    _guides.remove(normalizedSource);
    _remoteFailures.remove(normalizedSource);
  }

  static bool isRemoteUrl(String source) {
    final uri = Uri.tryParse(source.trim());
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return false;
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  Future<_CachedGuide?> _localGuide(String source) async {
    final file = File(source);
    if (!await file.exists()) return null;

    final modified = await file.lastModified();
    final cached = _guides[source];
    if (cached?.fileModified == modified) return cached;

    final guide = _parseGuide(
      _decodeGuide(await file.readAsBytes()),
      loadedAt: _now(),
      fileModified: modified,
    );
    _guides[source] = guide;
    return guide;
  }

  Future<_CachedGuide?> _remoteGuide(String source) async {
    final current = _guides[source];
    final now = _now();
    if (current != null &&
        now.difference(current.loadedAt) < remoteRefreshInterval) {
      return current;
    }

    final failedAt = _remoteFailures[source];
    if (failedAt != null &&
        now.difference(failedAt) < remoteFailureRetryInterval) {
      return current;
    }

    final pending = _remoteLoads[source];
    if (pending != null) {
      try {
        return await pending;
      } catch (_) {
        if (current != null) return current;
        rethrow;
      }
    }

    final load = _refreshRemoteGuide(source, current);
    _remoteLoads[source] = load;
    try {
      final guide = await load;
      _remoteFailures.remove(source);
      _guides[source] = guide;
      return guide;
    } catch (_) {
      _remoteFailures[source] = _now();
      if (current != null) return current;
      rethrow;
    } finally {
      if (identical(_remoteLoads[source], load)) {
        _remoteLoads.remove(source);
      }
    }
  }

  Future<_CachedGuide> _refreshRemoteGuide(
    String source,
    _CachedGuide? current,
  ) async {
    final headers = <String, String>{
      'Accept': 'application/xml, text/xml, application/gzip, */*',
      if (current?.etag != null) 'If-None-Match': current!.etag!,
      if (current?.lastModifiedHeader != null)
        'If-Modified-Since': current!.lastModifiedHeader!,
    };
    final response = await _httpGet(
      Uri.parse(source),
      headers: headers,
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == HttpStatus.notModified && current != null) {
      return current.copyWith(loadedAt: _now());
    }
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('XMLTV server returned HTTP ${response.statusCode}.');
    }

    return _parseGuide(
      _decodeGuide(response.bodyBytes),
      loadedAt: _now(),
      etag: response.headers['etag'],
      lastModifiedHeader: response.headers['last-modified'],
    );
  }

  static String _decodeGuide(List<int> bytes) {
    final content = bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b
        ? gzip.decode(bytes)
        : bytes;
    return utf8.decode(content, allowMalformed: true);
  }

  static _CachedGuide _parseGuide(
    String xml, {
    required DateTime loadedAt,
    DateTime? fileModified,
    String? etag,
    String? lastModifiedHeader,
  }) {
    final document = XmlDocument.parse(xml);
    final names = <String, String>{};
    for (final channel in document.findAllElements('channel')) {
      final id = channel.getAttribute('id')?.trim() ?? '';
      if (id.isEmpty) continue;
      for (final displayName in channel.findElements('display-name')) {
        final normalized = _normalizeName(displayName.innerText);
        if (normalized.isNotEmpty) names.putIfAbsent(normalized, () => id);
      }
    }

    final programs = <String, List<EpgProgram>>{};
    for (final programme in document.findAllElements('programme')) {
      final channelId = programme.getAttribute('channel')?.trim() ?? '';
      if (channelId.isEmpty) continue;
      final title = _childText(programme, 'title');
      if (title.isEmpty) continue;
      final start = _parseXmltvTime(programme.getAttribute('start'));
      final end = _parseXmltvTime(programme.getAttribute('stop'));
      if (start == null && end == null) continue;
      (programs[channelId] ??= []).add(
        EpgProgram(
          id: '$channelId:${programme.getAttribute('start') ?? ''}:$title',
          title: title,
          description: _childText(programme, 'desc'),
          startTime: start,
          endTime: end,
          nowPlaying: false,
        ),
      );
    }
    for (final listings in programs.values) {
      listings.sort(
        (left, right) => (left.startTime ?? DateTime(0)).compareTo(
          right.startTime ?? DateTime(0),
        ),
      );
    }

    return _CachedGuide(
      loadedAt: loadedAt,
      fileModified: fileModified,
      etag: etag,
      lastModifiedHeader: lastModifiedHeader,
      programsByChannel: programs,
      channelIdsByName: names,
    );
  }

  static String _childText(XmlElement parent, String name) {
    final element = parent.findElements(name).firstOrNull;
    return element?.innerText.trim() ?? '';
  }

  static DateTime? _parseXmltvTime(String? value) {
    final text = value?.trim() ?? '';
    final match = RegExp(
      r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(?:\s*([+-]\d{2})(\d{2}))?$',
    ).firstMatch(text);
    if (match == null) return null;
    final date = DateTime.utc(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
      int.parse(match[4]!),
      int.parse(match[5]!),
      int.parse(match[6]!),
    );
    final sign = match[7];
    if (sign == null) return date.toLocal();
    final offset = Duration(
      hours: int.parse(sign.substring(1)),
      minutes: int.parse(match[8]!),
    );
    return sign.startsWith('-')
        ? date.add(offset).toLocal()
        : date.subtract(offset).toLocal();
  }

  static String _normalizeName(String value) => value.toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9\u0370-\u03ff\u1f00-\u1fff]'),
    '',
  );
}

class _CachedGuide {
  const _CachedGuide({
    required this.loadedAt,
    required this.programsByChannel,
    required this.channelIdsByName,
    this.fileModified,
    this.etag,
    this.lastModifiedHeader,
  });

  final DateTime loadedAt;
  final DateTime? fileModified;
  final String? etag;
  final String? lastModifiedHeader;
  final Map<String, List<EpgProgram>> programsByChannel;
  final Map<String, String> channelIdsByName;

  _CachedGuide copyWith({required DateTime loadedAt}) => _CachedGuide(
    loadedAt: loadedAt,
    fileModified: fileModified,
    etag: etag,
    lastModifiedHeader: lastModifiedHeader,
    programsByChannel: programsByChannel,
    channelIdsByName: channelIdsByName,
  );
}
