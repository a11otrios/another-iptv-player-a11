import 'dart:math' as math;

const int windowsPerformanceMaxVideoWidth = 2560;
const int windowsPerformanceMaxVideoHeight = 1440;

const Map<String, String> windowsPerformanceMpvProperties = {
  // Per-frame HDR peak detection uses compute shaders and can stutter on some
  // Windows hybrid-GPU paths. Static metadata still drives tone mapping.
  'hdr-compute-peak': 'no',
  'tone-mapping': 'mobius',
  // Prefer inexpensive texture filtering in the opt-in performance mode.
  'scale': 'bilinear',
  'cscale': 'bilinear',
  'dscale': 'bilinear',
};

class VideoSurfaceSize {
  const VideoSurfaceSize(this.width, this.height);

  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is VideoSurfaceSize &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '${width}x$height';
}

VideoSurfaceSize? windowsPerformanceVideoSurfaceSize({
  required int? width,
  required int? height,
  int? rotate,
}) {
  if (width == null || height == null || width <= 0 || height <= 0) {
    return null;
  }

  var displayWidth = width;
  var displayHeight = height;
  if (rotate == 90 || rotate == 270) {
    displayWidth = height;
    displayHeight = width;
  }

  final scale = math.min(
    1.0,
    math.min(
      windowsPerformanceMaxVideoWidth / displayWidth,
      windowsPerformanceMaxVideoHeight / displayHeight,
    ),
  );

  return VideoSurfaceSize(
    _positiveEvenDimension(displayWidth * scale),
    _positiveEvenDimension(displayHeight * scale),
  );
}

int _positiveEvenDimension(double value) {
  final roundedDown = value.floor();
  if (roundedDown <= 2) return 2;
  return roundedDown.isEven ? roundedDown : roundedDown - 1;
}
