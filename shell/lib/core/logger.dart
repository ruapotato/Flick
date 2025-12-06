import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';

/// Flick logging system with file persistence and crash recording
class FlickLogger {
  static FlickLogger? _instance;
  static FlickLogger get instance => _instance ??= FlickLogger._();

  late final File _logFile;
  late final File _crashFile;
  late final IOSink _logSink;
  final List<String> _recentLogs = [];
  static const int _maxRecentLogs = 100;

  FlickLogger._();

  /// Initialize the logger - call once at app startup
  Future<void> init() async {
    final logDir = Directory('${Platform.environment['HOME']}/.local/share/flick/logs');
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    _logFile = File('${logDir.path}/flick-$timestamp.log');
    _crashFile = File('${logDir.path}/crash.log');
    _logSink = _logFile.openWrite(mode: FileMode.append);

    // Log startup
    info('Flick shell starting');
    info('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    info('Dart: ${Platform.version}');

    // Set up Flutter error handling
    FlutterError.onError = (details) {
      error('Flutter error: ${details.exception}');
      error('Stack trace:\n${details.stack}');
      _writeCrashLog(details.exception.toString(), details.stack);
    };

    // Handle async errors
    PlatformDispatcher.instance.onError = (error, stack) {
      this.error('Unhandled error: $error');
      this.error('Stack trace:\n$stack');
      _writeCrashLog(error.toString(), stack);
      return true;
    };
  }

  void _log(String level, String message) {
    final timestamp = DateTime.now().toIso8601String();
    final line = '[$timestamp] [$level] $message';

    // Console output in debug mode
    if (kDebugMode) {
      debugPrint(line);
    }

    // File output
    _logSink.writeln(line);

    // Keep recent logs in memory for quick access
    _recentLogs.add(line);
    if (_recentLogs.length > _maxRecentLogs) {
      _recentLogs.removeAt(0);
    }
  }

  void debug(String message) => _log('DEBUG', message);
  void info(String message) => _log('INFO', message);
  void warn(String message) => _log('WARN', message);
  void error(String message) => _log('ERROR', message);

  Future<void> _writeCrashLog(String error, StackTrace? stack) async {
    final timestamp = DateTime.now().toIso8601String();
    final crashReport = StringBuffer();

    crashReport.writeln('=== FLICK CRASH REPORT ===');
    crashReport.writeln('Time: $timestamp');
    crashReport.writeln('Error: $error');
    crashReport.writeln('');
    crashReport.writeln('Stack Trace:');
    crashReport.writeln(stack?.toString() ?? 'No stack trace available');
    crashReport.writeln('');
    crashReport.writeln('Recent Logs:');
    for (final log in _recentLogs) {
      crashReport.writeln(log);
    }
    crashReport.writeln('=== END CRASH REPORT ===\n');

    await _crashFile.writeAsString(
      crashReport.toString(),
      mode: FileMode.append,
    );

    // Also flush the main log
    await _logSink.flush();
  }

  /// Get path to current log file
  String get logPath => _logFile.path;

  /// Get path to crash log file
  String get crashLogPath => _crashFile.path;

  /// Get recent logs from memory
  List<String> get recentLogs => List.unmodifiable(_recentLogs);

  /// Flush logs to disk
  Future<void> flush() => _logSink.flush();

  /// Clean up
  Future<void> dispose() async {
    info('Flick shell shutting down');
    await _logSink.flush();
    await _logSink.close();
  }
}

/// Convenience function for logging
FlickLogger get log => FlickLogger.instance;
