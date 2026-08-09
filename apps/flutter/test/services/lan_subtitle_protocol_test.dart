import 'package:another_iptv_player/services/lan_server/lan_server_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('converts SRT timestamps to WebVTT', () {
    const source = '''1
00:00:01,250 --> 00:00:03,500
Hello

2
01:02:03,004 --> 01:02:05,006
World
''';

    final result = subtitleToWebVtt(source);

    expect(result, startsWith('WEBVTT\n\n'));
    expect(result, contains('00:00:01.250 --> 00:00:03.500'));
    expect(result, contains('01:02:03.004 --> 01:02:05.006'));
  });

  test('leaves an existing WebVTT document intact', () {
    const source = 'WEBVTT\n\n00:01.000 --> 00:02.000\nHello';
    expect(subtitleToWebVtt(source), source);
  });
}
