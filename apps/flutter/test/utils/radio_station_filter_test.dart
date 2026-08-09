import 'package:another_iptv_player/utils/radio_station_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects explicit radio metadata without broad false positives', () {
    expect(isLikelyRadioStation('BBC Radio 2'), isTrue);
    expect(isLikelyRadioStation('Athens 98.4 FM'), isTrue);
    expect(isLikelyRadioStation('Station', 'GR | Radio'), isTrue);
    expect(isLikelyRadioStation('Radioactive (2026)'), isFalse);
    expect(isLikelyRadioStation('FMVSS 218'), isFalse);
  });
}
