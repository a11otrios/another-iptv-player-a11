import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/playlist_content_model.dart';
import '../../services/event_bus.dart';
import '../../utils/helpers.dart';
import 'content_card.dart';

class ContentItemCardWidget extends StatefulWidget {
  final double cardWidth;
  final double cardHeight;
  final Function(ContentItem)? onContentTap;
  final List<ContentItem> contentItems;
  final int initialSelectedIndex;
  final bool isSelectionModeEnabled;

  const ContentItemCardWidget({
    super.key,
    required this.cardHeight,
    required this.cardWidth,
    required this.contentItems,
    this.onContentTap,
    this.initialSelectedIndex = -1,
    this.isSelectionModeEnabled = false,
  });

  @override
  State<ContentItemCardWidget> createState() => _ContentItemCardWidgetState();
}

class _ContentItemCardWidgetState extends State<ContentItemCardWidget> {
  late StreamSubscription contentItemIndexChangedSubscription;
  late StreamSubscription contentItemIndexSubscription;
  int selectedIndex = -1;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    selectedIndex = widget.initialSelectedIndex;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialSelectedIndex >= 0) {
        _scrollToIndex(widget.initialSelectedIndex);
      }
    });

    contentItemIndexSubscription = EventBus()
        .on<int>('player_content_item_index')
        .listen((int index) {
          if (!mounted) return;
          selectAndScrollToIndex(index);
        });

    contentItemIndexChangedSubscription = EventBus()
        .on<int>('player_content_item_index_changed')
        .listen((int index) {
          if (!mounted) return;
          selectAndScrollToIndex(index);
        });
  }

  @override
  void dispose() {
    contentItemIndexSubscription.cancel();
    contentItemIndexChangedSubscription.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToIndex(int index) {
    if (index < 0 || index >= widget.contentItems.length) return;

    if (!_scrollController.hasClients) return;

    double screenWidth = MediaQuery.of(context).size.width;

    double cardTotalWidth = widget.cardWidth + 8;
    double targetPosition =
        (cardTotalWidth * index) + (widget.cardWidth / 2) - (screenWidth / 2);

    double maxScrollExtent = _scrollController.position.maxScrollExtent;
    double minScrollExtent = _scrollController.position.minScrollExtent;

    if (targetPosition < minScrollExtent) {
      targetPosition = minScrollExtent;
    } else if (targetPosition > maxScrollExtent) {
      targetPosition = maxScrollExtent;
    }

    _scrollController.animateTo(
      targetPosition,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void selectAndScrollToIndex(int index) {
    if (index < 0 ||
        index >= widget.contentItems.length ||
        !widget.isSelectionModeEnabled) {
      return;
    }

    setState(() {
      selectedIndex = index;
    });

    // _scrollToIndex(index);
  }

  @override
  Widget build(BuildContext context) {
    final itemIndexes = <Key, int>{
      for (var index = 0; index < widget.contentItems.length; index++)
        _contentKey(widget.contentItems[index]): index,
    };
    final contentList = ListView.builder(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: widget.contentItems.length,
      findChildIndexCallback: (key) => itemIndexes[key],
      itemBuilder: (context, index) {
        final content = widget.contentItems[index];
        return Container(
          key: _contentKey(content),
          width: widget.cardWidth,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          child: ContentCard(
            content: content,
            width: widget.cardWidth,
            onTap: () {
              selectAndScrollToIndex(index);
              widget.onContentTap?.call(content);
            },
            isSelected: selectedIndex == index,
          ),
        );
      },
    );

    return SizedBox(
      height: widget.cardHeight,
      child: isDesktop
          ? Scrollbar(
              controller: _scrollController,
              thumbVisibility: false,
              trackVisibility: false,
              child: contentList,
            )
          : contentList,
    );
  }

  ValueKey<String> _contentKey(ContentItem content) {
    return ValueKey('content-${content.contentType.name}-${content.id}');
  }
}
