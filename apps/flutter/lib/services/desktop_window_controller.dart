import 'package:another_iptv_player/repositories/user_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DesktopWindowController extends ChangeNotifier {
  static const MethodChannel _defaultChannel = MethodChannel(
    'another_iptv_player/window',
  );

  static final DesktopWindowController instance = DesktopWindowController();

  final MethodChannel _channel;
  final bool? _isSupportedOverride;

  bool _borderless = false;
  bool _alwaysOnTop = false;
  bool _isMaximized = false;
  bool _nativeBorderlessApplied = false;
  bool _nativeAlwaysOnTopApplied = false;

  DesktopWindowController({
    MethodChannel channel = _defaultChannel,
    bool? isSupportedOverride,
  }) : _channel = channel,
       _isSupportedOverride = isSupportedOverride;

  bool get isSupported =>
      _isSupportedOverride ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows);

  bool get borderless => _borderless;
  bool get alwaysOnTop => _alwaysOnTop;
  bool get isMaximized => _isMaximized;

  Future<void> initialize({
    bool? borderlessOverride,
    bool? alwaysOnTopOverride,
  }) async {
    if (!isSupported) return;

    final savedBorderless =
        borderlessOverride ?? await UserPreferences.getBorderlessWindow();
    final savedAlwaysOnTop =
        alwaysOnTopOverride ?? await UserPreferences.getAlwaysOnTop();

    _borderless = savedBorderless;
    _alwaysOnTop = savedAlwaysOnTop;

    try {
      _isMaximized = await _channel.invokeMethod<bool>('isMaximized') ?? false;
    } on PlatformException catch (error) {
      debugPrint('Could not read desktop window mode: $error');
    } on MissingPluginException catch (error) {
      debugPrint('Desktop window bridge is unavailable: $error');
    }

    notifyListeners();
  }

  Future<void> applySavedWindowState() async {
    if (!isSupported) return;

    if (_borderless && !_nativeBorderlessApplied) {
      try {
        await _channel.invokeMethod<void>('setBorderless', true);
        _nativeBorderlessApplied = true;
      } on PlatformException catch (error) {
        debugPrint('Could not restore borderless window mode: $error');
        _borderless = false;
      } on MissingPluginException catch (error) {
        debugPrint('Desktop window bridge is unavailable: $error');
        _borderless = false;
      }
    }

    if (_alwaysOnTop && !_nativeAlwaysOnTopApplied) {
      try {
        await _channel.invokeMethod<void>('setAlwaysOnTop', true);
        _nativeAlwaysOnTopApplied = true;
      } on PlatformException catch (error) {
        debugPrint('Could not restore always-on-top mode: $error');
        _alwaysOnTop = false;
      } on MissingPluginException catch (error) {
        debugPrint('Desktop window bridge is unavailable: $error');
        _alwaysOnTop = false;
      }
    }

    notifyListeners();
  }

  Future<void> setBorderless(bool value) async {
    if (!isSupported || value == _borderless) return;
    await _channel.invokeMethod<void>('setBorderless', value);
    await UserPreferences.setBorderlessWindow(value);
    _borderless = value;
    _nativeBorderlessApplied = value;
    notifyListeners();
  }

  Future<void> setAlwaysOnTop(bool value) async {
    if (!isSupported || value == _alwaysOnTop) return;
    await _channel.invokeMethod<void>('setAlwaysOnTop', value);
    await UserPreferences.setAlwaysOnTop(value);
    _alwaysOnTop = value;
    _nativeAlwaysOnTopApplied = value;
    notifyListeners();
  }

  Future<void> restoreNormalWindow() async {
    if (!isSupported) return;

    if (_alwaysOnTop) {
      await setAlwaysOnTop(false);
    }
    if (_borderless) {
      await setBorderless(false);
    }
  }

  Future<void> startDragging() async {
    if (!isSupported || !_borderless) return;
    await _channel.invokeMethod<void>('startDrag');
  }

  Future<void> minimize() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('minimize');
  }

  Future<void> toggleMaximized() async {
    if (!isSupported) return;
    _isMaximized =
        await _channel.invokeMethod<bool>('toggleMaximized') ?? !_isMaximized;
    notifyListeners();
  }

  Future<void> close() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('close');
  }
}
