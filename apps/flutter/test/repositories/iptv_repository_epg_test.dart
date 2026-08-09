import 'dart:convert';

import 'package:another_iptv_player/models/api_configuration_model.dart';
import 'package:another_iptv_player/repositories/iptv_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  const config = ApiConfig(
    baseUrl: 'http://provider.test',
    username: 'user',
    password: 'pass',
  );

  test(
    'falls back to the simple EPG table and removes expired listings',
    () async {
      final now = DateTime.now();
      final actions = <String>[];
      final repository = IptvRepository(
        config,
        'playlist',
        httpGet: (uri, {headers}) async {
          final action = uri.queryParameters['action']!;
          actions.add(action);
          if (action == 'get_short_epg') {
            return http.Response(jsonEncode({'epg_listings': []}), 200);
          }

          return http.Response(
            jsonEncode({
              'epg_listings': [
                _listing(
                  'expired',
                  now.subtract(const Duration(hours: 2)),
                  now.subtract(const Duration(hours: 1)),
                ),
                _listing(
                  'current',
                  now.subtract(const Duration(minutes: 10)),
                  now.add(const Duration(minutes: 20)),
                ),
                _listing(
                  'next',
                  now.add(const Duration(minutes: 20)),
                  now.add(const Duration(hours: 1)),
                ),
              ],
            }),
            200,
          );
        },
      );

      final programs = await repository.getShortEpg('42', limit: 2);

      expect(actions, ['get_short_epg', 'get_simple_data_table']);
      expect(programs?.map((program) => program.title), ['current', 'next']);
      expect(programs?.first.isAiringAt(DateTime.now()), isTrue);
    },
  );

  test('does not use the fallback when short EPG has listings', () async {
    final now = DateTime.now();
    final actions = <String>[];
    final repository = IptvRepository(
      config,
      'playlist',
      httpGet: (uri, {headers}) async {
        final action = uri.queryParameters['action']!;
        actions.add(action);
        return http.Response(
          jsonEncode({
            'epg_listings': [
              _listing(
                'current',
                now.subtract(const Duration(minutes: 5)),
                now.add(const Duration(minutes: 25)),
              ),
            ],
          }),
          200,
        );
      },
    );

    final programs = await repository.getShortEpg('42');

    expect(actions, ['get_short_epg']);
    expect(programs?.single.title, 'current');
  });

  test('does not report a stale simple EPG schedule as current', () async {
    final now = DateTime.now();
    final repository = IptvRepository(
      config,
      'playlist',
      httpGet: (uri, {headers}) async => http.Response(
        jsonEncode({
          'epg_listings': uri.queryParameters['action'] == 'get_short_epg'
              ? []
              : [
                  _listing(
                    'expired',
                    now.subtract(const Duration(days: 2)),
                    now.subtract(const Duration(days: 1)),
                  ),
                ],
        }),
        200,
      ),
    );

    final programs = await repository.getShortEpg('42');

    expect(programs, isEmpty);
  });
}

Map<String, Object> _listing(String title, DateTime start, DateTime end) => {
  'id': title,
  'title': base64.encode(utf8.encode(title)),
  'description': '',
  'start_timestamp': start.millisecondsSinceEpoch ~/ 1000,
  'stop_timestamp': end.millisecondsSinceEpoch ~/ 1000,
  'now_playing': 0,
};
