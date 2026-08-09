class SubtitleSearchResult {
  final int fileId;
  final String subtitleId;
  final String language;
  final String title;
  final String releaseName;
  final String format;
  final bool hearingImpaired;
  final int downloadCount;
  final double? rating;

  const SubtitleSearchResult({
    required this.fileId,
    required this.subtitleId,
    required this.language,
    required this.title,
    required this.releaseName,
    required this.format,
    required this.hearingImpaired,
    required this.downloadCount,
    this.rating,
  });

  factory SubtitleSearchResult.fromOpenSubtitles(
    Map<String, dynamic> item,
    Map<String, dynamic> file,
  ) {
    final attributes = _asMap(item['attributes']);
    final feature = _asMap(attributes['feature_details']);
    final fileName = _asString(file['file_name']);
    final release = _firstNonEmpty([
      _asString(attributes['release']),
      fileName,
      _asString(feature['title']),
      _asString(attributes['subtitle_id']),
    ]);

    return SubtitleSearchResult(
      fileId: _asInt(file['file_id']) ?? 0,
      subtitleId: _asString(attributes['subtitle_id']) ?? item['id'].toString(),
      language: _asString(attributes['language']) ?? '',
      title:
          _asString(feature['title']) ?? _asString(attributes['feature']) ?? '',
      releaseName: release ?? 'Subtitle',
      format: _extension(fileName) ?? _asString(file['file_type']) ?? 'srt',
      hearingImpaired: _asBool(attributes['hearing_impaired']),
      downloadCount: _asInt(attributes['download_count']) ?? 0,
      rating: _asDouble(attributes['ratings']),
    );
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  static String? _asString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static double? _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  static bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) {
      final normalized = value.toLowerCase().trim();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }

  static String? _extension(String? fileName) {
    if (fileName == null) return null;
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return null;
    return fileName.substring(dot + 1).toLowerCase();
  }

  static String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}

class CachedSubtitle {
  final String contentKey;
  final String filePath;
  final String title;
  final String language;
  final double offsetSeconds;

  const CachedSubtitle({
    required this.contentKey,
    required this.filePath,
    required this.title,
    required this.language,
    required this.offsetSeconds,
  });

  Map<String, dynamic> toJson() => {
    'contentKey': contentKey,
    'filePath': filePath,
    'title': title,
    'language': language,
    'offsetSeconds': offsetSeconds,
  };

  factory CachedSubtitle.fromJson(Map<String, dynamic> json) {
    return CachedSubtitle(
      contentKey: json['contentKey']?.toString() ?? '',
      filePath: json['filePath']?.toString() ?? '',
      title: json['title']?.toString() ?? 'External subtitle',
      language: json['language']?.toString() ?? 'auto',
      offsetSeconds: _asOffset(json['offsetSeconds']),
    );
  }

  static double _asOffset(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? 0.0;
    return 0.0;
  }
}
