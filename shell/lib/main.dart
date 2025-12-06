import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/logger.dart';
import 'shell/home/home_screen.dart';
import 'theme/flick_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize logging
  await FlickLogger.instance.init();
  log.info('Log file: ${log.logPath}');

  // Run the shell
  runApp(const FlickShell());
}

class FlickShell extends StatelessWidget {
  const FlickShell({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flick',
      debugShowCheckedModeBanner: false,
      theme: FlickTheme.light,
      darkTheme: FlickTheme.dark,
      themeMode: ThemeMode.system,
      home: const FlickShellScaffold(),
    );
  }
}

/// Root scaffold that handles global keyboard events (XF86Back, etc)
class FlickShellScaffold extends StatefulWidget {
  const FlickShellScaffold({super.key});

  @override
  State<FlickShellScaffold> createState() => _FlickShellScaffoldState();
}

class _FlickShellScaffoldState extends State<FlickShellScaffold> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    log.info('Flick shell UI initialized');
  }

  @override
  void dispose() {
    _focusNode.dispose();
    FlickLogger.instance.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      // Handle XF86Back - browser back key sent by lisgd
      if (event.logicalKey == LogicalKeyboardKey.browserBack) {
        log.debug('XF86Back pressed');
        _handleBack();
        return KeyEventResult.handled;
      }

      // Handle XF86Forward
      if (event.logicalKey == LogicalKeyboardKey.browserForward) {
        log.debug('XF86Forward pressed');
        // Could be used for forward navigation in apps
        return KeyEventResult.handled;
      }

      // Escape key for development (acts like back)
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        log.debug('Escape pressed (dev back)');
        _handleBack();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _handleBack() {
    // In the shell, back does nothing (we're already home)
    // In real apps, this would navigate back or close drawers
    log.debug('Back action - already at home');
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: const HomeScreen(),
    );
  }
}
