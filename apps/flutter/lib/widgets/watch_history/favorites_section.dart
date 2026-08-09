import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:another_iptv_player/models/favorite.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:flutter/material.dart';
import 'package:another_iptv_player/widgets/content_card.dart';
import 'package:another_iptv_player/utils/navigate_by_content_type.dart';
import 'package:another_iptv_player/utils/get_playlist_type.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/models/live_stream.dart';
import 'package:another_iptv_player/models/vod_streams.dart';
import 'package:another_iptv_player/models/series.dart';
import 'package:another_iptv_player/models/m3u_item.dart';
import '../../repositories/favorites_repository.dart';

class FavoritesSection extends StatefulWidget {
  final List<Favorite> favorites;
  final double cardWidth;
  final double cardHeight;
  final VoidCallback? onSeeAllTap;
  final Function(Favorite)? onFavoriteRemove;
  final Future<ContentItem?> Function(Favorite)? contentResolver;

  const FavoritesSection({
    super.key,
    required this.favorites,
    required this.cardWidth,
    required this.cardHeight,
    this.onSeeAllTap,
    this.onFavoriteRemove,
    this.contentResolver,
  });

  @override
  State<FavoritesSection> createState() => _FavoritesSectionState();
}

class _FavoritesSectionState extends State<FavoritesSection> {
  final Map<String, Future<ContentItem?>> _contentFutures = {};
  FavoritesRepository? _repository;

  @override
  void didUpdateWidget(covariant FavoritesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentResolver != widget.contentResolver) {
      _contentFutures.clear();
    }
    final activeKeys = widget.favorites.map(_contentCacheKey).toSet();
    _contentFutures.removeWhere((key, _) => !activeKeys.contains(key));
  }

  @override
  Widget build(BuildContext context) {
    final favorites = widget.favorites;
    final cardHeight = widget.cardHeight;
    if (favorites.isEmpty) {
      return const SizedBox.shrink();
    }

    final recentFavorites = favorites.take(10).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.loc.favorites,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (widget.onSeeAllTap != null && favorites.length > 10)
                TextButton(
                  onPressed: widget.onSeeAllTap,
                  child: Text(context.loc.see_all_favorites),
                ),
            ],
          ),
        ),
        SizedBox(
          height: cardHeight + 16,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 12),
            itemCount: recentFavorites.length,
            itemBuilder: (context, index) {
              final favorite = recentFavorites[index];
              return _buildFavoriteCard(context, favorite);
            },
          ),
        ),
        SizedBox(height: 16),
      ],
    );
  }

  Widget _buildFavoriteCard(BuildContext context, Favorite favorite) {
    final cardWidth = widget.cardWidth;
    final cardHeight = widget.cardHeight;
    final fallback = _convertFavoriteToContentItem(favorite);
    return Container(
      key: ValueKey(favorite.id),
      width: cardWidth,
      height: cardHeight,
      margin: EdgeInsets.symmetric(horizontal: 4),
      child: Stack(
        children: [
          FutureBuilder<ContentItem?>(
            future: _contentFutureFor(favorite),
            initialData: fallback,
            builder: (context, snapshot) {
              final contentItem = snapshot.data ?? fallback;

              return ContentCard(
                content: contentItem,
                width: cardWidth,
                initialFavorite: true,
                onTap: () => _navigateToContent(context, contentItem),
              );
            },
          ),
          if (widget.onFavoriteRemove != null)
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () async {
                  widget.onFavoriteRemove?.call(favorite);
                },
                child: Container(
                  padding: EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.favorite, color: Colors.red, size: 16),
                ),
              ),
            ),
        ],
      ),
    );
  }

  ContentItem _convertFavoriteToContentItem(Favorite favorite) {
    if (isXtreamCode) {
      switch (favorite.contentType) {
        case ContentType.liveStream:
          final liveStream = LiveStream(
            streamId: favorite.streamId,
            name: favorite.name,
            streamIcon: favorite.imagePath ?? '',
            categoryId: '',
            epgChannelId: '',
          );
          return ContentItem(
            favorite.streamId,
            favorite.name,
            favorite.imagePath ?? '',
            favorite.contentType,
            liveStream: liveStream,
          );

        case ContentType.vod:
          final vodStream = VodStream(
            streamId: favorite.streamId,
            name: favorite.name,
            streamIcon: favorite.imagePath ?? '',
            categoryId: '',
            rating: '',
            rating5based: 0.0,
            containerExtension: '',
            createdAt: DateTime.now(),
          );
          return ContentItem(
            favorite.streamId,
            favorite.name,
            favorite.imagePath ?? '',
            favorite.contentType,
            vodStream: vodStream,
          );

        case ContentType.series:
          final seriesStream = SeriesStream(
            seriesId: favorite.streamId,
            name: favorite.name,
            cover: favorite.imagePath ?? '',
            categoryId: '',
            playlistId: favorite.playlistId,
          );
          return ContentItem(
            favorite.streamId,
            favorite.name,
            favorite.imagePath ?? '',
            favorite.contentType,
            seriesStream: seriesStream,
          );
      }
    } else if (isM3u) {
      final m3uItem = M3uItem(
        id: favorite.m3uItemId ?? favorite.streamId,
        playlistId: favorite.playlistId,
        url: favorite.streamId,
        contentType: favorite.contentType,
        name: favorite.name,
        tvgLogo: favorite.imagePath,
      );
      return ContentItem(
        favorite.streamId,
        favorite.name,
        favorite.imagePath ?? '',
        favorite.contentType,
        m3uItem: m3uItem,
      );
    }

    return ContentItem(
      favorite.streamId,
      favorite.name,
      favorite.imagePath ?? '',
      favorite.contentType,
    );
  }

  Future<ContentItem?> _contentFutureFor(Favorite favorite) {
    final key = _contentCacheKey(favorite);
    return _contentFutures.putIfAbsent(key, () {
      final resolver = widget.contentResolver;
      if (resolver != null) return resolver(favorite);
      _repository ??= FavoritesRepository();
      return _repository!.getContentItemFromFavorite(favorite);
    });
  }

  String _contentCacheKey(Favorite favorite) =>
      '${favorite.id}:${favorite.updatedAt.microsecondsSinceEpoch}';

  Future<void> _navigateToContent(
    BuildContext context,
    ContentItem contentItem,
  ) async {
    final matchingFavorites = widget.favorites
        .take(10)
        .where((favorite) => favorite.contentType == contentItem.contentType);
    final resolvedFavorites = await Future.wait(
      matchingFavorites.map(_contentFutureFor),
    );
    if (!context.mounted) return;

    navigateByContentType(
      context,
      contentItem,
      queue: resolvedFavorites.whereType<ContentItem>().toList(),
    );
  }
}
