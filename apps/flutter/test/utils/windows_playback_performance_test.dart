import 'package:another_iptv_player/utils/windows_playback_performance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps video at or below the performance cap unchanged', () {
    expect(
      windowsPerformanceVideoSurfaceSize(width: 1920, height: 1080),
      const VideoSurfaceSize(1920, 1080),
    );
    expect(
      windowsPerformanceVideoSurfaceSize(width: 2560, height: 1440),
      const VideoSurfaceSize(2560, 1440),
    );
  });

  test('caps oversized video while preserving its aspect ratio', () {
    expect(
      windowsPerformanceVideoSurfaceSize(width: 3840, height: 2160),
      const VideoSurfaceSize(2560, 1440),
    );
    expect(
      windowsPerformanceVideoSurfaceSize(width: 4096, height: 2160),
      const VideoSurfaceSize(2560, 1350),
    );
  });

  test('accounts for rotated video and rejects missing dimensions', () {
    expect(
      windowsPerformanceVideoSurfaceSize(width: 3840, height: 2160, rotate: 90),
      const VideoSurfaceSize(810, 1440),
    );
    expect(
      windowsPerformanceVideoSurfaceSize(width: null, height: 1080),
      isNull,
    );
  });

  test('uses the lightweight HDR and scaling properties', () {
    expect(windowsPerformanceMpvProperties['hdr-compute-peak'], 'no');
    expect(windowsPerformanceMpvProperties['tone-mapping'], 'mobius');
    expect(windowsPerformanceMpvProperties['dscale'], 'bilinear');
  });
}
