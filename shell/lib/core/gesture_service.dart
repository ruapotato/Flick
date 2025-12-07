import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'logger.dart';

/// Edge of screen where gesture started
enum GestureEdge { left, right, top, bottom }

/// State of an ongoing gesture
enum GestureState { start, update, endComplete, endCancel }

/// Progressive gesture event with position/progress info
class GestureProgress {
  final GestureEdge edge;
  final GestureState state;
  final double progress;  // 0.0 to 1.0+
  final double velocity;  // pixels per second

  const GestureProgress({
    required this.edge,
    required this.state,
    required this.progress,
    required this.velocity,
  });

  bool get isStart => state == GestureState.start;
  bool get isUpdate => state == GestureState.update;
  bool get isEnd => state == GestureState.endComplete || state == GestureState.endCancel;
  bool get isCompleted => state == GestureState.endComplete;
  bool get isCancelled => state == GestureState.endCancel;

  @override
  String toString() => 'GestureProgress($edge, $state, progress: ${progress.toStringAsFixed(2)}, vel: ${velocity.toStringAsFixed(0)})';
}

/// Legacy action enum for backwards compatibility
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

  // Current gesture state (for animations)
  GestureProgress? _currentGesture;
  GestureProgress? get currentGesture => _currentGesture;

  final _progressController = StreamController<GestureProgress>.broadcast();
  final _actionController = StreamController<GestureAction>.broadcast();

  /// Stream of gesture progress events (for animations)
  Stream<GestureProgress> get progress => _progressController.stream;

  /// Stream of completed gesture actions (legacy)
  Stream<GestureAction> get gestures => _actionController.stream;

  GestureService._() {
    _startWatching();
  }

  void _startWatching() {
    final runtimeDir = Platform.environment['XDG_RUNTIME_DIR'] ?? '/run/user/1000';
    final gestureFile = File('$runtimeDir/flick-gesture');

    // Poll frequently for smooth animations
    _pollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _checkGestureFile(gestureFile);
    });

    log.info('GestureService started, watching: ${gestureFile.path}');
  }

  void _checkGestureFile(File file) {
    try {
      if (!file.existsSync()) return;

      final content = file.readAsStringSync().trim();
      if (content.isEmpty) return;

      // New format: timestamp|edge|state|progress|velocity
      final parts = content.split('|');
      if (parts.length == 5) {
        final timestamp = parts[0];
        if (timestamp == _lastTimestamp) return;
        _lastTimestamp = timestamp;

        final edge = _parseEdge(parts[1]);
        final state = _parseState(parts[2]);
        final progress = double.tryParse(parts[3]) ?? 0.0;
        final velocity = double.tryParse(parts[4]) ?? 0.0;

        if (edge != null && state != null) {
          final gestureProgress = GestureProgress(
            edge: edge,
            state: state,
            progress: progress,
            velocity: velocity,
          );

          _currentGesture = gestureProgress;
          _progressController.add(gestureProgress);
          notifyListeners();

          // Also emit legacy action on completion
          if (gestureProgress.isCompleted) {
            final action = _edgeToAction(edge);
            if (action != null) {
              log.info('Gesture completed: $action');
              _actionController.add(action);
            }
          }
        }
      }
      // Legacy format: timestamp:action (for backwards compat)
      else if (parts.length == 1 && content.contains(':')) {
        final legacyParts = content.split(':');
        if (legacyParts.length == 2) {
          final timestamp = legacyParts[0];
          if (timestamp == _lastTimestamp) return;
          _lastTimestamp = timestamp;

          final action = _parseAction(legacyParts[1]);
          if (action != null) {
            log.info('Legacy gesture received: $action');
            _actionController.add(action);
          }
        }
      }
    } catch (e) {
      // Ignore errors - file might be being written
    }
  }

  GestureEdge? _parseEdge(String edgeStr) {
    switch (edgeStr) {
      case 'left': return GestureEdge.left;
      case 'right': return GestureEdge.right;
      case 'top': return GestureEdge.top;
      case 'bottom': return GestureEdge.bottom;
      default: return null;
    }
  }

  GestureState? _parseState(String stateStr) {
    switch (stateStr) {
      case 'start': return GestureState.start;
      case 'update': return GestureState.update;
      case 'end_complete': return GestureState.endComplete;
      case 'end_cancel': return GestureState.endCancel;
      default: return null;
    }
  }

  GestureAction? _edgeToAction(GestureEdge edge) {
    switch (edge) {
      case GestureEdge.left: return GestureAction.back;
      case GestureEdge.right: return GestureAction.appSwitcher;
      case GestureEdge.top: return GestureAction.closeApp;
      case GestureEdge.bottom: return GestureAction.appDrawer;
    }
  }

  GestureAction? _parseAction(String actionStr) {
    switch (actionStr) {
      case 'back': return GestureAction.back;
      case 'app_switcher': return GestureAction.appSwitcher;
      case 'close_app': return GestureAction.closeApp;
      case 'app_drawer': return GestureAction.appDrawer;
      case 'quick_settings': return GestureAction.quickSettings;
      case 'home': return GestureAction.home;
      default: return null;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _progressController.close();
    _actionController.close();
    super.dispose();
  }
}
