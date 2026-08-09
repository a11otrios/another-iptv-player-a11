import 'package:flutter/material.dart';
import 'package:another_iptv_player/models/category_view_model.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import '../services/content_service.dart';
import '../repositories/user_preferences.dart';
import '../utils/category_item_sort.dart';

class CategoryDetailController extends ChangeNotifier {
  final CategoryViewModel category;
  final ContentService _contentService = ContentService();

  CategoryDetailController(this.category) {
    loadContent();
  }

  // --- State ---
  List<ContentItem> _contentItems = [];
  List<ContentItem> _filteredItems = [];
  bool _isLoading = true;
  bool _isSearching = false;
  String? _errorMessage;
  CategoryItemSort _sort = CategoryItemSort.provider;

  // --- Genre filtering ---
  List<String> _genres = [];
  String? _selectedGenre;

  // --- Getters ---
  List<ContentItem> get contentItems => _contentItems;
  List<ContentItem> get filteredItems => _filteredItems;
  List<ContentItem> get displayItems => sortCategoryItems(
    _isSearching ? _filteredItems : _applyGenreFilter(_contentItems),
    _sort,
  );
  bool get isLoading => _isLoading;
  bool get isSearching => _isSearching;
  String? get errorMessage => _errorMessage;
  bool get isEmpty => displayItems.isEmpty && !_isLoading;

  List<String> get genres => _genres;
  String? get selectedGenre => _selectedGenre;
  CategoryItemSort get sort => _sort;

  Future<void> loadContent() async {
    try {
      _setLoading(true);
      _contentItems = await _contentService.fetchContentByCategory(category);
      _sort = await UserPreferences.getCategoryItemSort(
        playlistId: category.category.playlistId,
        type: category.category.type,
        categoryId: category.category.categoryId,
      );
      _genres = _extractGenres(_contentItems);
      _selectedGenre = null;
      _updateCategoryPreview();
      _setLoading(false);
    } catch (error) {
      _setError(error.toString());
    }
  }

  List<String> _extractGenres(List<ContentItem> items) {
    final Set<String> genreSet = {};

    for (final item in items) {
      final rawGenre = _getItemGenre(item);
      if (rawGenre != null && rawGenre.isNotEmpty) {
        // Split on common separators (comma, slash, backslash, pipe, ampersand, semicolon, Arabic comma) (with surrounding spaces)
        final parts = rawGenre
            .split(RegExp(r'\s*[,/\\|&;،]+\s*'))
            .map((g) => g.trim())
            .where((g) => g.isNotEmpty)
            .toSet();
        genreSet.addAll(parts);
      }
    }

    final sorted = genreSet.toList()..sort();
    return sorted;
  }

  String? _getItemGenre(ContentItem item) {
    if (item.contentType.name == "series") {
      return item.seriesStream?.genre;
    } else {
      return item.vodStream?.genre;
    }
  }

  void filterByGenre(String? genre) {
    _selectedGenre = genre;
    notifyListeners();
  }

  List<ContentItem> _applyGenreFilter(List<ContentItem> items) {
    if (_selectedGenre == null || _selectedGenre!.isEmpty) return items;

    // We compare lowercased versions to be safe
    final genreLower = _selectedGenre!.toLowerCase();
    return items.where((item) {
      final rawGenre = _getItemGenre(item);
      if (rawGenre == null) return false;

      // Use the same splitter logic to check if the item contains the selected genre
      final itemGenres = rawGenre
          .split(RegExp(r'\s*[,/\\|&;،]+\s*'))
          .map((g) => g.trim().toLowerCase());

      return itemGenres.contains(genreLower);
    }).toList();
  }

  void startSearch() {
    _isSearching = true;
    _filteredItems = [];
    notifyListeners();
  }

  void stopSearch() {
    _isSearching = false;
    _filteredItems = [];
    notifyListeners();
  }

  void searchContent(String query) {
    if (query.trim().isEmpty) {
      _filteredItems = [];
    } else {
      _filteredItems = _contentItems
          .where(
            (item) =>
                item.name.toLowerCase().contains(query.trim().toLowerCase()),
          )
          .toList();
    }
    notifyListeners();
  }

  Future<void> sortItems(CategoryItemSort sort) async {
    _sort = sort;
    _updateCategoryPreview();
    notifyListeners();
    await UserPreferences.setCategoryItemSort(
      playlistId: category.category.playlistId,
      type: category.category.type,
      categoryId: category.category.categoryId,
      sort: sort,
    );
  }

  void _updateCategoryPreview() {
    final sorted = sortCategoryItems(_contentItems, _sort);
    category.contentItems
      ..clear()
      ..addAll(sorted.take(10));
  }

  // --- State helpers ---
  void _setLoading(bool loading) {
    _isLoading = loading;
    _errorMessage = null;
    notifyListeners();
  }

  void _setError(String error) {
    _isLoading = false;
    _errorMessage = error;
    notifyListeners();
  }
}
