import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/models/content_type.dart' as app;
import 'package:another_iptv_player/models/subtitle_search_result.dart';
import 'package:another_iptv_player/services/lan_server/lan_library_service.dart';
import 'package:another_iptv_player/services/lan_server/lan_pairing_manager.dart';
import 'package:another_iptv_player/services/lan_server/lan_media_pipeline.dart';
import 'package:another_iptv_player/services/open_subtitles_service.dart';
import 'package:flutter/foundation.dart';

class LanServerController extends ChangeNotifier {
  LanServerController({
    LanPairingManager? pairingManager,
    LanMediaPipeline? mediaPipeline,
    OpenSubtitlesService? subtitlesService,
  }) : pairing = pairingManager ?? LanPairingManager(),
       _mediaPipeline = mediaPipeline ?? LanMediaPipeline(),
       _subtitles = subtitlesService ?? OpenSubtitlesService();

  static final LanServerController instance = LanServerController();
  static const int defaultPort = 32145;

  HttpServer? _server;
  HttpClient? _httpClient;
  RawDatagramSocket? _discoverySocket;
  LanLibraryService? _library;
  final LanPairingManager pairing;
  final Map<String, _StreamTicket> _streamTickets = {};
  final Map<String, _SubtitleTicket> _subtitleTickets = {};
  final LanMediaPipeline _mediaPipeline;
  final OpenSubtitlesService _subtitles;
  final Random _random = Random.secure();
  String? _error;
  List<String> _addresses = const [];
  bool? _ffmpegAvailable;

  bool get running => _server != null;
  String? get error => _error;
  int get port => _server?.port ?? defaultPort;
  List<String> get addresses => _addresses;
  bool? get ffmpegAvailable => _ffmpegAvailable;
  String get ffmpegExecutable => _mediaPipeline.resolvedExecutable;
  String get pairingCode => pairing.pairingCode;
  DateTime get pairingCodeExpiresAt => pairing.pairingCodeExpiresAt;

  Future<void> initialize(
    AppDatabase database, {
    int port = defaultPort,
    bool enableDiscovery = true,
  }) async {
    if (kIsWeb ||
        !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return;
    }
    _library = LanLibraryService(database);
    await pairing.initialize();
    await start(port: port, enableDiscovery: enableDiscovery);
    unawaited(refreshMediaCapability());
  }

  Future<void> refreshMediaCapability() async {
    _ffmpegAvailable = await _mediaPipeline.isAvailable();
    notifyListeners();
  }

