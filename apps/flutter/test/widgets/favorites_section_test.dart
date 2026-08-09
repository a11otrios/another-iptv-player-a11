import 'dart:async';

import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/l10n/app_localizations.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/favorite.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/models/playlist_model.dart';
import 'package:another_iptv_player/services/app_state.dart';
import 'package:another_iptv_player/services/service_locator.dart';
import 'package:another_iptv_player/widgets/watch_history/favorites_section.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'resizing retains resolved favorite work without a loading flash',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      getIt.registerSingleton<AppDatabase>(database);
      AppState.currentPlaylist = Playlist(
        id: 'playlist-1',
        name: 'Playlist',
        type: PlaylistType.m3u,
        createdAt: DateTime(2026),
      );
      addTearDown(() async {
        AppState.currentPlaylist = null;
        await getIt.reset();
        await database.close();
      });

      final favorite = Favorite(
        id: 'favorite-1',
        playlistId: 'playlist-1',
        contentType: ContentType.vod,
        streamId: 'movie-1',
        name: 'Family Movie',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final pending = Completer<ContentItem?>();
      var resolveCalls = 0;
      Future<ContentItem?> resolver(Favorite _) {
        resolveCalls += 1;
        return pending.future;
      }

      var cardWidth = 160.0;
      late StateSetter rebuildHost;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('en')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuildHost = setState;
                return FavoritesSection(
                  favorites: [favorite],
                  cardWidth: cardWidth,
                  cardHeight: 220,
                  contentResolver: resolver,
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(resolveCalls, 1);
      expect(find.text('Family Movie'), findsWidgets);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      rebuildHost(() => cardWidth = 130);
      await tester.pump();

      expect(resolveCalls, 1);
      expect(find.text('Family Movie'), findsWidgets);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );
}
