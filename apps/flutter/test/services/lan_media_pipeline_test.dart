import 'dart:io';
import 'package:another_iptv_player/services/lan_server/lan_library_service.dart';
import 'package:another_iptv_player/services/lan_server/lan_media_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final testFfmpeg = Platform.environment['AIPTV_TEST_FFMPEG'];
  test(
    'keeps both tagged audio streams in actual remux and transcode output',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'aiptv-audio-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final input = '${directory.path}/two-audio.mkv';
      final generated = await Process.run(testFfmpeg!, [
        '-hide_banner',
        '-loglevel',
        'error',
        '-f',
        'lavfi',
        '-i',
        'color=c=black:s=64x64:r=25',
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=440',
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=880',
        '-map',
        '0:v',
        '-map',
        '1:a',
        '-map',
        '2:a',
        '-metadata:s:a:0',
        'language=deu',
        '-metadata:s:a:1',
        'language=eng',
        '-c:v',
        'mpeg2video',
        '-c:a',
        'aac',
        '-t',
        '2',
        input,
      ]);
      expect(generated.exitCode, 0, reason: generated.stderr.toString());
      for (final transcode in [false, true]) {
        final output =
            '${directory.path}/${transcode ? 'transcode' : 'remux'}.m3u8';
        final converted = await Process.run(
          testFfmpeg,
          buildLanMediaArguments(
            source: LanPlaybackDescriptor(
              url: input,
              mimeType: 'video/x-matroska',
              isLive: false,
            ),
            transcode: transcode,
            segmentPath: '${directory.path}/${transcode}_%06d.ts',
            playlistPath: output,
          ),
        );
        expect(converted.exitCode, 0, reason: converted.stderr.toString());
        final inspected = await Process.run(testFfmpeg, [
          '-hide_banner',
          '-i',
          output,
          '-map',
          '0:a:1',
          '-f',
          'null',
          '-',
        ]);
        expect(inspected.exitCode, 0, reason: inspected.stderr.toString());
        expect(inspected.stderr.toString(), contains('(deu)'));
        expect(inspected.stderr.toString(), contains('(eng)'));
      }
    },
    skip: testFfmpeg == null
        ? 'Set AIPTV_TEST_FFMPEG to exercise local media conversion'
        : false,
  );

  test('resolves FFmpeg from explicit and environment overrides first', () {
    expect(
      resolveFfmpegExecutable(
        configured: r'C:\custom\ffmpeg.exe',
        environment: const {'AIPTV_FFMPEG': r'C:\env\ffmpeg.exe'},
        resolvedExecutable: r'C:\app\player.exe',
        currentDirectory: r'C:\work',
        isWindows: true,
      ),
      r'C:\custom\ffmpeg.exe',
    );
    expect(
      resolveFfmpegExecutable(
        environment: const {'AIPTV_FFMPEG': '/opt/ffmpeg'},
        resolvedExecutable: '/app/player',
        currentDirectory: '/work',
        isWindows: false,
      ),
      '/opt/ffmpeg',
    );
  });

  test('falls back to the platform command name', () {
    expect(
      resolveFfmpegExecutable(
        environment: const {},
        resolvedExecutable: r'Z:\missing\player.exe',
        currentDirectory: r'Z:\also-missing',
        isWindows: true,
      ),
      'ffmpeg.exe',
    );
  });

  test('keeps remux output stream-copy and preserves full source quality', () {
    final args = buildLanMediaArguments(
      source: const LanPlaybackDescriptor(
        url: 'https://example.test/movie.mkv',
        mimeType: 'video/x-matroska',
        isLive: false,
      ),
      transcode: false,
      segmentPath: 'segment_%06d.ts',
      playlistPath: 'index.m3u8',
    );

    expect(args, containsAllInOrder(['-map', '0:a?']));
    expect(args, isNot(contains('0:a:0?')));
    expect(args, containsAllInOrder(['-c', 'copy']));
    expect(args, isNot(contains('-vf')));
  });

  test('caps compatibility transcodes at 1080p with a webOS-safe level', () {
    final args = buildLanMediaArguments(
      source: const LanPlaybackDescriptor(
        url: 'https://example.test/movie-4k.mkv',
        mimeType: 'video/x-matroska',
        isLive: false,
      ),
      transcode: true,
      segmentPath: 'segment_%06d.ts',
      playlistPath: 'index.m3u8',
    );
    expect(args, containsAllInOrder(['-map', '0:a?']));
    final filterIndex = args.indexOf('-vf');
    final levelIndex = args.indexOf('-level');

    expect(filterIndex, greaterThanOrEqualTo(0));
    expect(args[filterIndex + 1], contains('min(1920,iw)'));
    expect(args[filterIndex + 1], contains('min(1080,ih)'));
    expect(args[levelIndex + 1], '4.2');
  });

  test('seeks the proxied VOD input to the selected resume point', () {
    final args = buildLanMediaArguments(
      source: const LanPlaybackDescriptor(
        url: 'https://example.test/movie-4k.mkv',
        mimeType: 'video/x-matroska',
        isLive: false,
        startPositionMs: 564191,
      ),
      transcode: true,
      segmentPath: 'segment_%06d.ts',
      playlistPath: 'index.m3u8',
    );

    expect(
      args,
      containsAllInOrder([
        '-ss',
        '564.191',
        '-i',
        'https://example.test/movie-4k.mkv',
      ]),
    );
  });

  test('never applies a saved position to a live input', () {
    final args = buildLanMediaArguments(
      source: const LanPlaybackDescriptor(
        url: 'https://example.test/live.ts',
        mimeType: 'video/mp2t',
        isLive: true,
        startPositionMs: 564191,
      ),
      transcode: true,
      segmentPath: 'segment_%06d.ts',
      playlistPath: 'index.m3u8',
    );

    expect(args, isNot(contains('-ss')));
  });

  test('allows large VOD compatibility streams longer to initialise', () {
    const vod = LanPlaybackDescriptor(
      url: 'https://example.test/movie-4k.mkv',
      mimeType: 'video/x-matroska',
      isLive: false,
    );
    const live = LanPlaybackDescriptor(
      url: 'https://example.test/live.ts',
      mimeType: 'video/mp2t',
      isLive: true,
    );

    expect(
      lanMediaStartupTimeout(source: vod, transcode: false),
      const Duration(seconds: 30),
    );
    expect(
      lanMediaStartupTimeout(source: vod, transcode: true),
      const Duration(seconds: 45),
    );
    expect(
      lanMediaStartupTimeout(source: live, transcode: true),
      const Duration(seconds: 15),
    );
  });

  test(
    'reports a clear compatibility error when FFmpeg is unavailable',
    () async {
      final pipeline = LanMediaPipeline(
        ffmpegExecutable: 'definitely-not-an-ffmpeg-executable',
      );
      addTearDown(pipeline.dispose);

      expect(
        () => pipeline.start(
          source: const LanPlaybackDescriptor(
            url: 'https://example.invalid/video.mkv',
            mimeType: 'video/x-matroska',
            isLive: false,
          ),
          deviceToken: 'device-token',
          accessGrant: 'media-grant',
          transcode: false,
        ),
        throwsA(
          isA<LanApiException>().having(
            (error) => error.code,
            'code',
            'ffmpeg_unavailable',
          ),
        ),
      );
    },
  );
}
