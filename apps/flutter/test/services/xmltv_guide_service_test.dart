import 'dart:convert';
import 'dart:io';

import 'package:another_iptv_player/services/xmltv_guide_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('falls back to an exact normalized XMLTV display name', () async {
    final directory = await Directory.systemTemp.createTemp('xmltv-guide-test');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}guide.xml');
    await file.writeAsString('''<?xml version="1.0"?>
<tv>
  <channel id="ERT1.gr"><display-name>ERT 1 HD</display-name></channel>
  <programme channel="ERT1.gr" start="20260811120000 +0300" stop="20260811130000 +0300">
    <title>News</title><desc>Current affairs</desc>
  </programme>
</tv>''');

    final programs = await XmltvGuideService.instance.programsFor(
      source: file.path,
      channelId: 'provider-specific-id',
      channelName: 'ERT 1 HD',
      limit: 2,
      now: DateTime.utc(2026, 8, 11, 8),
    );

    expect(programs, hasLength(1));
    expect(programs.single.title, 'News');
    expect(programs.single.description, 'Current affairs');
  });

  test('downloads and shares a gzipped remote guide across lookups', () async {
    var requests = 0;
    final service = XmltvGuideService(
      httpGet: (uri, {headers}) async {
        requests++;
        expect(uri.host, 'provider.test');
        return http.Response.bytes(
          gzip.encode(utf8.encode(_guideXml)),
          HttpStatus.ok,
          headers: {'content-type': 'application/gzip'},
        );
      },
    );

    final first = await service.programsFor(
      source: 'https://provider.test/xmltv.php?username=user&password=secret',
      channelId: 'ERT1.gr',
      channelName: 'ERT 1 HD',
      limit: 2,
      now: DateTime.utc(2026, 8, 11, 8),
    );
    final second = await service.programsFor(
      source: 'https://provider.test/xmltv.php?username=user&password=secret',
      channelId: 'provider-specific-id',
      channelName: 'ERT 1 HD',
      limit: 2,
      now: DateTime.utc(2026, 8, 11, 8),
    );

    expect(first.single.title, 'News');
    expect(second.single.title, 'News');
    expect(requests, 1);
  });

  test(
    'conditionally refreshes a remote guide after the cache interval',
    () async {
      var clock = DateTime.utc(2026, 8, 11, 8);
      var requests = 0;
      final service = XmltvGuideService(
        now: () => clock,
        remoteRefreshInterval: const Duration(hours: 1),
        httpGet: (uri, {headers}) async {
          requests++;
          if (requests == 1) {
            return http.Response(
              _guideXml,
              HttpStatus.ok,
              headers: {'etag': 'guide-v1'},
            );
          }
          expect(headers?['If-None-Match'], 'guide-v1');
          return http.Response('', HttpStatus.notModified);
        },
      );

      await service.programsFor(
        source: 'https://provider.test/epg.xml',
        channelId: 'ERT1.gr',
        channelName: 'ERT 1 HD',
        limit: 1,
        now: clock,
      );
      clock = clock.add(const Duration(hours: 2));
      final refreshed = await service.programsFor(
        source: 'https://provider.test/epg.xml',
        channelId: 'ERT1.gr',
        channelName: 'ERT 1 HD',
        limit: 1,
        now: DateTime.utc(2026, 8, 11, 8),
      );

      expect(refreshed.single.title, 'News');
      expect(requests, 2);
    },
  );

  test('recognizes only complete HTTP and HTTPS guide URLs', () {
    expect(XmltvGuideService.isRemoteUrl('https://provider.test/epg'), isTrue);
    expect(XmltvGuideService.isRemoteUrl('http://provider.test/epg'), isTrue);
    expect(XmltvGuideService.isRemoteUrl('provider.test/epg'), isFalse);
    expect(XmltvGuideService.isRemoteUrl('ftp://provider.test/epg'), isFalse);
  });
}

const _guideXml = '''<?xml version="1.0"?>
<tv>
  <channel id="ERT1.gr"><display-name>ERT 1 HD</display-name></channel>
  <programme channel="ERT1.gr" start="20260811120000 +0300" stop="20260811130000 +0300">
    <title>News</title><desc>Current affairs</desc>
  </programme>
</tv>''';
