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
      id: 'org.flick.files',
      name: 'Files',
      icon: Icons.folder,
      exec: 'flick-files',
      categories: ['System', 'FileManager'],
    ),
    AppInfo(
      id: 'org.flick.settings',
      name: 'Settings',
      icon: Icons.settings,
      exec: 'flick-settings',
      categories: ['System', 'Settings'],
    ),
    AppInfo(
      id: 'org.flick.terminal',
      name: 'Terminal',
      icon: Icons.terminal,
      exec: 'flick-terminal',
      categories: ['System', 'TerminalEmulator'],
    ),
    AppInfo(
      id: 'org.gnome.Calculator',
      name: 'Calculator',
      icon: Icons.calculate,
      exec: 'gnome-calculator',
      categories: ['Utility', 'Calculator'],
    ),
    AppInfo(
      id: 'org.gnome.Calendar',
      name: 'Calendar',
      icon: Icons.calendar_month,
      exec: 'gnome-calendar',
      categories: ['Office', 'Calendar'],
    ),
    AppInfo(
      id: 'org.gnome.clocks',
      name: 'Clock',
      icon: Icons.access_time,
      exec: 'gnome-clocks',
      categories: ['Utility', 'Clock'],
    ),
    AppInfo(
      id: 'org.example.browser',
      name: 'Browser',
      icon: Icons.public,
      exec: 'firefox',
      categories: ['Network', 'WebBrowser'],
    ),
    AppInfo(
      id: 'org.example.gallery',
      name: 'Gallery',
      icon: Icons.photo_library,
      exec: 'eog',
      categories: ['Graphics', 'Viewer'],
    ),
    AppInfo(
      id: 'org.example.camera',
      name: 'Camera',
      icon: Icons.camera_alt,
      exec: 'cheese',
      categories: ['Graphics', 'Photography'],
    ),
    AppInfo(
      id: 'org.example.music',
      name: 'Music',
      icon: Icons.library_music,
      exec: 'rhythmbox',
      categories: ['Audio', 'Music'],
    ),
    AppInfo(
      id: 'org.example.videos',
      name: 'Videos',
      icon: Icons.video_library,
      exec: 'totem',
      categories: ['Video', 'Player'],
    ),
    AppInfo(
      id: 'org.example.notes',
      name: 'Notes',
      icon: Icons.note,
      exec: 'gedit',
      categories: ['Utility', 'TextEditor'],
    ),
  ];
}
