import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'logger.dart';

/// Gesture actions from compositor
enum GestureAction {
  back,
  appSwitcher,
  closeApp,
  appDrawer,
  quickSettings,
  home,
}

/// Service to receive gesture events from the compositor
class GestureService extends ChangeNotifier {
  static GestureService? _instance;
  static GestureService get instance => _instance ??= GestureService._();

  Timer? _pollTimer;
  String? _lastTimestamp;
  final _gestureController = StreamController<GestureAction>.broadcast();

  /// Stream of gesture events
  Stream<GestureAction> get gestures => _gestureController.stream;

  GestureService._() {
    _startWatching();
  }

  void _startWatching() {
    final runtimeDir = Platform.environment['XDG_RUNTIME_DIR'] ?? '/run/user/1000';
    final gestureFile = File('$runtimeDir/flick-gesture');

    // Poll the file for changes (more reliable than inotify with layer-shell)
    _pollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _checkGestureFile(gestureFile);
    });

    log.info('GestureService started, watching: ${gestureFile.path}');
  }

  void _checkGestureFile(File file) {
    try {
      if (!file.existsSync()) return;

      final content = file.readAsStringSync().trim();
      if (content.isEmpty) return;

      // Format: timestamp:action
      final parts = content.split(':');
      if (parts.length != 2) return;

      final timestamp = parts[0];
      final actionStr = parts[1];

      // Only process if this is a new event
      if (timestamp == _lastTimestamp) return;
      _lastTimestamp = timestamp;

      final action = _parseAction(actionStr);
      if (action != null) {
        log.info('Gesture received: $action');
        _gestureController.add(action);
        notifyListeners();
      }
    } catch (e) {
      // Ignore errors - file might be being written
    }
  }

  GestureAction? _parseAction(String actionStr) {
    switch (actionStr) {
      case 'back':
        return GestureAction.back;
      case 'app_switcher':
        return GestureAction.appSwitcher;
      case 'close_app':
        return GestureAction.closeApp;
      case 'app_drawer':
        return GestureAction.appDrawer;
      case 'quick_settings':
        return GestureAction.quickSettings;
      case 'home':
        return GestureAction.home;
      default:
        log.warn('Unknown gesture action: $actionStr');
        return null;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _gestureController.close();
    super.dispose();
  }
}
