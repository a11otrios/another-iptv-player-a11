import 'dart:convert';

import 'package:another_iptv_player/utils/type_convertions.dart';

class EpgProgram {
  final String id;
  final String title;
  final String description;
  final DateTime? startTime;
  final DateTime? endTime;
  final bool nowPlaying;

  const EpgProgram({
    required this.id,
    required this.title,
    required this.description,
    required this.startTime,
    required this.endTime,
    required this.nowPlaying,
  });

  factory EpgProgram.fromXtreamJson(Map<String, dynamic> json) {
    return EpgProgram(
      id: safeString(json['id']),
      title: _decodeXtreamText(json['title']),
      description: _decodeXtreamText(json['description']),
      startTime: _parseXtreamDateTime([json['start_timestamp'], json['start']]),
      endTime: _parseXtreamDateTime([
        json['stop_timestamp'],
        json['end_timestamp'],
        json['end'],
      ]),
      nowPlaying: safeBool(json['now_playing']),
    );
  }

  bool isAiringAt(DateTime time) {
    final start = startTime;
    final end = endTime;
    if (start == null || end == null) return nowPlaying;
    return !time.isBefore(start) && time.isBefore(end);
  }

  static String _decodeXtreamText(dynamic value) {
    final text = safeString(value);
    if (text.isEmpty) return '';

    try {
      final normalized = base64.normalize(text);
      final bytes = base64.decode(normalized);
      final decoded = utf8.decode(bytes, allowMalformed: true).trim();
      if (decoded.isNotEmpty && !_looksLikeBinary(decoded)) {
        return decoded;
      }
    } catch (_) {
      // Xtream providers are inconsistent: plain text is common too.
    }

    return text;
  }

  static bool _looksLikeBinary(String value) {
    final controlCharacters = value.runes
        .where((rune) => rune < 32 && rune != 9 && rune != 10 && rune != 13)
        .length;
    return controlCharacters > 0;
  }

  static DateTime? _parseXtreamDateTime(List<dynamic> candidates) {
    for (final candidate in candidates) {
      final timestamp = safeInt(candidate);
      if (timestamp > 0) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
      }

      final text = safeString(candidate);
      if (text.isEmpty) continue;
      final parsed = DateTime.tryParse(text.replaceFirst(' ', 'T'));
      if (parsed != null) return parsed;
    }
    return null;
  }
}
