import 'package:another_iptv_player/models/player_aspect_ratio_mode.dart';
import 'package:another_iptv_player/models/category_type.dart';
import 'package:another_iptv_player/repositories/user_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('player aspect ratio defaults to original', () async {
    expect(
      await UserPreferences.getPlayerAspectRatio('playlist-a/live/one'),
      PlayerAspectRatioMode.original,
    );
  });

  test('player aspect ratios are persisted independently by stream', () async {
    await UserPreferences.setPlayerAspectRatio(
      'playlist-a/live/one',
      PlayerAspectRatioMode.ratio21x9,
    );

    expect(
      await UserPreferences.getPlayerAspectRatio('playlist-a/live/one'),
      PlayerAspectRatioMode.ratio21x9,
    );
    expect(
      await UserPreferences.getPlayerAspectRatio('playlist-a/live/two'),
      PlayerAspectRatioMode.original,
    );
  });

  test('unknown player aspect ratio falls back to original', () async {
    SharedPreferences.setMockInitialValues({
      'player_aspect_ratio': 'unsupported',
    });

    expect(
      await UserPreferences.getPlayerAspectRatio('playlist-a/live/one'),
      PlayerAspectRatioMode.original,
    );
  });

  test(
    'legacy global aspect ratio migrates to only the first stream',
    () async {
      SharedPreferences.setMockInitialValues({
        'player_aspect_ratio': 'stretch',
      });

      expect(
        await UserPreferences.getPlayerAspectRatio('playlist-a/live/one'),
        PlayerAspectRatioMode.stretch,
      );
      expect(
        await UserPreferences.getPlayerAspectRatio('playlist-a/live/two'),
        PlayerAspectRatioMode.original,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('player_aspect_ratio'), isFalse);
    },
  );

  test('legacy and current subtitle font weights remain compatible', () async {
    SharedPreferences.setMockInitialValues({'subtitle_font_weight': 3});
    expect(await UserPreferences.getSubtitleFontWeight(), FontWeight.values[3]);

    await UserPreferences.setSubtitleFontWeight(FontWeight.bold);
    expect(await UserPreferences.getSubtitleFontWeight(), FontWeight.bold);
  });

  test(
    'desktop window settings default off and persist independently',
    () async {
      expect(await UserPreferences.getBorderlessWindow(), isFalse);
      expect(await UserPreferences.getAlwaysOnTop(), isFalse);

      await UserPreferences.setBorderlessWindow(true);
      expect(await UserPreferences.getBorderlessWindow(), isTrue);
      expect(await UserPreferences.getAlwaysOnTop(), isFalse);

      await UserPreferences.setAlwaysOnTop(true);
      expect(await UserPreferences.getBorderlessWindow(), isTrue);
      expect(await UserPreferences.getAlwaysOnTop(), isTrue);
    },
  );

  test('category order is isolated by playlist and content type', () async {
    await UserPreferences.setCategoryOrder(
      playlistId: 'playlist-a',
      type: CategoryType.live,
      categoryIds: ['news', 'children'],
    );

    expect(
      await UserPreferences.getCategoryOrder(
        playlistId: 'playlist-a',
        type: CategoryType.live,
      ),
      ['news', 'children'],
    );
    expect(
      await UserPreferences.getCategoryOrder(
        playlistId: 'playlist-a',
        type: CategoryType.vod,
      ),
      isEmpty,
    );
    expect(
      await UserPreferences.getCategoryOrder(
        playlistId: 'playlist-b',
        type: CategoryType.live,
      ),
      isEmpty,
    );
  });

  test('saved category order appends new categories in provider order', () {
    final ordered = UserPreferences.applyCategoryOrder(
      ['children', 'sports', 'news', 'documentary'],
      ['news', 'children', 'missing'],
      (category) => category,
    );

    expect(ordered, ['news', 'children', 'sports', 'documentary']);
  });

  test(
    'provider category order survives refreshes and tracks changes',
    () async {
      expect(
        await UserPreferences.syncCategoryOriginalOrder(
          playlistId: 'playlist-a',
          type: CategoryType.live,
          categoryIds: ['news', 'children', 'sports'],
        ),
        ['news', 'children', 'sports'],
      );

      expect(
        await UserPreferences.syncCategoryOriginalOrder(
          playlistId: 'playlist-a',
          type: CategoryType.live,
          categoryIds: ['children', 'sports', 'documentary'],
        ),
        ['children', 'sports', 'documentary'],
      );
      expect(
        await UserPreferences.getCategoryOriginalOrder(
          playlistId: 'playlist-a',
          type: CategoryType.live,
        ),
        ['children', 'sports', 'documentary'],
      );
    },
  );

  test('radio visibility is persisted per playlist', () async {
    await UserPreferences.setHideRadioStations(
      playlistId: 'playlist-a',
      value: true,
    );

    expect(
      await UserPreferences.getHideRadioStations(playlistId: 'playlist-a'),
      isTrue,
    );
    expect(
      await UserPreferences.getHideRadioStations(playlistId: 'playlist-b'),
      isFalse,
    );
  });
}