  Future<void> start({
    int port = defaultPort,
    bool enableDiscovery = true,
  }) async {
    if (_server != null || _library == null) return;
    try {
      _error = null;
      final server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        port,
        shared: true,
      );
      _server = server;
      _httpClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 20);
      _addresses = await _findLanAddresses(server.port);
      if (enableDiscovery) await _startDiscoveryResponder(server.port);
      unawaited(_serve(server));
    } catch (error) {
      _error = error.toString();
    }
    notifyListeners();
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _httpClient?.close(force: true);
    _httpClient = null;
    _discoverySocket?.close();
    _discoverySocket = null;
    _streamTickets.clear();
    _subtitleTickets.clear();
    await _mediaPipeline.dispose();
    if (server != null) await server.close(force: true);
    notifyListeners();
  }

  void refreshPairingCode() {
    pairing.rotateCode();
    notifyListeners();
  }

  Future<void> revokeDevice(String id) async {
    await pairing.revoke(id);
    notifyListeners();
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handle(request));
    }
  }

  Future<void> _startDiscoveryResponder(int port) async {
    _discoverySocket?.close();
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        32146,
        reuseAddress: true,
      );
      _discoverySocket = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        final probe = utf8.decode(datagram.data, allowMalformed: true).trim();
        if (probe != 'AIPTV_DISCOVER_V1') return;
        final payload = utf8.encode(
          jsonEncode(<String, Object?>{
            'protocol': 'AIPTV_DISCOVER_V1',
            'name': 'Another IPTV Player',
            'serverName': Platform.localHostname,
            'port': port,
            'addresses': _addresses,
          }),
        );
        socket.send(payload, datagram.address, datagram.port);
      });
    } catch (error) {
      debugPrint('LAN discovery responder unavailable: $error');
    }
  }

  Future<void> _handle(HttpRequest request) async {
    _applyCommonHeaders(request.response);
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/api/v1/local/pairing') {
        if (request.connectionInfo?.remoteAddress.isLoopback != true) {
          throw const LanApiException(
            HttpStatus.forbidden,
            'local_only',
            'Pairing diagnostics are available only on this computer',
          );
        }
        await _json(request.response, HttpStatus.ok, <String, Object?>{
          'pairingCode': pairing.pairingCode,
          'pairingExpiresAt': pairing.pairingCodeExpiresAt
              .toUtc()
              .toIso8601String(),
        });
        return;
      }
      if (request.method == 'GET' && path == '/api/v1/status') {
        await _json(request.response, HttpStatus.ok, <String, Object?>{
          'apiVersion': 1,
          'name': 'Another IPTV Player',
          'serverName': Platform.localHostname,
          'pairingAvailable': pairing.pairingAvailable,
          'pairingExpiresAt': pairing.pairingCodeExpiresAt
              .toUtc()
              .toIso8601String(),
          'ffmpegAvailable': _ffmpegAvailable,
        });
        return;
      }
      if (request.method == 'POST' && path == '/api/v1/pair') {
        final body = await _readJson(request);
        try {
          final device = await pairing.pair(
            code: _string(body['code']),
            deviceName: _string(body['deviceName']),
          );
          notifyListeners();
          await _json(request.response, HttpStatus.ok, <String, Object?>{
            'apiVersion': 1,
            'deviceId': device.id,
            'deviceName': device.name,
            'token': device.token,
          });
        } on PairingRejectedException {
          throw const LanApiException(
            401,
            'pairing_rejected',
            'Pairing code is invalid or expired',
          );
        }
        return;
      }

      // Native video and text tracks cannot attach Authorization headers.
      // These routes use short-lived random grants while retaining the paired
      // device token only in server memory for immediate revocation checks.
      if (request.method == 'GET' && path.startsWith('/api/v1/stream/')) {
        await _proxyStream(request, path.substring('/api/v1/stream/'.length));
        return;
      }
      if (request.method == 'GET' && path.startsWith('/api/v1/media/')) {
        await _serveMediaFile(request, path);
        return;
      }
      if (request.method == 'GET' &&
          path.startsWith('/api/v1/subtitles/file/')) {
        await _serveSubtitle(
          request,
          path.substring('/api/v1/subtitles/file/'.length),
        );
        return;
      }

      final token = _requestToken(request);
      if (!await pairing.acceptsAndTouch(token)) {
        throw const LanApiException(
          401,
          'unauthorized',
          'A valid device token is required',
        );
      }

      final library = _library!;
      if (request.method == 'DELETE' && path.startsWith('/api/v1/media/')) {
        final sessionId = path.substring('/api/v1/media/'.length);
        if (sessionId.isEmpty || sessionId.contains('/')) {
          throw const LanApiException(
            400,
            'invalid_media_session',
            'A media session identity is required',
          );
        }
        if (!await _mediaPipeline.stopForDevice(sessionId, token)) {
          throw const LanApiException(
            404,
            'media_expired',
            'Media session is unavailable',
          );
        }
        await _json(request.response, HttpStatus.noContent, null);
        return;
      }
      if (request.method == 'GET' && path == '/api/v1/playlists') {
        await _ok(request.response, await library.playlists());
        return;
      }
      if (request.method == 'GET' && path == '/api/v1/categories') {
        await _ok(
          request.response,
          await library.categories(
            playlistId: _requiredQuery(request, 'playlistId'),
            contentType: contentTypeFromWire(_requiredQuery(request, 'type')),
          ),
        );
        return;
      }
      if (request.method == 'GET' && path == '/api/v1/items') {
        await _ok(
          request.response,
          await library.items(
            playlistId: _requiredQuery(request, 'playlistId'),
            contentType: contentTypeFromWire(_requiredQuery(request, 'type')),
            itemId: request.uri.queryParameters['itemId'],
            categoryId: request.uri.queryParameters['categoryId'],
            query: request.uri.queryParameters['query'] ?? '',
            sort: request.uri.queryParameters['sort'] ?? '',
            offset: _queryInt(request, 'offset', 0),
            limit: _queryInt(request, 'limit', 100),
          ),
        );
        return;
      }
      if (request.method == 'GET' && path == '/api/v1/shelves') {
        await _ok(
          request.response,
          await library.shelves(
            playlistId: _requiredQuery(request, 'playlistId'),
            contentType: contentTypeFromWire(_requiredQuery(request, 'type')),
            limit: _queryInt(request, 'limit', 30),
          ),
        );
        return;
      }
      if (request.method == 'GET' && path == '/api/v1/item') {
        await _ok(
          request.response,
          await library.item(
            playlistId: _requiredQuery(request, 'playlistId'),
            contentType: contentTypeFromWire(_requiredQuery(request, 'type')),
            itemId: _requiredQuery(request, 'itemId'),
          ),
        );
        return;
      }
      if (request.method == 'GET' && path.startsWith('/api/v1/series/')) {
        await _ok(
          request.response,
          await library.seriesDetails(
            playlistId: _requiredQuery(request, 'playlistId'),
            seriesId: Uri.decodeComponent(
              path.substring('/api/v1/series/'.length),
            ),
          ),
        );
        return;
      }
      if (request.method == 'GET' && path.startsWith('/api/v1/vod/')) {
        await _ok(
          request.response,
          await library.vodDetails(
            playlistId: _requiredQuery(request, 'playlistId'),
            vodId: Uri.decodeComponent(path.substring('/api/v1/vod/'.length)),
          ),
        );
        return;
      }
      if (request.method == 'GET' && path == '/api/v1/search') {
        final playlistId = _requiredQuery(request, 'playlistId');
        final query = _requiredQuery(request, 'query');
        final limit = _queryInt(request, 'limit', 40).clamp(1, 100);
        final results = <Object?>[];
        for (final type in app.ContentType.values) {
          final page = await library.items(
            playlistId: playlistId,
            contentType: type,
            query: query,
            limit: limit,
          );
          results.addAll((page['items'] as List).take(limit - results.length));
          if (results.length >= limit) break;
        }
        await _ok(request.response, results);
        return;
      }
      if (request.method == 'GET' && path == '/api/v1/epg') {
        await _ok(
          request.response,
          await library.epg(
            playlistId: _requiredQuery(request, 'playlistId'),
            streamId: _requiredQuery(request, 'streamId'),
            limit: _queryInt(request, 'limit', 8).clamp(1, 50),
          ),
        );
        return;
      }
      if (request.method == 'GET' && path == '/api/v1/preferences') {
        await _ok(
          request.response,
          await library.preferences(_requiredQuery(request, 'playlistId')),
        );
        return;
      }
      if (request.method == 'PATCH' && path == '/api/v1/preferences') {
        final playlistId = _requiredQuery(request, 'playlistId');
        final body = await _readJson(request);
        await _ok(
          request.response,
          await library.patchPreferences(playlistId, body),
        );
        return;
      }
      if (request.method == 'GET' && path == '/api/v1/shortcuts') {
        await _ok(
          request.response,
          await library.shortcuts(
            _requiredQuery(request, 'playlistId'),
            page: request.uri.queryParameters['page'] ?? 'A',
          ),
        );
        return;
      }
      if (request.method == 'POST' && path == '/api/v1/subtitles/search') {
        final body = await _readJson(request);
        final results = await _subtitles.search(
          title: _requiredString(body, 'title'),
          contentType: contentTypeFromWire(_requiredString(body, 'type')),
          query: _optionalString(body['query']),
          languages: _optionalString(body['languages']),
          imdbId: _optionalString(body['imdbId']),
          season: _optionalInt(body['season']),
        );
        await _ok(
          request.response,
          results.map(_subtitleResultJson).toList(growable: false),
        );
        return;
      }
      if (request.method == 'GET' && path == '/api/v1/subtitles/cached') {
        final contentKey = _subtitleContentKey(
          playlistId: _requiredQuery(request, 'playlistId'),
          contentType: contentTypeFromWire(_requiredQuery(request, 'type')),
          itemId: _requiredQuery(request, 'itemId'),
          episodeId: request.uri.queryParameters['episodeId'],
        );
        final cached = await _subtitles.cachedForKey(contentKey);
        await _ok(
          request.response,
          cached == null ? null : _subtitleDescriptor(request, cached, token),
        );
        return;
      }
      if (request.method == 'POST' && path == '/api/v1/subtitles/download') {
        final body = await _readJson(request);
        final contentType = contentTypeFromWire(_requiredString(body, 'type'));
        final contentKey = _subtitleContentKey(
          playlistId: _requiredString(body, 'playlistId'),
          contentType: contentType,
          itemId: _requiredString(body, 'itemId'),
          episodeId: _optionalString(body['episodeId']),
        );
        final resultBody = body['result'];
        if (resultBody is! Map) {
          throw const LanApiException(
            400,
            'invalid_subtitle',
            'Subtitle result is required',
          );
        }
        final result = _subtitleResultFromJson(
          Map<String, Object?>.from(resultBody),
        );
        final cached = await _subtitles.download(
          contentKey: contentKey,
          contentName: _requiredString(body, 'title'),
          subtitle: result,
          preferredFormat: 'srt',
        );
        await _ok(
          request.response,
          _subtitleDescriptor(request, cached, token),
        );
        return;
      }
      if (request.method == 'PATCH' && path == '/api/v1/subtitles/offset') {
        final body = await _readJson(request);
        final contentKey = _subtitleContentKey(
          playlistId: _requiredString(body, 'playlistId'),
          contentType: contentTypeFromWire(_requiredString(body, 'type')),
          itemId: _requiredString(body, 'itemId'),
          episodeId: _optionalString(body['episodeId']),
        );
        final offsetMs = _int(body['offsetMs']).clamp(-30000, 30000);
        await _subtitles.saveOffsetForKey(contentKey, offsetMs / 1000);
        await _ok(request.response, <String, Object?>{'offsetMs': offsetMs});
        return;
      }
      if (path == '/api/v1/favorites' && request.method == 'GET') {
        await _ok(
          request.response,
          await library.favorites(
            playlistId: request.uri.queryParameters['playlistId'],
          ),
        );
        return;
      }
      if (path.startsWith('/api/v1/favorites/')) {
        final identity = _parseTypedIdentity(path, '/api/v1/favorites/');
        if (request.method == 'PUT') {
          final body = await _readJson(request);
          await _ok(
            request.response,
            await library.putFavorite(
              playlistId: _requiredString(body, 'playlistId'),
              contentType: identity.$1,
              itemId: identity.$2,
              name: _requiredString(body, 'name'),
              imageUrl: _optionalString(body['imageUrl']),
              m3uItemId: _optionalString(body['m3uItemId']),
            ),
          );
          return;
        }
        if (request.method == 'DELETE') {
          await library.deleteFavorite(
            playlistId: _requiredQuery(request, 'playlistId'),
            contentType: identity.$1,
            itemId: identity.$2,
          );
          await _json(request.response, HttpStatus.noContent, null);
          return;
        }
      }
      if (path == '/api/v1/history' && request.method == 'GET') {
        await _ok(
          request.response,
          await library.history(
            playlistId: _requiredQuery(request, 'playlistId'),
          ),
        );
        return;
      }
      if (path == '/api/v1/history' && request.method == 'DELETE') {
        await library.clearHistory(_requiredQuery(request, 'playlistId'));
        await _json(request.response, HttpStatus.noContent, null);
        return;
      }
      if (path.startsWith('/api/v1/history/')) {
        final identity = _parseTypedIdentity(path, '/api/v1/history/');
        if (request.method == 'PUT') {
          final body = await _readJson(request);
          await _ok(
            request.response,
            await library.putHistory(
              playlistId: _requiredString(body, 'playlistId'),
              contentType: identity.$1,
              itemId: identity.$2,
              title: _requiredString(body, 'title'),
              seriesId: _optionalString(body['seriesId']),
              imageUrl: _optionalString(body['imageUrl']),
              positionMs: _int(body['positionMs']),
              durationMs: _int(body['durationMs']),
            ),
          );
          return;
        }
        if (request.method == 'DELETE') {
          await library.deleteHistory(
            playlistId: _requiredQuery(request, 'playlistId'),
            itemId: identity.$2,
          );
          await _json(request.response, HttpStatus.noContent, null);
          return;
        }
      }
      if (path == '/api/v1/playback' && request.method == 'POST') {
        final body = await _readJson(request);
        final descriptor = await library.playback(
          playlistId: _requiredString(body, 'playlistId'),
          contentType: contentTypeFromWire(_requiredString(body, 'type')),
          itemId: _requiredString(body, 'itemId'),
          episodeId: _optionalString(body['episodeId']),
        );
        final modePreference = _string(body['modePreference']);
        if (modePreference == 'remux' || modePreference == 'transcode') {
          final accessGrant = _newGrant();
          final session = await _mediaPipeline.start(
            source: descriptor,
            deviceToken: token,
            accessGrant: accessGrant,
            transcode: modePreference == 'transcode',
          );
          await _ok(request.response, <String, Object?>{
            'mode': modePreference,
            'url':
                '${_requestOrigin(request)}/api/v1/media/${session.id}/index.m3u8?access_token=${Uri.encodeQueryComponent(accessGrant)}',
            'mimeType': 'application/vnd.apple.mpegurl',
            'isLive': descriptor.isLive,
            'startPositionMs': descriptor.startPositionMs,
            'expiresAt': session.expiresAt.toUtc().toIso8601String(),
          });
          return;
        }
        final expiresAt = DateTime.now().toUtc().add(
          const Duration(minutes: 30),
        );
        // Playback URLs can embed Xtream credentials or provider tokens. Keep
        // them desktop-side even if an older client asks for direct playback.
        final ticket = _createStreamTicket(descriptor, token, expiresAt);
        final url =
            '${_requestOrigin(request)}/api/v1/stream/${ticket.id}?access_token=${Uri.encodeQueryComponent(ticket.accessGrant)}';
        final mode = descriptor.mimeType == 'application/vnd.apple.mpegurl'
            ? 'hls'
            : 'proxy';
        await _ok(request.response, <String, Object?>{
          'mode': mode,
          'url': url,
          'mimeType': descriptor.mimeType,
          'isLive': descriptor.isLive,
          'startPositionMs': descriptor.startPositionMs,
          'expiresAt': expiresAt.toIso8601String(),
        });
        return;
      }
      throw const LanApiException(404, 'not_found', 'Endpoint not found');
    } on LanApiException catch (error) {
      await _errorJson(
        request.response,
        error.statusCode,
        error.code,
        error.message,
      );
    } on FormatException catch (error) {
      await _errorJson(request.response, 400, 'invalid_request', error.message);
    } catch (error, stackTrace) {
      debugPrint('LAN server request failed: $error\n$stackTrace');
      await _errorJson(
        request.response,
        500,
        'internal_error',
        'The request could not be completed',
      );
    }
  }

  Future<void> _proxyStream(HttpRequest incoming, String ticketId) async {
    _pruneTickets();
    final ticket = _streamTickets[ticketId];
    final accessGrant = _requestToken(incoming);
    if (ticket == null ||
        ticket.accessGrant != accessGrant ||
        DateTime.now().isAfter(ticket.expiresAt)) {
      throw const LanApiException(
        404,
        'stream_expired',
        'Playback ticket is invalid or expired',
      );
    }
    if (!await pairing.acceptsAndTouch(ticket.deviceToken)) {
      throw const LanApiException(
        401,
        'device_revoked',
        'The paired device is no longer authorized',
      );
    }
    final client = _httpClient;
    if (client == null) {
      throw const LanApiException(
        503,
        'server_stopped',
        'Stream proxy is unavailable',
      );
    }
    final upstream = await client.getUrl(Uri.parse(ticket.descriptor.url));
    ticket.descriptor.headers.forEach(upstream.headers.set);
    final range = incoming.headers.value(HttpHeaders.rangeHeader);
    if (range != null) upstream.headers.set(HttpHeaders.rangeHeader, range);
    upstream.followRedirects = true;
    upstream.maxRedirects = 5;
    final response = await upstream.close();
    final contentType = response.headers.contentType?.mimeType ?? '';
    final isHls =
        contentType.contains('mpegurl') ||
        ticket.descriptor.mimeType == 'application/vnd.apple.mpegurl' ||
        Uri.parse(ticket.descriptor.url).path.toLowerCase().endsWith('.m3u8');
    if (isHls && response.statusCode >= 200 && response.statusCode < 300) {
      final manifest = await utf8.decoder.bind(response).join();
      final rewritten = _rewriteHlsManifest(
        manifest,
        Uri.parse(ticket.descriptor.url),
        ticket,
        requestOrigin: _requestOrigin(incoming),
      );
      incoming.response
        ..statusCode = response.statusCode
        ..headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
          charset: 'utf-8',
        )
        ..write(rewritten);
      await incoming.response.close();
      return;
    }
    incoming.response.statusCode = response.statusCode;
    for (final header in const [
      HttpHeaders.contentTypeHeader,
      HttpHeaders.contentLengthHeader,
      HttpHeaders.contentRangeHeader,
      HttpHeaders.acceptRangesHeader,
      HttpHeaders.cacheControlHeader,
    ]) {
      final value = response.headers.value(header);
      if (value != null) incoming.response.headers.set(header, value);
    }
    await response.pipe(incoming.response);
  }

  Future<void> _serveMediaFile(HttpRequest request, String path) async {
    final parts = path.substring('/api/v1/media/'.length).split('/');
    if (parts.length != 2 || parts[1].contains('..')) {
      throw const LanApiException(
        400,
        'invalid_media_path',
        'Invalid media path',
      );
    }
    final accessGrant = _requestToken(request);
    final session = _mediaPipeline.find(parts[0], accessGrant);
    if (session == null) {
      throw const LanApiException(
        404,
        'media_expired',
        'Media session is unavailable',
      );
    }
    if (!await pairing.acceptsAndTouch(session.deviceToken)) {
      throw const LanApiException(
        401,
        'device_revoked',
        'The paired device is no longer authorized',
      );
    }
    final file = File(
      '${session.directory.path}${Platform.pathSeparator}${parts[1]}',
    );
    if (!await file.exists()) {
      throw const LanApiException(
        404,
        'media_not_ready',
        'Media segment is not ready',
      );
    }
    if (parts[1].endsWith('.m3u8')) {
      final manifest = await file.readAsString();
      final suffix =
          '?access_token=${Uri.encodeQueryComponent(session.accessGrant)}';
      request.response
        ..headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
          charset: 'utf-8',
        )
        ..write(
          manifest
              .split('\n')
              .map((line) {
                final trimmed = line.trim();
                return trimmed.isNotEmpty && !trimmed.startsWith('#')
                    ? '$trimmed$suffix'
                    : line;
              })
              .join('\n'),
        );
      await request.response.close();
      return;
    }
    request.response.headers
      ..contentType = ContentType('video', 'mp2t')
      ..set(HttpHeaders.cacheControlHeader, 'no-store');
    await file.openRead().pipe(request.response);
  }

  Future<void> _serveSubtitle(HttpRequest request, String ticketId) async {
    _pruneTickets();
    final ticket = _subtitleTickets[ticketId];
    final accessGrant = _requestToken(request);
    if (ticket == null ||
        ticket.accessGrant != accessGrant ||
        DateTime.now().isAfter(ticket.expiresAt)) {
      throw const LanApiException(
        404,
        'subtitle_expired',
        'Subtitle link is invalid or expired',
      );
    }
    if (!await pairing.acceptsAndTouch(ticket.deviceToken)) {
      throw const LanApiException(
        401,
        'device_revoked',
        'The paired device is no longer authorized',
      );
    }
    final file = File(ticket.path);
    if (!await file.exists()) {
      throw const LanApiException(
        404,
        'subtitle_missing',
        'Subtitle file is unavailable',
      );
    }
    final source = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    request.response.headers.contentType = ContentType(
      'text',
      'vtt',
      charset: 'utf-8',
    );
    request.response.write(subtitleToWebVtt(source));
    await request.response.close();
  }

  Map<String, Object?> _subtitleDescriptor(
    HttpRequest request,
    CachedSubtitle cached,
    String deviceToken,
  ) {
    final expiresAt = DateTime.now().toUtc().add(const Duration(hours: 4));
    final ticketId = _newGrant();
    final accessGrant = _newGrant();
    _subtitleTickets[ticketId] = _SubtitleTicket(
      path: cached.filePath,
      deviceToken: deviceToken,
      accessGrant: accessGrant,
      expiresAt: expiresAt,
    );
    return <String, Object?>{
      'url':
          '${_requestOrigin(request)}/api/v1/subtitles/file/$ticketId?access_token=${Uri.encodeQueryComponent(accessGrant)}',
      'title': cached.title,
      'language': cached.language,
      'offsetMs': (cached.offsetSeconds * 1000).round(),
      'expiresAt': expiresAt.toIso8601String(),
    };
  }

  ({String id, String accessGrant}) _createStreamTicket(
    LanPlaybackDescriptor descriptor,
    String deviceToken,
    DateTime expiresAt,
  ) {
    final id = _newGrant();
    final accessGrant = _newGrant();
    _streamTickets[id] = _StreamTicket(
      descriptor: descriptor,
      deviceToken: deviceToken,
      accessGrant: accessGrant,
      expiresAt: expiresAt,
    );
    return (id: id, accessGrant: accessGrant);
  }

  String _newGrant() => base64UrlEncode(
    List<int>.generate(18, (_) => _random.nextInt(256)),
  ).replaceAll('=', '');

  String _rewriteHlsManifest(
    String manifest,
    Uri manifestUri,
    _StreamTicket parent, {
    required String requestOrigin,
  }) {
    String ticketFor(String reference) {
      if (reference.startsWith('data:')) return reference;
      final resolved = manifestUri.resolve(reference).toString();
      final descriptor = LanPlaybackDescriptor(
        url: resolved,
        mimeType: resolved.toLowerCase().contains('.m3u8')
            ? 'application/vnd.apple.mpegurl'
            : 'application/octet-stream',
        isLive: parent.descriptor.isLive,
        headers: parent.descriptor.headers,
      );
      final ticket = _createStreamTicket(
        descriptor,
        parent.deviceToken,
        parent.expiresAt,
      );
      return '$requestOrigin/api/v1/stream/${ticket.id}?access_token=${Uri.encodeQueryComponent(ticket.accessGrant)}';
    }

    return manifest
        .split('\n')
        .map((line) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) return line;
          if (!trimmed.startsWith('#')) return ticketFor(trimmed);
          return line.replaceAllMapped(
            RegExp(r'URI="([^"]+)"'),
            (match) => 'URI="${ticketFor(match.group(1)!)}"',
          );
        })
        .join('\n');
  }

  void _pruneTickets() {
    final now = DateTime.now();
    _streamTickets.removeWhere((_, ticket) => now.isAfter(ticket.expiresAt));
    _subtitleTickets.removeWhere((_, ticket) => now.isAfter(ticket.expiresAt));
  }
}

