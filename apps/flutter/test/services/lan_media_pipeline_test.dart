import 'package:another_iptv_player/services/lan_server/lan_library_service.dart';
import 'package:another_iptv_player/services/lan_server/lan_media_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
