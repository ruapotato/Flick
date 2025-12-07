import 'dart:convert';
import 'dart:io';
import 'package:bcrypt/bcrypt.dart';

enum LockMethod {
  none,
  pin,
  pattern,
  password,
}

class LockConfig {
  LockMethod method;
  String? pinHash;
  String? patternHash;
  int timeoutSeconds;

  LockConfig({
    this.method = LockMethod.none,
    this.pinHash,
    this.patternHash,
    this.timeoutSeconds = 300,
  });

  factory LockConfig.fromJson(Map<String, dynamic> json) {
    return LockConfig(
      method: _parseMethod(json['method'] as String?),
      pinHash: json['pin_hash'] as String?,
      patternHash: json['pattern_hash'] as String?,
      timeoutSeconds: json['timeout_seconds'] as int? ?? 300,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'method': _methodToString(method),
      'pin_hash': pinHash,
      'pattern_hash': patternHash,
      'timeout_seconds': timeoutSeconds,
    };
  }

  static LockMethod _parseMethod(String? method) {
    switch (method) {
      case 'pin':
        return LockMethod.pin;
      case 'pattern':
        return LockMethod.pattern;
      case 'password':
        return LockMethod.password;
      default:
        return LockMethod.none;
    }
  }

  static String _methodToString(LockMethod method) {
    switch (method) {
      case LockMethod.pin:
        return 'pin';
      case LockMethod.pattern:
        return 'pattern';
      case LockMethod.password:
        return 'password';
      case LockMethod.none:
        return 'none';
    }
  }
}

class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  LockConfig? _cachedConfig;

  String get _configPath {
    final home = Platform.environment['HOME'] ?? '/home';
    return '$home/.local/state/flick/lock_config.json';
  }

  Future<LockConfig> loadConfig() async {
    try {
      final file = File(_configPath);
      if (await file.exists()) {
        final contents = await file.readAsString();
        final json = jsonDecode(contents) as Map<String, dynamic>;
        _cachedConfig = LockConfig.fromJson(json);
        return _cachedConfig!;
      }
    } catch (e) {
      // Config doesn't exist or is invalid, return default
    }
    _cachedConfig = LockConfig();
    return _cachedConfig!;
  }

  Future<void> saveConfig(LockConfig config) async {
    final file = File(_configPath);

    // Ensure directory exists
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final json = jsonEncode(config.toJson());
    await file.writeAsString(json);
    _cachedConfig = config;
  }

  String hashPin(String pin) {
    return BCrypt.hashpw(pin, BCrypt.gensalt());
  }

  String hashPattern(List<int> pattern) {
    // Convert pattern to string like "0,1,2,5,8"
    final patternStr = pattern.join(',');
    return BCrypt.hashpw(patternStr, BCrypt.gensalt());
  }

  bool verifyPin(String pin, String hash) {
    return BCrypt.checkpw(pin, hash);
  }

  bool verifyPattern(List<int> pattern, String hash) {
    final patternStr = pattern.join(',');
    return BCrypt.checkpw(patternStr, hash);
  }

  LockConfig? get cachedConfig => _cachedConfig;
}