class _StreamTicket {
  const _StreamTicket({
    required this.descriptor,
    required this.deviceToken,
    required this.accessGrant,
    required this.expiresAt,
  });

  final LanPlaybackDescriptor descriptor;
  final String deviceToken;
  final String accessGrant;
  final DateTime expiresAt;
}

class _SubtitleTicket {
  const _SubtitleTicket({
    required this.path,
    required this.deviceToken,
    required this.accessGrant,
    required this.expiresAt,
  });

  final String path;
  final String deviceToken;
  final String accessGrant;
  final DateTime expiresAt;
}

String subtitleToWebVtt(String source) {
  var normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  normalized = normalized.replaceFirst('\ufeff', '').trimLeft();
  if (normalized.startsWith('WEBVTT')) return normalized;
  normalized = normalized.replaceAllMapped(
    RegExp(r'(\d{1,2}:\d{2}:\d{2}),(\d{3})'),
    (match) => '${match.group(1)}.${match.group(2)}',
  );
  return 'WEBVTT\n\n$normalized';
}

Map<String, Object?> _subtitleResultJson(SubtitleSearchResult result) => {
  'fileId': result.fileId,
  'subtitleId': result.subtitleId,
  'language': result.language,
  'title': result.title,
  'releaseName': result.releaseName,
  'format': result.format,
  'hearingImpaired': result.hearingImpaired,
  'downloadCount': result.downloadCount,
  'rating': result.rating,
};

