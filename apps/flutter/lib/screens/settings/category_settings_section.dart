import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:another_iptv_player/models/category_type.dart';
import 'package:another_iptv_player/models/category_view_model.dart';
import 'package:another_iptv_player/repositories/user_preferences.dart';
import 'package:flutter/material.dart';

class CategorySettingsScreen extends StatefulWidget {
  final String playlistId;
  final List<CategoryViewModel> liveCategories;
  final List<CategoryViewModel> movieCategories;
  final List<CategoryViewModel> seriesCategories;

  const CategorySettingsScreen({
    super.key,
    required this.playlistId,
    this.liveCategories = const [],
    this.movieCategories = const [],
    this.seriesCategories = const [],
  });

  @override
  State<CategorySettingsScreen> createState() => _CategorySettingsScreenState();
}

class _CategorySettingsScreenState extends State<CategorySettingsScreen> {
  Set<String> _hiddenCategories = {};
  late final Map<CategoryType, List<CategoryViewModel>> _categories;
  final Map<CategoryType, List<String>> _originalOrder = {};
  bool _hideRadioStations = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _categories = {
      CategoryType.live: List.of(widget.liveCategories),
      CategoryType.vod: List.of(widget.movieCategories),
      CategoryType.series: List.of(widget.seriesCategories),
    };
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final hidden = await UserPreferences.getHiddenCategories(
      playlistId: widget.playlistId,
    );
    final hideRadioStations = await UserPreferences.getHideRadioStations(
      playlistId: widget.playlistId,
    );
    for (final type in CategoryType.values) {
      final order = await UserPreferences.getCategoryOrder(
        playlistId: widget.playlistId,
        type: type,
      );
      final original = await UserPreferences.getCategoryOriginalOrder(
        playlistId: widget.playlistId,
        type: type,
      );
      _originalOrder[type] = original.isEmpty
          ? _categories[type]!
                .map((category) => category.category.categoryId)
                .toList()
          : original;
      _categories[type] = UserPreferences.applyCategoryOrder(
        _categories[type]!,
        order,
        (category) => category.category.categoryId,
      );
    }
    if (!mounted) return;
    setState(() {
      _hiddenCategories = hidden.toSet();
      _hideRadioStations = hideRadioStations;
    });
  }

  Future<void> _setHideRadioStations(bool value) async {
    setState(() {
      _hasChanges = true;
      _hideRadioStations = value;
    });
    await UserPreferences.setHideRadioStations(
      playlistId: widget.playlistId,
      value: value,
    );
  }

  Future<void> _toggleHidden(
    bool isVisible,
    CategoryType type,
    String categoryId,
  ) async {
    final key = UserPreferences.hiddenCategoryKey(type, categoryId);
    setState(() {
      _hasChanges = true;
      if (isVisible) {
        _hiddenCategories
          ..remove(key)
          ..remove(categoryId);
      } else {
        _hiddenCategories.add(key);
      }
    });
    await _saveHiddenCategories();
  }

  Future<void> _setAllCategoriesVisible(
    CategoryType type,
    Iterable<String> ids,
    bool visible,
  ) async {
    setState(() {
      _hasChanges = true;
      final keys = ids.map((id) => UserPreferences.hiddenCategoryKey(type, id));
      if (visible) {
        _hiddenCategories
          ..removeAll(keys)
          ..removeAll(ids);
      } else {
        _hiddenCategories.addAll(keys);
      }
    });
    await _saveHiddenCategories();
  }

  Future<void> _saveHiddenCategories() async {
    await UserPreferences.setHiddenCategories(
      _hiddenCategories.toList(),
      playlistId: widget.playlistId,
    );
  }

  Future<void> _moveCategory(CategoryType type, int index, int offset) async {
    final categories = _categories[type]!;
    final target = index + offset;
    if (target < 0 || target >= categories.length) return;
    setState(() {
      _hasChanges = true;
      final category = categories.removeAt(index);
      categories.insert(target, category);
    });
    await _saveCategoryOrder(type);
  }

  Future<void> _moveCategoryToTop(CategoryType type, int index) async {
    if (index <= 0) return;
    final categories = _categories[type]!;
    setState(() {
      _hasChanges = true;
      categories.insert(0, categories.removeAt(index));
    });
    await _saveCategoryOrder(type);
  }

  Future<void> _restoreCategoryPosition(CategoryType type, int index) async {
    final categories = _categories[type]!;
    final categoryId = categories[index].category.categoryId;
    final originalIndex = _originalOrder[type]?.indexOf(categoryId) ?? -1;
    if (originalIndex < 0) return;
    final target = originalIndex.clamp(0, categories.length - 1);
    if (target == index) return;
    setState(() {
      _hasChanges = true;
      categories.insert(target, categories.removeAt(index));
    });
    await _saveCategoryOrder(type);
  }

  Future<void> _saveCategoryOrder(CategoryType type) async {
    final categories = _categories[type]!;
    await UserPreferences.setCategoryOrder(
      playlistId: widget.playlistId,
      type: type,
      categoryIds: categories
          .map((category) => category.category.categoryId)
          .toList(),
    );
  }

  void _closeScreen(BuildContext context) {
    Navigator.pop(context, _hasChanges);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _closeScreen(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.loc.manage_categories),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _closeScreen(context),
          ),
        ),
        body: ListView(
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.radio),
              title: Text(context.loc.hide_radio_stations),
              value: _hideRadioStations,
              onChanged: _setHideRadioStations,
            ),
            _buildCategoryGroup(
              context,
              title: context.loc.live,
              type: CategoryType.live,
              categories: _categories[CategoryType.live]!,
            ),
            _buildCategoryGroup(
              context,
              title: context.loc.movies,
              type: CategoryType.vod,
              categories: _categories[CategoryType.vod]!,
            ),
            _buildCategoryGroup(
              context,
              title: context.loc.series_plural,
              type: CategoryType.series,
              categories: _categories[CategoryType.series]!,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryGroup(
    BuildContext context, {
    required String title,
    required CategoryType type,
    required List<CategoryViewModel> categories,
  }) {
    if (categories.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        ListTile(title: Text(title), tileColor: Colors.black12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => _setAllCategoriesVisible(
                type,
                categories.map((c) => c.category.categoryId),
                true,
              ),
              child: Text(context.loc.select_all),
            ),
            TextButton(
              onPressed: () => _setAllCategoriesVisible(
                type,
                categories.map((c) => c.category.categoryId),
                false,
              ),
              child: Text(context.loc.deselect_all),
            ),
          ],
        ),
        ...categories.indexed.map((entry) {
          final index = entry.$1;
          final category = entry.$2;
          final categoryId = category.category.categoryId;
          final key = UserPreferences.hiddenCategoryKey(type, categoryId);
          final isHidden =
              _hiddenCategories.contains(key) ||
              _hiddenCategories.contains(categoryId);
          final widgets = WidgetsLocalizations.of(context);
          final originalIndex = _originalOrder[type]?.indexOf(categoryId) ?? -1;
          return ListTile(
            title: Text(category.category.categoryName),
            leading: Switch(
              value: !isHidden,
              onChanged: (value) => _toggleHidden(value, type, categoryId),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: context.loc.move_to_top,
                  icon: const Icon(Icons.vertical_align_top),
                  onPressed: index == 0
                      ? null
                      : () => _moveCategoryToTop(type, index),
                ),
                IconButton(
                  tooltip: widgets.reorderItemUp,
                  icon: const Icon(Icons.keyboard_arrow_up),
                  onPressed: index == 0
                      ? null
                      : () => _moveCategory(type, index, -1),
                ),
                IconButton(
                  tooltip: widgets.reorderItemDown,
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed: index == categories.length - 1
                      ? null
                      : () => _moveCategory(type, index, 1),
                ),
                IconButton(
                  tooltip: context.loc.restore_original_position,
                  icon: const Icon(Icons.restore),
                  onPressed: originalIndex < 0 || originalIndex == index
                      ? null
                      : () => _restoreCategoryPosition(type, index),
                ),
              ],
            ),
            onTap: () => _toggleHidden(isHidden, type, categoryId),
          );
        }),
      ],
    );
  }
}
