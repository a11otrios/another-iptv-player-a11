import 'package:another_iptv_player/models/playlist_content_model.dart';

enum CategoryItemSort {
  provider,
  nameAscending,
  nameDescending,
  releaseDate,
  rating;

  static CategoryItemSort fromPreference(String? value) {
    return CategoryItemSort.values.firstWhere(
      (sort) => sort.name == value,
      orElse: () => CategoryItemSort.provider,
    );
  }
}

List<ContentItem> sortCategoryItems(
  Iterable<ContentItem> items,
  CategoryItemSort sort,
) {
  final indexed = items.indexed.toList();
  if (sort == CategoryItemSort.provider || indexed.length < 2) {
    return indexed.map((entry) => entry.$2).toList();
  }

  indexed.sort((first, second) {
    final comparison = _compareItems(first.$2, second.$2, sort);
    return comparison != 0 ? comparison : first.$1.compareTo(second.$1);
  });
  return indexed.map((entry) => entry.$2).toList();
}

int _compareItems(
  ContentItem first,
  ContentItem second,
  CategoryItemSort sort,
) {
  switch (sort) {
    case CategoryItemSort.provider:
      return 0;
    case CategoryItemSort.nameAscending:
      return _normalizedName(first).compareTo(_normalizedName(second));
    case CategoryItemSort.nameDescending:
      return _normalizedName(second).compareTo(_normalizedName(first));
    case CategoryItemSort.releaseDate:
      return _compareNullableDescending(
        _releaseDateValue(first),
        _releaseDateValue(second),
      );
    case CategoryItemSort.rating:
      return _compareNullableDescending(_rating(first), _rating(second));
  }
}

String _normalizedName(ContentItem item) => item.name.trim().toLowerCase();

int _compareNullableDescending(num? first, num? second) {
  if (first == null && second == null) return 0;
  if (first == null) return 1;
  if (second == null) return -1;
  return second.compareTo(first);
}

int? _releaseDateValue(ContentItem item) {
  final seriesDate = item.seriesStream?.releaseDate?.trim();
  if (seriesDate != null && seriesDate.isNotEmpty) {
    final parsed = DateTime.tryParse(seriesDate);
    if (parsed != null) return parsed.millisecondsSinceEpoch;
    final year = _yearFromText(seriesDate);
    if (year != null) return DateTime(year).millisecondsSinceEpoch;
  }

  // Xtream movie lists commonly carry the release year in the title.
  final year = _yearFromText(item.name);
  return year == null ? null : DateTime(year).millisecondsSinceEpoch;
}

int? _yearFromText(String value) {
  final matches = RegExp(
    r'(?<!\d)(18\d{2}|19\d{2}|20\d{2}|21\d{2})(?!\d)',
  ).allMatches(value).toList();
  return matches.isEmpty ? null : int.tryParse(matches.last.group(0)!);
}

double? _rating(ContentItem item) {
  final value = item.seriesStream?.rating ?? item.vodStream?.rating;
  return value == null ? null : double.tryParse(value);
}