SubtitleSearchResult _subtitleResultFromJson(Map<String, Object?> json) {
  final fileId = _int(json['fileId']);
  if (fileId <= 0) {
    throw const LanApiException(
      400,
      'invalid_subtitle',
      'Subtitle file identity is invalid',
    );
  }
  return SubtitleSearchResult(
    fileId: fileId,
    subtitleId: _string(json['subtitleId']),
    language: _string(json['language']),
    title: _string(json['title']),
    releaseName: _string(json['releaseName']),
    format: _string(json['format']).isEmpty ? 'srt' : _string(json['format']),
    hearingImpaired: json['hearingImpaired'] == true,
    downloadCount: _int(json['downloadCount']),
    rating: json['rating'] is num ? (json['rating'] as num).toDouble() : null,
  );
}

String _subtitleContentKey({
  required String playlistId,
  required app.ContentType contentType,
  required String itemId,
  String? episodeId,
}) => '$playlistId:${contentType.name}:${episodeId ?? itemId}';

Future<List<String>> _findLanAddresses(int port) async {
  final result = <String>[];
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback && !address.isLinkLocal) {
          result.add('http://${address.address}:$port');
        }
      }
    }
  } catch (_) {
    // The server remains usable by manually entering the desktop IP.
  }
  return result.toSet().toList()..sort();
}

