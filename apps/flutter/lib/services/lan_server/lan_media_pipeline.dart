import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:another_iptv_player/services/lan_server/lan_library_service.dart';

class LanMediaPipeline {
  LanMediaPipeline({String? ffmpegExecutable})
    : _configuredFfmpegExecutable = ffmpegExecutable;

  final String? _configuredFfmpegExecutable;
  final Random _random = Random.secure();
  final Map<String, LanMediaSession> _sessions = {};

  String get resolvedExecutable => resolveFfmpegExecutable(
    configured: _configuredFfmpegExecutable,
    environment: Platform.environment,
    resolvedExecutable: Platform.resolvedExecutable,
    currentDirectory: Directory.current.path,
    isWindows: Platform.isWindows,
  );

  Future<bool> isAvailable() async {
    try {
      final result = await Process.run(resolvedExecutable, const [
        '-version',
      ], runInShell: false).timeout(const Duration(seconds: 5));
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }

  Future<LanMediaSession> start({
    required LanPlaybackDescriptor source,
    required String deviceToken,
    required String accessGrant,
    required bool transcode,
  }) async {
    await prune();
    final id = base64UrlEncode(
      List<int>.generate(18, (_) => _random.nextInt(256)),
    ).replaceAll('=', '');
    final directory = await Directory.systemTemp.createTemp('aiptv-media-');
    final playlistPath = '${directory.path}${Platform.pathSeparator}index.m3u8';
    final segmentPath =
        '${directory.path}${Platform.pathSeparator}segment_%06d.ts';
    final args = <String>[
      '-hide_banner',
      '-loglevel',
      'warning',
      if (source.headers.isNotEmpty) ...[
        '-headers',
        '${source.headers.entries.map((entry) => '${entry.key}: ${entry.value}').join('\r\n')}\r\n',
      ],
      '-i',
      source.url,
      '-map',
      '0:v:0?',
      '-map',
      '0:a:0?',
      if (transcode) ...[
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-crf',
        '23',
        '-pix_fmt',
        'yuv420p',
        '-profile:v',
        'high',
        '-level',
        '4.1',
        '-c:a',
        'aac',
        '-b:a',
        '160k',
        '-ac',
        '2',
      ] else ...[
        '-c',
        'copy',
      ],
      '-f',
      'hls',
      '-hls_time',
      '4',
      '-hls_list_size',
      source.isLive ? '8' : '0',
      '-hls_flags',
      source.isLive
          ? 'delete_segments+append_list+independent_segments'
          : 'independent_segments',
      '-hls_segment_filename',
      segmentPath,
      playlistPath,
    ];

    Process process;
    try {
      process = await Process.start(
        resolvedExecutable,
        args,
        runInShell: false,
      );
    } on ProcessException {
      await directory.delete(recursive: true);
      throw const LanApiException(
        503,
        'ffmpeg_unavailable',
        'FFmpeg is required for compatibility playback but was not found',
      );
    }
    unawaited(process.stdout.drain<void>());
    final stderr = <String>[];
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (stderr.length >= 20) stderr.removeAt(0);
          stderr.add(line);
        });

    final session = LanMediaSession(
      id: id,
      deviceToken: deviceToken,
      accessGrant: accessGrant,
      directory: directory,
      process: process,
      expiresAt: DateTime.now().add(const Duration(hours: 4)),
      transcode: transcode,
      stderr: stderr,
    );
    _sessions[id] = session;
    unawaited(process.exitCode.then((_) => session.finished = true));

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    final playlist = File(playlistPath);
    while (!await playlist.exists()) {
      if (session.finished || DateTime.now().isAfter(deadline)) {
        await stop(id);
        throw LanApiException(
          502,
          'media_pipeline_failed',
          stderr.isEmpty
              ? 'FFmpeg did not produce a playable stream'
              : stderr.last,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return session;
  }

  LanMediaSession? find(String id, String accessGrant) {
    final session = _sessions[id];
    if (session == null || session.accessGrant != accessGrant) return null;
    return session;
  }

  Future<bool> stopForDevice(String id, String deviceToken) async {
    final session = _sessions[id];
    if (session == null || session.deviceToken != deviceToken) return false;
    await stop(id);
    return true;
  }

  Future<void> stop(String id) async {
    final session = _sessions.remove(id);
    if (session == null) return;
    if (!session.finished) {
      session.process.kill();
      try {
        await session.process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        session.process.kill(ProcessSignal.sigkill);
      }
    }
    try {
      if (await session.directory.exists()) {
        await session.directory.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<void> prune() async {
    final now = DateTime.now();
    final stale = _sessions.values
        .where((session) => now.isAfter(session.expiresAt))
        .map((session) => session.id)
        .toList();
    for (final id in stale) {
      await stop(id);
    }
  }

  Future<void> dispose() async {
    for (final id in _sessions.keys.toList()) {
      await stop(id);
    }
  }
}

String resolveFfmpegExecutable({
  String? configured,
  required Map<String, String> environment,
  required String resolvedExecutable,
  required String currentDirectory,
  required bool isWindows,
}) {
  final explicit = configured?.trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final environmentPath = environment['AIPTV_FFMPEG']?.trim();
  if (environmentPath != null && environmentPath.isNotEmpty) {
    return environmentPath;
  }

  final executableName = isWindows ? 'ffmpeg.exe' : 'ffmpeg';
  final appDirectory = File(resolvedExecutable).parent.path;
  final candidates = <String>[
    '$appDirectory${Platform.pathSeparator}$executableName',
    '$appDirectory${Platform.pathSeparator}tools${Platform.pathSeparator}ffmpeg${Platform.pathSeparator}$executableName',
    '$currentDirectory${Platform.pathSeparator}$executableName',
    '$currentDirectory${Platform.pathSeparator}tools${Platform.pathSeparator}ffmpeg${Platform.pathSeparator}$executableName',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }
  return executableName;
}

class LanMediaSession {
  LanMediaSession({
    required this.id,
    required this.deviceToken,
    required this.accessGrant,
    required this.directory,
    required this.process,
    required this.expiresAt,
    required this.transcode,
    required this.stderr,
  });

  final String id;
  final String deviceToken;
  final String accessGrant;
  final Directory directory;
  final Process process;
  final DateTime expiresAt;
  final bool transcode;
  final List<String> stderr;
  bool finished = false;
}
