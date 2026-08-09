import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:another_iptv_player/controllers/favorites_controller.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:another_iptv_player/models/epg_program.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/services/app_state.dart';

class ContentCard extends StatefulWidget {
  final ContentItem content;
  final double width;
  final VoidCallback? onTap;
  final bool isSelected;
  final bool showFavoriteButton;
  final bool? initialFavorite;
  final ValueChanged<bool>? onFavoriteChanged;
  final String? subtitle;

  const ContentCard({
    super.key,
    required this.content,
    required this.width,
    this.onTap,
    this.isSelected = false,
    this.showFavoriteButton = true,
    this.initialFavorite,
    this.onFavoriteChanged,
    this.subtitle,
  });

  @override
  State<ContentCard> createState() => _ContentCardState();
}

class _ContentCardState extends State<ContentCard> {
  late final FavoritesController _favoritesController;
  late bool _isFavorite;
  late bool _isFavoriteLoading;
  Future<List<EpgProgram>?>? _epgFuture;
  String? _epgContentKey;

  @override
  void initState() {
    super.initState();
    _favoritesController = FavoritesController();
    _isFavorite = widget.initialFavorite ?? false;
    _isFavoriteLoading = widget.initialFavorite == null;
    if (widget.initialFavorite == null) {
      _loadFavoriteState();
    }
  }

