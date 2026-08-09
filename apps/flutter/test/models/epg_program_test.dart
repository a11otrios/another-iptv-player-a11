import 'dart:convert';

import 'package:another_iptv_player/models/epg_program.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses base64 encoded Xtream EPG text and timestamps', () {
    final program = EpgProgram.fromXtreamJson({
      'id': '42',
      'title': base64.encode(utf8.encode('Evening News')),
      'description': base64.encode(utf8.encode('Headlines and weather')),
      'start_timestamp': '1800000000',
      'stop_timestamp': 1800001800,
      'now_playing': '1',
    });

    expect(program.id, '42');
    expect(program.title, 'Evening News');
    expect(program.description, 'Headlines and weather');
    expect(
      program.startTime,
      DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000),
    );
    expect(
      program.endTime,
      DateTime.fromMillisecondsSinceEpoch(1800001800 * 1000),
    );
    expect(program.nowPlaying, isTrue);
  });

  test('keeps plain Xtream EPG text when it is not base64 encoded', () {
    final program = EpgProgram.fromXtreamJson({
      'title': 'Live Match',
      'description': 'First half',
      'start': '2026-08-01 20:00:00',
      'end': '2026-08-01 22:00:00',
    });

    expect(program.title, 'Live Match');
    expect(program.description, 'First half');
    expect(program.startTime, DateTime(2026, 8, 1, 20));
    expect(program.endTime, DateTime(2026, 8, 1, 22));
  });
}
