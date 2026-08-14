import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:another_iptv_player/utils/category_item_sort.dart';
import 'package:flutter/material.dart';

class CategoryAppBar extends StatelessWidget {
  final String title;
  final bool isSearching;
  final TextEditingController searchController;
  final VoidCallback onSearchStart;
  final VoidCallback onSearchStop;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<CategoryItemSort>? onSortSelected;
  final CategoryItemSort? selectedSort;

  const CategoryAppBar({
    super.key,
    required this.title,
    required this.isSearching,
    required this.searchController,
    required this.onSearchStart,
    required this.onSearchStop,
    required this.onSearchChanged,
    this.onSortSelected,
    this.selectedSort,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      floating: true,
      snap: true,
      title: isSearching ? _buildSearchField(context) : SelectableText(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      actions: [
        if (onSortSelected != null)
          PopupMenuButton<CategoryItemSort>(
            icon: const Icon(Icons.sort),
            onSelected: onSortSelected,
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: CategoryItemSort.rating,
                checked: selectedSort == CategoryItemSort.rating,
                child: const Text('User rating (highest first)'),
              ),
              CheckedPopupMenuItem(
                value: CategoryItemSort.releaseDate,
                checked: selectedSort == CategoryItemSort.releaseDate,
                child: const Text('Release date (newest first)'),
              ),
              CheckedPopupMenuItem(
                value: CategoryItemSort.releaseDateAscending,
                checked: selectedSort == CategoryItemSort.releaseDateAscending,
                child: const Text('Release date (oldest first)'),
              ),
              CheckedPopupMenuItem(
                value: CategoryItemSort.provider,
                checked: selectedSort == CategoryItemSort.provider,
                child: const Text('Original order'),
              ),
            ],
          ),
        IconButton(
          icon: Icon(isSearching ? Icons.clear : Icons.search),
          onPressed: isSearching ? onSearchStop : onSearchStart,
        ),
      ],
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return TextField(
      controller: searchController,
      decoration: InputDecoration(
        hintText: context.loc.search,
        border: InputBorder.none,
      ),
      autofocus: true,
      onChanged: onSearchChanged,
    );
  }
}