void _applyCommonHeaders(HttpResponse response) {
  response.headers
    ..set(HttpHeaders.accessControlAllowOriginHeader, '*')
    ..set(
      HttpHeaders.accessControlAllowHeadersHeader,
      'Authorization, Content-Type',
    )
    ..set(
      HttpHeaders.accessControlAllowMethodsHeader,
      'GET, POST, PUT, PATCH, DELETE, OPTIONS',
    )
    ..set('X-Content-Type-Options', 'nosniff')
    ..set('Cache-Control', 'no-store');
}

Future<Map<String, Object?>> _readJson(HttpRequest request) async {
  final buffer = BytesBuilder(copy: false);
  var length = 0;
  await for (final chunk in request) {
    length += chunk.length;
    if (length > 64 * 1024) {
      throw const LanApiException(
        413,
        'body_too_large',
        'Request body is too large',
      );
    }
    buffer.add(chunk);
  }
  if (length == 0) return <String, Object?>{};
  final decoded = jsonDecode(utf8.decode(buffer.takeBytes()));
  if (decoded is! Map) {
    throw const FormatException('JSON body must be an object');
  }
  return Map<String, Object?>.from(decoded);
}

Future<void> _ok(HttpResponse response, Object? data) => _json(
  response,
  HttpStatus.ok,
  <String, Object?>{'apiVersion': 1, 'data': data},
);

