import 'package:another_iptv_player/l10n/app_localizations.dart';
import 'package:another_iptv_player/models/category.dart';
import 'package:another_iptv_player/models/category_type.dart';
import 'package:another_iptv_player/models/category_view_model.dart';
import 'package:another_iptv_player/repositories/user_preferences.dart';
import 'package:another_iptv_player/screens/settings/category_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'filters every category group and bulk toggles only matching categories',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await UserPreferences.setHiddenCategories([
        UserPreferences.hiddenCategoryKey(CategoryType.live, 'live-gr'),
        UserPreferences.hiddenCategoryKey(CategoryType.series, 'drama'),
      ], playlistId: 'playlist-1');

      await tester.pumpWidget(
        _testApp(
          liveCategories: [
            _category('live-gr', 'GR News', CategoryType.live),
            _category('sports', 'Sports', CategoryType.live),
          ],
          movieCategories: [
            _category('movie-gr', 'Greek Movies', CategoryType.vod),
          ],
          seriesCategories: [_category('drama', 'Drama', CategoryType.series)],
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('category-filter-field')),
        'gR',
      );
      await tester.pump();

      expect(find.text('GR News'), findsOneWidget);
      expect(find.text('Greek Movies'), findsOneWidget);
      expect(find.text('Sports'), findsNothing);
      expect(find.text('Drama'), findsNothing);

      Checkbox bulkToggle() => tester.widget<Checkbox>(
        find.byKey(const ValueKey('filtered-category-toggle')),
      );

      expect(bulkToggle().value, isNull);

      await tester.tap(find.byKey(const ValueKey('filtered-category-toggle')));
      await tester.pumpAndSettle();

      expect(bulkToggle().value, isTrue);
      var hidden = await UserPreferences.getHiddenCategories(
        playlistId: 'playlist-1',
      );
      expect(hidden, contains('series:drama'));
      expect(hidden, isNot(contains('live:live-gr')));
      expect(hidden, isNot(contains('vod:movie-gr')));

      await tester.tap(find.byKey(const ValueKey('filtered-category-toggle')));
      await tester.pumpAndSettle();

      expect(bulkToggle().value, isFalse);
      hidden = await UserPreferences.getHiddenCategories(
        playlistId: 'playlist-1',
      );
      expect(hidden, containsAll(['live:live-gr', 'vod:movie-gr']));
      expect(hidden, contains('series:drama'));
      expect(hidden, isNot(contains('live:sports')));
    },
  );

  testWidgets('reorders matching categories while the list is filtered', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testApp(
        liveCategories: [
          _category('gr-one', 'GR One', CategoryType.live),
          _category('sports', 'Sports', CategoryType.live),
          _category('gr-two', 'GR Two', CategoryType.live),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('category-filter-field')),
      'GR',
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down).first);
    await tester.pumpAndSettle();

    expect(
      await UserPreferences.getCategoryOrder(
        playlistId: 'playlist-1',
        type: CategoryType.live,
      ),
      ['gr-two', 'sports', 'gr-one'],
    );
  });
}

Widget _testApp({
  List<CategoryViewModel> liveCategories = const [],
  List<CategoryViewModel> movieCategories = const [],
  List<CategoryViewModel> seriesCategories = const [],
}) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: CategorySettingsScreen(
      playlistId: 'playlist-1',
      liveCategories: liveCategories,
      movieCategories: movieCategories,
      seriesCategories: seriesCategories,
    ),
  );
}

CategoryViewModel _category(String id, String name, CategoryType type) {
  return CategoryViewModel(
    category: Category(
      categoryId: id,
      categoryName: name,
      parentId: 0,
      playlistId: 'playlist-1',
      type: type,
    ),
    contentItems: const [],
  );
}
