import 'package:another_iptv_player/services/app_state.dart';
import 'package:flutter/foundation.dart';

import '../models/content_type.dart';
import '../models/playlist_content_model.dart';

String buildMediaUrl(ContentItem contentItem) {
  var playlist = AppState.currentPlaylist!;
  late final String url;
  switch (contentItem.contentType) {
    case ContentType.liveStream:
      final extension = kIsWeb ? 'm3u8' : 'ts';
      url =
          '${playlist.url}/live/${playlist.username}/${playlist.password}/${contentItem.id}.$extension';
      break;
    case ContentType.vod:
      url =
          '${playlist.url}/movie/${playlist.username}/${playlist.password}/${contentItem.id}.${contentItem.containerExtension}';
      break;
    case ContentType.series:
      url =
          '${playlist.url}/series/${playlist.username}/${playlist.password}/${contentItem.id}.${contentItem.containerExtension}';
      break;
  }

  if (!kIsWeb) {
    return url;
  }

  return Uri.parse(
    '/__proxy',
  ).replace(queryParameters: {'url': url}).toString();
}
