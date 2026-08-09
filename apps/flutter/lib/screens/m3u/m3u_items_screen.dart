import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:another_iptv_player/controllers/favorites_controller.dart';
import 'package:another_iptv_player/models/m3u_item.dart';
import 'package:another_iptv_player/screens/m3u/m3u_player_screen.dart';
import 'package:flutter/material.dart';
import '../../models/content_type.dart';
import '../../models/playlist_content_model.dart';
import '../../utils/navigate_by_content_type.dart';

class M3uItemsScreen extends StatefulWidget {
  final List<M3uItem> m3uItems;

  const M3uItemsScreen({super.key, required this.m3uItems});

  @override
  State<M3uItemsScreen> createState() => _M3uItemsScreenState();
}

class _M3uItemsScreenState extends State<M3uItemsScreen> {
  List<M3uItem> filteredItems = [];
  String searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool isSearching = false;
  final ScrollController _chipScrollController = ScrollController();
  final FavoritesController _favoritesController = FavoritesController();
  final Set<String> _favoriteIds = {};

  @override
  void initState() {
    super.initState();
    filteredItems = widget.m3uItems;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFavorites();
    });
  }

  @override
  void didUpdateWidget(covariant M3uItemsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.m3uItems != widget.m3uItems) {
      _filterItems(searchQuery);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _chipScrollController.dispose();
    _favoritesController.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    await _favoritesController.loadFavorites();
    if (!mounted) return;
    setState(() {
      _favoriteIds
        ..clear()
        ..addAll(
          _favoritesController.favorites.map((favorite) {
            return favorite.m3uItemId ?? favorite.streamId;
          }),
        );
    });
  }

  void _filterItems(String query) {
    setState(() {
      searchQuery = query;
      if (query.isEmpty) {
        filteredItems = widget.m3uItems;
      } else {
        filteredItems = widget.m3uItems.where((item) {
          final name = item.name?.toLowerCase() ?? '';
          final group = item.groupTitle?.toLowerCase() ?? '';
          final searchLower = query.toLowerCase();
          return name.contains(searchLower) || group.contains(searchLower);
        }).toList();
      }
    });
  }

  void _filterByGroup(String group) {
    setState(() {
      filteredItems = widget.m3uItems
          .where((item) => item.groupTitle == group)
          .toList();
      searchQuery = group;
    });
  }

  List<String> _getUniqueGroups() {
    final groups = widget.m3uItems
        .where((item) => item.groupTitle != null)
        .map((item) => item.groupTitle!)
        .toSet()
        .toList();
    groups.sort();
    return groups.toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      appBar: AppBar(
        title: isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: context.loc.search,
                  border: InputBorder.none,
                ),
                onChanged: _filterItems,
              )
            : SelectableText(
                context.loc.iptv_channels_count(filteredItems.length),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
        actions: [
          IconButton(
            icon: Icon(isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                isSearching = !isSearching;
                if (!isSearching) {
                  _searchController.clear();
                  _filterItems('');
                }
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (!isSearching && _getUniqueGroups().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                height: 50,
                child: isDesktop
                    ? Scrollbar(
                        controller: _chipScrollController,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: _chipScrollController,
                          scrollDirection: Axis.horizontal,
                          itemCount: _getUniqueGroups().length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return _buildFilterChip(
                                context.loc.see_all,
                                null,
                              );
                            }
                            final group = _getUniqueGroups()[index - 1];
                            return _buildFilterChip(group, group);
                          },
                        ),
                      )
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _getUniqueGroups().length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _buildFilterChip(context.loc.see_all, null);
                          }
                          final group = _getUniqueGroups()[index - 1];
                          return _buildFilterChip(group, group);
                        },
                      ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredItems.length,
              itemBuilder: (context, index) {
                final channel = filteredItems[index];

                return Container(
                  height: 80,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withValues(alpha: 0.1),
                        spreadRadius: 1,
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _onChannelTap(context, channel),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          _buildSimpleLogo(channel),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  channel.name ?? context.loc.unknown_channel,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (channel.groupTitle != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    channel.groupTitle!,
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getContentTypeColor(
                                channel,
                              ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _getContentTypeText(channel),
                              style: TextStyle(
                                fontSize: 10,
                                color: _getContentTypeColor(channel),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: _favoriteIds.contains(channel.id)
                                ? context.loc.remove_from_favorites
                                : context.loc.added_to_favorites,
                            icon: Icon(
                              _favoriteIds.contains(channel.id)
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: _favoriteIds.contains(channel.id)
                                  ? Colors.red
                                  : null,
                            ),
                            onPressed: () => _toggleFavorite(channel),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String? groupFilter) {
    final isSelected =
        (groupFilter == null && searchQuery.isEmpty) ||
        (groupFilter != null && searchQuery == groupFilter);

    return Container(
      margin: const EdgeInsets.only(left: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          if (groupFilter == null) {
            _filterItems('');
          } else {
            _filterByGroup(groupFilter);
          }
        },
      ),
    );
  }

  Widget _buildSimpleLogo(M3uItem channel) {
    if (channel.tvgLogo != null && channel.tvgLogo!.isNotEmpty) {
      return Container(
        width: 50,
        height: 35,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: Colors.grey[100],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(
            channel.tvgLogo!,
            width: 50,
            height: 35,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) =>
                _buildPlaceholderIcon(),
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return _buildPlaceholderIcon();
            },
          ),
        ),
      );
    }
    return _buildPlaceholderIcon();
  }

  Widget _buildPlaceholderIcon() {
    return Container(
      width: 50,
      height: 35,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: Colors.grey[200],
      ),
      child: Icon(Icons.tv, color: Colors.grey[500], size: 20),
    );
  }

  Color _getContentTypeColor(M3uItem channel) {
    switch (channel.contentType) {
      case ContentType.liveStream:
        return Colors.red;
      case ContentType.vod:
        return Colors.blue;
      case ContentType.series:
        return Colors.green;
    }
  }

  String _getContentTypeText(M3uItem channel) {
    switch (channel.contentType) {
      case ContentType.liveStream:
        return context.loc.live_content;
      case ContentType.vod:
        return context.loc.movie_content;
      case ContentType.series:
        return context.loc.series_content;
    }
  }

  void _onChannelTap(BuildContext context, M3uItem m3uItem) {
    if (m3uItem.groupTitle != null &&
        m3uItem.groupTitle!.isNotEmpty &&
        m3uItem.contentType != ContentType.series) {
      final contentItem = _toContentItem(m3uItem);
      final queue = filteredItems
          .where((item) => item.contentType == m3uItem.contentType)
          .map(_toContentItem)
          .toList();

      navigateByContentType(context, contentItem, queue: queue);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => M3uPlayerScreen(
            contentItem: ContentItem(
              m3uItem.id,
              m3uItem.name ?? '',
              m3uItem.tvgLogo ?? '',
              m3uItem.contentType,
              m3uItem: m3uItem,
            ),
          ),
        ),
      );
    }
  }

  ContentItem _toContentItem(M3uItem item) {
    return ContentItem(
      item.url,
      item.name ?? '',
      item.tvgLogo ?? '',
      item.contentType,
      m3uItem: item,
    );
  }

  Future<void> _toggleFavorite(M3uItem m3uItem) async {
    final contentItem = ContentItem(
      m3uItem.id,
      m3uItem.name ?? context.loc.unknown_channel,
      m3uItem.tvgLogo ?? '',
      m3uItem.contentType,
      m3uItem: m3uItem,
    );
    final isFavorite = _favoriteIds.contains(m3uItem.id);
    final success = isFavorite
        ? await _favoritesController.removeFavorite(
            contentItem.id,
            contentItem.contentType,
          )
        : await _favoritesController.addFavorite(contentItem);

    if (!success || !mounted) return;

    setState(() {
      if (isFavorite) {
        _favoriteIds.remove(m3uItem.id);
      } else {
        _favoriteIds.add(m3uItem.id);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isFavorite
              ? context.loc.removed_from_favorites
              : context.loc.added_to_favorites,
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
