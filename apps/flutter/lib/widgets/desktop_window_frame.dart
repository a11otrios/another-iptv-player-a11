import 'dart:async';

import 'package:another_iptv_player/services/desktop_window_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DesktopWindowFrame extends StatelessWidget {
  final Widget child;

  const DesktopWindowFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final window = context.watch<DesktopWindowController>();
    if (!window.isSupported || !window.borderless) {
      return child;
    }

    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surface,
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              border: Border(bottom: BorderSide(color: colors.outlineVariant)),
            ),
            child: _DesktopWindowTitleBar(window: window),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _DesktopWindowTitleBar extends StatefulWidget {
  final DesktopWindowController window;

  const _DesktopWindowTitleBar({required this.window});

  @override
  State<_DesktopWindowTitleBar> createState() => _DesktopWindowTitleBarState();
}

class _DesktopWindowTitleBarState extends State<_DesktopWindowTitleBar> {
  String? _hoverLabel;

  void _setHoverLabel(String? value) {
    setState(() {
      _hoverLabel = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final window = widget.window;
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => unawaited(window.startDragging()),
              onDoubleTap: () => unawaited(window.toggleMaximized()),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Icon(Icons.play_circle_fill, size: 17),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _hoverLabel ?? 'Another IPTV Player',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _WindowButton(
            label: window.alwaysOnTop
                ? 'Disable always on top'
                : 'Always on top',
            icon: window.alwaysOnTop ? Icons.push_pin : Icons.push_pin_outlined,
            onHover: _setHoverLabel,
            onPressed: () =>
                unawaited(window.setAlwaysOnTop(!window.alwaysOnTop)),
          ),
          _WindowButton(
            label: 'Restore normal window',
            icon: Icons.web_asset,
            onHover: _setHoverLabel,
            onPressed: () => unawaited(window.restoreNormalWindow()),
          ),
          _WindowButton(
            label: 'Minimize',
            icon: Icons.remove,
            onHover: _setHoverLabel,
            onPressed: () => unawaited(window.minimize()),
          ),
          _WindowButton(
            label: window.isMaximized ? 'Restore' : 'Maximize',
            icon: window.isMaximized ? Icons.filter_none : Icons.crop_square,
            onHover: _setHoverLabel,
            onPressed: () => unawaited(window.toggleMaximized()),
          ),
          _WindowButton(
            label: 'Close',
            icon: Icons.close,
            isClose: true,
            onHover: _setHoverLabel,
            onPressed: () => unawaited(window.close()),
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final ValueChanged<String?> onHover;
  final bool isClose;

  const _WindowButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.onHover,
    this.isClose = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => onHover(label),
      onExit: (_) => onHover(null),
      child: Semantics(
        label: label,
        child: SizedBox(
          width: 42,
          height: 36,
          child: IconButton(
            padding: EdgeInsets.zero,
            iconSize: 18,
            onPressed: onPressed,
            style: IconButton.styleFrom(
              shape: const RoundedRectangleBorder(),
              foregroundColor: isClose ? colors.error : colors.onSurface,
              hoverColor: isClose
                  ? colors.errorContainer
                  : colors.onSurface.withValues(alpha: 0.08),
            ),
            icon: Icon(icon),
          ),
        ),
      ),
    );
  }
}
