import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'logger.dart';

/// Represents an open window/app from the compositor
class WindowInfo {
  final int id;
  final String title;
  final String appClass;

  const WindowInfo({
    required this.id,
    required this.title,
    required this.appClass,
  });

  /// Get a display-friendly name
  String get displayName {
    // Use class name if title is generic or empty
    if (title.isEmpty || title == 'Unknown') {
      return _formatClass(appClass);
    }
    return title;
  }

  /// Format class name for display (e.g., "firefox" -> "Firefox")
  String _formatClass(String className) {
    if (className.isEmpty) return 'Unknown';
    // Capitalize first letter
    return className[0].toUpperCase() + className.substring(1);
  }

  @override
  String toString() => 'WindowInfo($id: $title [$appClass])';
}

/// Service to get list of open windows from compositor
class WindowService extends ChangeNotifier {
  static WindowService? _instance;
  static WindowService get instance => _instance ??= WindowService._();

  Timer? _pollTimer;
  String? _lastTimestamp;
  List<WindowInfo> _windows = [];

  /// Current list of open windows
  List<WindowInfo> get windows => List.unmodifiable(_windows);

  WindowService._() {
    _startWatching();
  }

  void _startWatching() {
    final runtimeDir = Platform.environment['XDG_RUNTIME_DIR'] ?? '/run/user/1000';
    final windowFile = File('$runtimeDir/flick-windows');

    // Poll the file for changes
    _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _checkWindowFile(windowFile);
    });

    log.info('WindowService started, watching: ${windowFile.path}');
  }

  void _checkWindowFile(File file) {
    try {
      if (!file.existsSync()) return;

      final content = file.readAsStringSync().trim();
      if (content.isEmpty) return;

      final lines = content.split('\n');
      if (lines.isEmpty) return;

      final timestamp = lines[0];

      // Only process if this is a new update
      if (timestamp == _lastTimestamp) return;
      _lastTimestamp = timestamp;

      // Parse window list
      final newWindows = <WindowInfo>[];
      for (var i = 1; i < lines.length; i++) {
        final parts = lines[i].split('|');
        if (parts.length >= 3) {
          final id = int.tryParse(parts[0]);
          if (id != null) {
            newWindows.add(WindowInfo(
              id: id,
              title: parts[1],
              appClass: parts[2],
            ));
          }
        }
      }

      // Update if changed
      if (!_listEquals(_windows, newWindows)) {
        _windows = newWindows;
        log.debug('Window list updated: ${_windows.length} windows');
        notifyListeners();
      }
    } catch (e) {
      // Ignore errors - file might be being written
    }
  }

  bool _listEquals(List<WindowInfo> a, List<WindowInfo> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].title != b[i].title) return false;
    }
    return true;
  }

  /// Request the compositor to focus a specific window
  void focusWindow(int windowId) {
    final runtimeDir = Platform.environment['XDG_RUNTIME_DIR'] ?? '/run/user/1000';
    final focusFile = File('$runtimeDir/flick-focus');

    try {
      focusFile.writeAsStringSync(windowId.toString());
      log.info('Requested focus for window: $windowId');
    } catch (e) {
      log.error('Failed to request window focus: $e');
    }
  }

  /// Force refresh the window list
  void refresh() {
    _lastTimestamp = null;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
