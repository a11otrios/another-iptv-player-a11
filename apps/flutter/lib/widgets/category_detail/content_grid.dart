import 'package:flutter/material.dart';
import 'package:another_iptv_player/models/playlist_content_model.dart';
import 'package:another_iptv_player/utils/responsive_helper.dart';

import '../content_card.dart';

class ContentGrid extends StatelessWidget {
  final List<ContentItem> items;
  final Function(ContentItem) onItemTap;

  const ContentGrid({super.key, required this.items, required this.onItemTap});

  @override
  Widget build(BuildContext context) {
    final itemIndexes = <Key, int>{
      for (var index = 0; index < items.length; index++)
        _contentKey(items[index]): index,
    };

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: ResponsiveHelper.getCrossAxisCount(context),
        childAspectRatio: 0.65,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: items.length,
      findChildIndexCallback: (key) => itemIndexes[key],
      itemBuilder: (context, index) {
        final item = items[index];
        return ContentCard(
          key: _contentKey(item),
          content: item,
          width: 150,
          onTap: () => onItemTap(item),
        );
      },
    );
  }

  ValueKey<String> _contentKey(ContentItem content) {
    return ValueKey('content-${content.contentType.name}-${content.id}');
  }
}