  @override
  void didUpdateWidget(ContentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content.id != widget.content.id ||
        oldWidget.content.contentType != widget.content.contentType) {
      _isFavorite = widget.initialFavorite ?? false;
      _isFavoriteLoading = widget.initialFavorite == null;
      if (widget.initialFavorite == null) {
        _loadFavoriteState();
      }
      _epgFuture = null;
      _epgContentKey = null;
    } else if (oldWidget.initialFavorite != widget.initialFavorite &&
        widget.initialFavorite != null) {
      _isFavorite = widget.initialFavorite!;
      _isFavoriteLoading = false;
    }
  }

  @override
  void dispose() {
    _favoritesController.dispose();
    super.dispose();
  }

  Future<void> _loadFavoriteState() async {
    if (!widget.showFavoriteButton) return;

    final contentId = widget.content.id;
    final contentType = widget.content.contentType;

    setState(() {
      _isFavoriteLoading = true;
    });

    final isFavorite = await _favoritesController.isFavorite(
      contentId,
      contentType,
    );

    if (!mounted ||
        widget.content.id != contentId ||
        widget.content.contentType != contentType) {
      return;
    }
    setState(() {
      _isFavorite = isFavorite;
      _isFavoriteLoading = false;
    });
  }

  Future<void> _toggleFavorite() async {
    final result = await _favoritesController.toggleFavorite(widget.content);

    if (!mounted) return;
    setState(() {
      _isFavorite = result;
      _isFavoriteLoading = false;
    });
    widget.onFavoriteChanged?.call(result);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result
              ? context.loc.added_to_favorites
              : context.loc.removed_from_favorites,
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isRecent = false;
    String? releaseDateStr;
    DateTime? releaseDate;

    if (widget.content.contentType == ContentType.series) {
      releaseDateStr = widget.content.seriesStream?.releaseDate;
    }

    if (releaseDateStr != null && releaseDateStr.isNotEmpty) {
      try {
        releaseDate = DateTime.parse(releaseDateStr);
      } catch (e) {
        releaseDate = null;
      }
    }

    if (releaseDate != null) {
      final diff = DateTime.now().difference(releaseDate).inDays;
      isRecent = diff <= 15;
    }

    final bool isLiveStream =
        widget.content.contentType == ContentType.liveStream;
    final Widget? ratingBadge = isLiveStream
        ? null
        : _buildRatingBadge(context);

    Widget cardWidget = Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 1),
      color: widget.isSelected
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _buildImageContent(context, isLiveStream),
                  ),
                  if (widget.showFavoriteButton) _buildFavoriteButton(context),
                  if (ratingBadge != null) ratingBadge,
                  if (isRecent)
                    Positioned(
                      top: widget.showFavoriteButton ? 44 : 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          context.loc.new_ep,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 5,
                      ),
                      color: Colors.black.withValues(alpha: 0.72),
                      child: _buildTitleOverlay(context, isLiveStream),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return cardWidget;
  }

  Widget _buildImageContent(BuildContext context, bool isLiveStream) {
    final image = widget.content.imagePath.isNotEmpty
        ? CachedNetworkImage(
            imageUrl: widget.content.imagePath,
            cacheKey: _imageCacheKey,
            fit: _getFitForContentType(),
            useOldImageOnUrlChange: true,
            placeholder: (context, url) => _buildTitleCard(context),
            errorWidget: (context, url, error) => _buildTitleCard(context),
          )
        : _buildTitleCard(context);

    if (!isLiveStream) {
      return image;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 54),
      child: image,
    );
  }

  String get _imageCacheKey {
    final playlistId = AppState.currentPlaylist?.id ?? 'no-playlist';
    return '$playlistId:${widget.content.contentType.name}:${widget.content.id}';
  }

  Widget _buildTitleOverlay(BuildContext context, bool isLiveStream) {
    final title = Text(
      widget.content.name,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 12,
        color: Colors.white,
      ),
      textAlign: TextAlign.center,
      maxLines: isLiveStream ? 1 : 2,
      overflow: TextOverflow.ellipsis,
    );

    if (!isLiveStream && widget.subtitle == null) {
      return title;
    }

    if (!isLiveStream) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          title,
          const SizedBox(height: 2),
          Text(
            widget.subtitle!,
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.82),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }

    final epgFuture = _getEpgFuture();
    if (epgFuture == null) {
      return title;
    }

    return FutureBuilder<List<EpgProgram>?>(
      future: epgFuture,
      builder: (context, snapshot) {
        final programTitle = _currentProgramTitle(snapshot.data);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            title,
            if (programTitle != null) ...[
              const SizedBox(height: 2),
              Text(
                programTitle,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.88),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        );
      },
    );
  }

  Future<List<EpgProgram>?>? _getEpgFuture() {
    final liveStream = widget.content.liveStream;
    final repository = AppState.xtreamCodeRepository;
    if (liveStream == null || repository == null) {
      return null;
    }

    final contentKey = '${liveStream.playlistId}:${liveStream.streamId}';
    if (_epgFuture == null || _epgContentKey != contentKey) {
      _epgContentKey = contentKey;
      _epgFuture = repository.getShortEpg(liveStream.streamId, limit: 2);
    }
    return _epgFuture;
  }

  String? _currentProgramTitle(List<EpgProgram>? programs) {
    if (programs == null || programs.isEmpty) {
      return null;
    }

    final now = DateTime.now();
    for (final program in programs) {
      if (program.nowPlaying || program.isAiringAt(now)) {
        return program.title.isEmpty ? null : program.title;
      }
    }

    final firstTitle = programs.first.title;
    return firstTitle.isEmpty ? null : firstTitle;
  }

  BoxFit _getFitForContentType() {
    if (widget.content.contentType == ContentType.liveStream) {
      return BoxFit.contain;
    }
    return BoxFit.cover;
  }

  Widget _buildTitleCard(BuildContext context) {
    return Container(
      color: widget.isSelected
          ? Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.3)
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Text(
            widget.content.name,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              color: widget.isSelected
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : null,
            ),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget? _buildRatingBadge(BuildContext context) {
    final dynamic rawRating = widget.content.contentType == ContentType.series
        ? widget.content.seriesStream?.rating
        : widget.content.vodStream?.rating;

    final double? rating = _parseRating(rawRating);
    if (rating == null || rating <= 0) {
      return null;
    }

    final colorScheme = Theme.of(context).colorScheme;
    final formattedRating = rating % 1 == 0
        ? rating.toStringAsFixed(0)
        : rating.toStringAsFixed(1);

    return Positioned(
      top: 6,
      right: 6,
      child: Semantics(
        label: 'Rating $formattedRating',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.secondaryContainer.withValues(alpha: 0.93),
                colorScheme.secondary.withValues(alpha: 0.8),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: colorScheme.onSecondaryContainer.withValues(alpha: 0.16),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.22),
                offset: const Offset(0, 1),
                blurRadius: 4,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.star_rounded,
                size: 14,
                color: colorScheme.onSecondaryContainer.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 3),
              Text(
                formattedRating,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                  color: colorScheme.onSecondaryContainer,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double? _parseRating(dynamic rating) {
    if (rating == null) return null;
    if (rating is num) return rating.toDouble();
    if (rating is String && rating.isNotEmpty) {
      final normalized = rating.replaceAll(',', '.');
      return double.tryParse(normalized);
    }
    return null;
  }

  Widget _buildFavoriteButton(BuildContext context) {
    return Positioned(
      top: 6,
      left: 6,
      child: Material(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _isFavoriteLoading ? null : _toggleFavorite,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(
              _isFavorite ? Icons.favorite : Icons.favorite_border,
              size: 20,
              color: _isFavorite ? Colors.red : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
