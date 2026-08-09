import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/models/playlist_model.dart';
import 'package:another_iptv_player/services/app_state.dart';
import 'package:another_iptv_player/utils/category_item_sort.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    AppState.currentPlaylist = Playlist(
      id: 'sort-test',
      name: 'Sort test',
      type: PlaylistType.xtream,
      url: 'https://example.invalid',
      username: 'test',
      password: 'test',
      createdAt: DateTime(2026),
    );
  });

  ContentItem movie(String id, String name) =>
      ContentItem(id, name, '', ContentType.vod);

  test('release date sorts movie years newest first', () {
    final result = sortCategoryItems([
      movie('old', 'An Old Film (1988)'),
      movie('unknown', 'A Film Without A Year'),
      movie('new', 'A New Film 4K (2025)'),
      movie('middle', 'A Middle Film [2014]'),
    ], CategoryItemSort.releaseDate);

    expect(result.map((item) => item.id), ['new', 'middle', 'old', 'unknown']);
  });

  test('equal and unknown release dates retain provider order', () {
    final result = sortCategoryItems([
      movie('first', 'First (2024)'),
      movie('second', 'Second (2024)'),
      movie('third', 'Third'),
      movie('fourth', 'Fourth'),
    ], CategoryItemSort.releaseDate);

    expect(result.map((item) => item.id), [
      'first',
      'second',
      'third',
      'fourth',
    ]);
  });
}
