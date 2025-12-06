import 'package:flutter/material.dart';

/// Represents an application that can be launched
class AppInfo {
  final String id;
  final String name;
  final String? genericName;
  final String? comment;
  final IconData icon;
  final String? iconPath;
  final String exec;
  final List<String> categories;
  final bool isWaydroid;

  const AppInfo({
    required this.id,
    required this.name,
    this.genericName,
    this.comment,
    this.icon = Icons.apps,
    this.iconPath,
    required this.exec,
    this.categories = const [],
    this.isWaydroid = false,
  });

  /// Get display name (prefer generic name for clarity)
  String get displayName => genericName ?? name;
}

/// Mock app data for development - will be replaced by D-Bus service
class MockApps {
  static const List<AppInfo> apps = [
    AppInfo(
      id: 'org.codeberg.dnkl.foot',
      name: 'Terminal',
      icon: Icons.terminal,
      exec: 'foot',
      categories: ['System', 'TerminalEmulator'],
    ),
    AppInfo(
      id: 'org.mozilla.firefox',
      name: 'Firefox',
      icon: Icons.public,
      exec: 'firefox',
      categories: ['Network', 'WebBrowser'],
    ),
    AppInfo(
      id: 'org.chromium.Chromium',
      name: 'Chromium',
      icon: Icons.language,
      exec: 'chromium',
      categories: ['Network', 'WebBrowser'],
    ),
    AppInfo(
      id: 'org.kde.kate',
      name: 'Kate',
      genericName: 'Text Editor',
      icon: Icons.edit_note,
      exec: 'kate',
      categories: ['Utility', 'TextEditor'],
    ),
    AppInfo(
      id: 'xterm',
      name: 'XTerm',
      icon: Icons.terminal,
      exec: 'xterm',
      categories: ['System', 'TerminalEmulator'],
    ),
  ];
}
