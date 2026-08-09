import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/watch_history_controller.dart';
import '../controllers/favorites_controller.dart';
import '../models/watch_history.dart';
import '../models/favorite.dart';
import '../widgets/watch_history/watch_history_empty_state.dart';
import '../widgets/watch_history/watch_history_content.dart';
import '../widgets/watch_history/watch_history_dialogs.dart';
import '../widgets/watch_history/watch_history_list_screen.dart';
import '../l10n/localization_extension.dart';
import 'favorites_screen.dart';

class WatchHistoryScreen extends StatefulWidget {
  final String playlistId;
  final Key? screenKey;

  const WatchHistoryScreen({
    super.key,
    required this.playlistId,
    this.screenKey,
  });

  @override
  State<WatchHistoryScreen> createState() => _WatchHistoryScreenState();
}

class _WatchHistoryScreenState extends State<WatchHistoryScreen> {
  late WatchHistoryController _historyController;
  late FavoritesController _favoritesController;

  @override
  void initState() {
    super.initState();
    _historyController = WatchHistoryController();
    _favoritesController = FavoritesController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshData();
    });
  }

  void _refreshData() {
    if (mounted) {
      _historyController.loadWatchHistory();
      _favoritesController.loadFavorites();
    }
  }

  @override
  void dispose() {
    _historyController.dispose();
    _favoritesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _historyController),
        ChangeNotifierProvider.value(value: _favoritesController),
      ],
      child: Scaffold(
        body: Consumer2<WatchHistoryController, FavoritesController>(
          builder: (context, historyController, favoritesController, child) {
            final hasExistingContent =
                !historyController.isAllEmpty ||
                favoritesController.favorites.isNotEmpty;
            if ((historyController.isLoading ||
                    favoritesController.isLoading) &&
                !hasExistingContent) {
              return const Center(child: CircularProgressIndicator());
            }

            if (historyController.errorMessage != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(historyController.errorMessage!)),
                );
              });
            }

            return RefreshIndicator(
              onRefresh: () async {
                await historyController.loadWatchHistory();
                await favoritesController.loadFavorites();
              },
              child:
                  historyController.isAllEmpty &&
                      favoritesController.favorites.isEmpty
                  ? const WatchHistoryEmptyState()
                  : WatchHistoryContent(
                      onHistoryTap: (history, histories) =>
                          historyController.playContent(
                            context,
                            history,
                            sectionHistories: histories,
                          ),
                      onHistoryRemove: (history) => _showRemoveDialog(history),
                      onSeeAllTap: _showAllHistory,
                      onFavoriteRemove: _removeFavorite,
                      onSeeAllFavorites: _showAllFavorites,
                    ),
            );
          },
        ),
      ),
    );
  }

  void _showAllHistory(String title, List<WatchHistory> histories) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WatchHistoryListScreen(
          title: title,
          histories: histories,
          onHistoryTap: (history) => _historyController.playContent(
            context,
            history,
            sectionHistories: histories,
          ),
          onHistoryRemove: (history) => _showRemoveDialog(history),
        ),
      ),
    );
  }

  void _showRemoveDialog(history) {
    WatchHistoryDialogs.showRemoveDialog(
      context,
      onConfirm: () => _historyController.removeHistory(history),
    );
  }

  void _removeFavorite(Favorite favorite) async {
    final success = await _favoritesController.removeFavorite(
      favorite.streamId,
      favorite.contentType,
      episodeId: favorite.episodeId,
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.loc.removed_from_favorites),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showAllFavorites() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const FavoritesScreen()),
    );
  }
}
