import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:another_iptv_player/models/category_view_model.dart';
import 'package:another_iptv_player/models/category_type.dart';
import 'package:another_iptv_player/models/content_type.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/models/view_state.dart';
import 'package:another_iptv_player/repositories/iptv_repository.dart';
import 'package:another_iptv_player/repositories/user_preferences.dart';
import 'package:another_iptv_player/screens/xtream-codes/xtream_code_data_loader_screen.dart';
import 'package:another_iptv_player/services/app_state.dart';
import 'package:flutter/material.dart';
import 'package:another_iptv_player/utils/radio_station_filter.dart';

class XtreamCodeHomeController extends ChangeNotifier {
  late PageController _pageController;
  final IptvRepository _repository = AppState.xtreamCodeRepository!;
  String? _errorMessage;
  ViewState _viewState = ViewState.idle;

  int _currentIndex = 0;
  final bool _isLoading = false;

  final List<CategoryViewModel> _liveCategories = [];
  final List<CategoryViewModel> _movieCategories = [];
  final List<CategoryViewModel> _seriesCategories = [];
  final Set<String> _hiddenCategoryKeys = {};
  bool _hideRadioStations = false;

  PageController get pageController => _pageController;

  int get currentIndex => _currentIndex;

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  ViewState get viewState => _viewState;

  List<CategoryViewModel> get liveCategories => _liveCategories;

  List<CategoryViewModel> get movieCategories => _movieCategories;

  List<CategoryViewModel> get seriesCategories => _seriesCategories;

  List<CategoryViewModel> get visibleLiveCategories =>
      _visibleCategories(_liveCategories);

  List<CategoryViewModel> get visibleMovieCategories =>
      _visibleCategories(_movieCategories);

  List<CategoryViewModel> get visibleSeriesCategories =>
      _visibleCategories(_seriesCategories);

  XtreamCodeHomeController(bool all) {
    _pageController = PageController();
    _loadCategories();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void onNavigationTap(int index) {
    _currentIndex = index;
    notifyListeners();

    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void onPageChanged(int index) {
    _currentIndex = index;
    notifyListeners();
  }

  String getPageTitle(BuildContext context) {
    switch (currentIndex) {
      case 0:
        return context.loc.history;
      case 1:
        return context.loc.favorites;
      case 2:
        return context.loc.live_streams;
      case 3:
        return context.loc.movies;
      case 4:
        return context.loc.series_plural;
      case 5:
        return context.loc.settings;
      default:
        return 'Another IPTV Player';
    }
  }

  void _setViewState(ViewState state) {
    _viewState = state;
    if (state != ViewState.error) {
      _errorMessage = null;
    }
    notifyListeners();
  }

  Future<void> _loadCategories() async {
    try {
      await reloadHiddenCategories(notify: false);
      final liveCategories = await _repository.getLiveCategories();
      if (liveCategories != null && liveCategories.isNotEmpty) {
        for (final liveCategory in liveCategories) {
          final liveStreams = await _repository.getLiveChannelsByCategoryId(
            categoryId: liveCategory.categoryId,
            top: 10,
          );

          if (liveStreams == null || liveStreams.isEmpty) continue;

          _liveCategories.add(
            CategoryViewModel(
              category: liveCategory,
              contentItems: liveStreams
                  .map(
                    (x) => ContentItem(
                      x.streamId,
                      x.name,
                      x.streamIcon,
                      ContentType.liveStream,
                      liveStream: x,
                    ),
                  )
                  .toList(),
            ),
          );
        }
      }

      final movieCategories = await _repository.getVodCategories();
      if (movieCategories != null && movieCategories.isNotEmpty) {
        for (final movieCategory in movieCategories) {
          final movies = await _repository.getMovies(
            categoryId: movieCategory.categoryId,
            top: 10,
          );

          if (movies == null || movies.isEmpty) {
            continue;
          }

          _movieCategories.add(
            CategoryViewModel(
              category: movieCategory,
              contentItems: movies
                  .map(
                    (x) => ContentItem(
                      x.streamId,
                      x.name,
                      x.streamIcon,
                      ContentType.vod,
                      containerExtension: x.containerExtension,
                      vodStream: x,
                    ),
                  )
                  .toList(),
            ),
          );
        }
      }

      final seriesCategories = await _repository.getSeriesCategories();
      if (seriesCategories != null && seriesCategories.isNotEmpty) {
        for (final seriesCategory in seriesCategories) {
          final series = await _repository.getSeries(
            categoryId: seriesCategory.categoryId,
            top: 10,
          );

          if (series == null || series.isEmpty) {
            continue;
          }

          _seriesCategories.add(
            CategoryViewModel(
              category: seriesCategory,
              contentItems: series
                  .map(
                    (x) => ContentItem(
                      x.seriesId,
                      x.name,
                      x.cover ?? '',
                      ContentType.series,
                      seriesStream: x,
                    ),
                  )
                  .toList(),
            ),
          );
        }
      }

      notifyListeners();
    } catch (e, st) {
      debugPrint(st.toString());
      _errorMessage = 'Kategoriler yuklenemedi: $e';
      _setViewState(ViewState.error);
    }
  }

  Future<void> reloadHiddenCategories({bool notify = true}) async {
    final hidden = await UserPreferences.getHiddenCategories(
      playlistId: AppState.currentPlaylist?.id,
    );
    _hiddenCategoryKeys
      ..clear()
      ..addAll(hidden);
    final playlistId = AppState.currentPlaylist?.id;
    _hideRadioStations =
        playlistId != null &&
        await UserPreferences.getHideRadioStations(playlistId: playlistId);
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> reloadCategoryPreferences({bool notify = true}) async {
    await reloadHiddenCategories(notify: false);
    final playlistId = AppState.currentPlaylist?.id;
    if (playlistId != null) {
      await _applyOrder(_liveCategories, playlistId);
      await _applyOrder(_movieCategories, playlistId);
      await _applyOrder(_seriesCategories, playlistId);
    }
    if (notify) notifyListeners();
  }

  Future<void> _applyOrder(
    List<CategoryViewModel> categories,
    String playlistId,
  ) async {
    if (categories.isEmpty) return;
    final order = await UserPreferences.getCategoryOrder(
      playlistId: playlistId,
      type: categories.first.category.type,
    );
    final ordered = UserPreferences.applyCategoryOrder(
      categories,
      order,
      (category) => category.category.categoryId,
    );
    categories
      ..clear()
      ..addAll(ordered);
  }

  List<CategoryViewModel> _visibleCategories(
    List<CategoryViewModel> categories,
  ) {
    return categories.where((category) {
      final key = UserPreferences.hiddenCategoryKey(
        category.category.type,
        category.category.categoryId,
      );
      return !_hiddenCategoryKeys.contains(key) &&
          !_hiddenCategoryKeys.contains(category.category.categoryId) &&
          (!_hideRadioStations ||
              category.category.type != CategoryType.live ||
              !isLikelyRadioStation('', category.category.categoryName));
    }).toList();
  }

  refreshAllData(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => XtreamCodeDataLoaderScreen(
          playlist: AppState.currentPlaylist!,
          refreshAll: true,
        ),
      ),
    );
  }
}
