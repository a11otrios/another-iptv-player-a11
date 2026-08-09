import 'package:another_iptv_player/controllers/favorites_controller.dart';
import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/favorite.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/repositories/favorites_repository.dart';
import 'package:another_iptv_player/utils/navigate_by_content_type.dart';
import 'package:another_iptv_player/utils/responsive_helper.dart';
import 'package:another_iptv_player/widgets/content_card.dart';
import 'package:flutter/material.dart';

class FavoritesScreen extends StatefulWidget {
  final bool isActive;

  const FavoritesScreen({super.key, this.isActive = true});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final FavoritesController _controller = FavoritesController();
  final FavoritesRepository _repository = FavoritesRepository();
  ContentType? _selectedType;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.isActive) {
        _controller.loadFavorites();
      }
    });
  }

  @override
  void didUpdateWidget(FavoritesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _controller.loadFavorites();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) {
        return Scaffold(
          appBar: AppBar(
            title: SelectableText(
              context.loc.favorites,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            actions: [
              IconButton(
                tooltip: context.loc.refresh,
                icon: const Icon(Icons.refresh),
                onPressed: _controller.loadFavorites,
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _controller.loadFavorites,
            child: _buildBody(context),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final favorites = _filteredFavorites;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildFilters(context)),
        if (favorites.isEmpty)
          SliverFillRemaining(child: _buildEmptyState(context))
        else
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: ResponsiveHelper.getCrossAxisCount(context),
                childAspectRatio: 0.65,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _FavoriteGridItem(
                  favorite: favorites[index],
                  repository: _repository,
                  onTap: _openFavorite,
                  onChanged: () async {
                    await _controller.loadFavorites();
                  },
                ),
                childCount: favorites.length,
              ),
            ),
          ),
      ],
    );
  }

  List<Favorite> get _filteredFavorites {
    final selectedType = _selectedType;
    if (selectedType == null) return _controller.favorites;
    return _controller.favorites
        .where((favorite) => favorite.contentType == selectedType)
        .toList();
  }

  Widget _buildFilters(BuildContext context) {
    final filters = [
      _FavoriteFilter(null, context.loc.all),
      _FavoriteFilter(ContentType.liveStream, context.loc.live),
      _FavoriteFilter(ContentType.vod, context.loc.movies),
      _FavoriteFilter(ContentType.series, context.loc.series_plural),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: filters.map((filter) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(filter.label),
              selected: _selectedType == filter.type,
              onSelected: (_) {
                setState(() {
                  _selectedType = filter.type;
                });
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.favorite_border,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              context.loc.favorites,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Use the heart button on channels, movies, and series to keep them here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFavorite(ContentItem contentItem) async {
    final matchingFavorites = _filteredFavorites
        .where((favorite) => favorite.contentType == contentItem.contentType)
        .toList();
    final resolvedFavorites = await Future.wait(
      matchingFavorites.map(_repository.getContentItemFromFavorite),
    );
    if (!mounted) return;

    navigateByContentType(
      context,
      contentItem,
      queue: resolvedFavorites.whereType<ContentItem>().toList(),
    );
  }
}

class _FavoriteGridItem extends StatelessWidget {
  final Favorite favorite;
  final FavoritesRepository repository;
  final ValueChanged<ContentItem> onTap;
  final VoidCallback onChanged;

  const _FavoriteGridItem({
    required this.favorite,
    required this.repository,
    required this.onTap,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ContentItem?>(
      future: repository.getContentItemFromFavorite(favorite),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final content = snapshot.data ?? _fallbackContentItem(favorite);
        return ContentCard(
          content: content,
          width: 150,
          initialFavorite: true,
          onTap: () => onTap(content),
          showFavoriteButton: true,
          onFavoriteChanged: (_) => onChanged(),
        );
      },
    );
  }

  ContentItem _fallbackContentItem(Favorite favorite) {
    return ContentItem(
      favorite.streamId,
      favorite.name,
      favorite.imagePath ?? '',
      favorite.contentType,
    );
  }
}

class _FavoriteFilter {
  final ContentType? type;
  final String label;

  const _FavoriteFilter(this.type, this.label);
}