Future<void> _errorJson(
  HttpResponse response,
  int status,
  String code,
  String message,
) => _json(response, status, <String, Object?>{
  'apiVersion': 1,
  'error': <String, String>{'code': code, 'message': message},
});

Future<void> _json(HttpResponse response, int status, Object? value) async {
  response.statusCode = status;
  if (status != HttpStatus.noContent) {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(value));
  }
  await response.close();
}

String _requestToken(HttpRequest request) {
  final auth = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
  if (auth.toLowerCase().startsWith('bearer ')) {
    return auth.substring(7).trim();
  }
  return request.uri.queryParameters['access_token'] ?? '';
}

String _requestOrigin(HttpRequest request) {
  final host = request.headers.host;
  if (host == null || host.isEmpty) {
    return 'http://127.0.0.1:${LanServerController.defaultPort}';
  }
  final formattedHost = host.contains(':') ? '[$host]' : host;
  final port = request.headers.port;
  return port == null || port == 80 || port <= 0
      ? 'http://$formattedHost'
      : 'http://$formattedHost:$port';
}

String _requiredQuery(HttpRequest request, String name) {
  final value = request.uri.queryParameters[name]?.trim() ?? '';
  if (value.isEmpty) {
    throw LanApiException(400, 'missing_parameter', '$name is required');
  }
  return value;
}

int _queryInt(HttpRequest request, String name, int fallback) =>
    int.tryParse(request.uri.queryParameters[name] ?? '') ?? fallback;

String _requiredString(Map<String, Object?> body, String name) {
  final value = _string(body[name]).trim();
  if (value.isEmpty) {
    throw LanApiException(400, 'missing_parameter', '$name is required');
  }
  return value;
}

String _string(Object? value) =>
    value is String ? value : value?.toString() ?? '';
String? _optionalString(Object? value) {
  final result = _string(value).trim();
  return result.isEmpty ? null : result;
}

int _int(Object? value) => value is int ? value : int.tryParse('$value') ?? 0;
int? _optionalInt(Object? value) {
  if (value == null) return null;
  return value is int ? value : int.tryParse('$value');
}

(app.ContentType, String) _parseTypedIdentity(String path, String prefix) {
  final segments = path.substring(prefix.length).split('/');
  if (segments.length != 2) {
    throw const LanApiException(
      400,
      'invalid_identity',
      'Type and item identity are required',
    );
  }
  return (contentTypeFromWire(segments[0]), Uri.decodeComponent(segments[1]));
}
