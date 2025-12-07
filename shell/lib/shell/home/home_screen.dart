import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/app_model.dart';
import '../../core/gesture_service.dart';
import '../../core/window_service.dart';
import '../../core/logger.dart';
import 'app_grid.dart';
import 'app_switcher.dart';

/// Main home screen of Flick shell
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _showDrawer = false;
  bool _showAppSwitcher = false;
  StreamSubscription<GestureAction>? _gestureSubscription;

  @override
  void initState() {
    super.initState();
    _gestureSubscription = GestureService.instance.gestures.listen(_handleGesture);
    // Initialize window service
    WindowService.instance;
  }

  @override
  void dispose() {
    _gestureSubscription?.cancel();
    super.dispose();
  }

  void _handleGesture(GestureAction action) {
    log.info('Handling gesture: $action');
    switch (action) {
      case GestureAction.appDrawer:
        // Swipe up from bottom - compositor brings home to front
        // Close overlays if open
        if (_showDrawer || _showAppSwitcher) {
          setState(() {
            _showDrawer = false;
            _showAppSwitcher = false;
          });
        }
        break;
      case GestureAction.back:
        // Swipe from left edge - go back / close overlays
        if (_showDrawer || _showAppSwitcher) {
          setState(() {
            _showDrawer = false;
            _showAppSwitcher = false;
          });
        }
        // TODO: Send back event to focused app via compositor
        break;
      case GestureAction.closeApp:
        // Swipe down from top - compositor closes the app
        // Nothing for shell to do, compositor handles it
        break;
      case GestureAction.appSwitcher:
        // Swipe from right edge - show app switcher
        log.info('App switcher requested');
        setState(() {
          _showAppSwitcher = true;
          _showDrawer = false;
        });
        break;
      case GestureAction.home:
        // Go home - close overlays if open
        if (_showDrawer || _showAppSwitcher) {
          setState(() {
            _showDrawer = false;
            _showAppSwitcher = false;
          });
        }
        break;
      case GestureAction.quickSettings:
        log.info('Quick settings requested');
        // TODO: Show quick settings panel
        break;
    }
  }

  /// Get XWayland display from compositor's runtime file
  String _getXWaylandDisplay() {
    final runtimeDir = Platform.environment['XDG_RUNTIME_DIR'] ?? '/run/user/1000';
    final displayFile = File('$runtimeDir/flick-xwayland-display');
    try {
      if (displayFile.existsSync()) {
        final display = displayFile.readAsStringSync().trim();
        log.info('Read XWayland display from file: $display');
        return display;
      }
    } catch (e) {
      log.warn('Failed to read XWayland display file: $e');
    }
    // Fallback to :1 if file doesn't exist
    log.warn('XWayland display file not found, falling back to :1');
    return ':1';
  }

  void _launchApp(AppInfo app) {
    log.info('Launching app: ${app.name} (${app.exec})');

    // Get XWayland display from compositor
    final xwaylandDisplay = _getXWaylandDisplay();

    // Build environment with DISPLAY for X11 apps
    final env = Map<String, String>.from(Platform.environment);
    env['DISPLAY'] = xwaylandDisplay;

    // Prepend DISPLAY to command to ensure it's set (detached mode can lose env vars)
    final cmd = 'export DISPLAY=$xwaylandDisplay; ${app.exec}';
    log.info('Launching with command: $cmd');

    // Launch the app using shell to handle arguments properly
    Process.start(
      '/bin/sh',
      ['-c', cmd],
      mode: ProcessStartMode.detached,
      environment: env,
    ).then((_) {
      log.debug('App ${app.name} started');
    }).catchError((e) {
      log.error('Failed to launch ${app.name}: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to launch ${app.name}')),
        );
      }
    });
  }

  void _toggleDrawer() {
    setState(() => _showDrawer = !_showDrawer);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: Stack(
        children: [
          // Main content - app grid
          Column(
            children: [
              // Status bar area (reserved space)
              Container(
                height: MediaQuery.of(context).padding.top + 24,
                color: colorScheme.surface,
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Clock placeholder
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          _formatTime(),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // App grid
              Expanded(
                child: GestureDetector(
                  onVerticalDragEnd: (details) {
                    // Swipe up to open drawer
                    if (details.velocity.pixelsPerSecond.dy < -300) {
                      _toggleDrawer();
                    }
                  },
                  child: AppGrid(
                    apps: MockApps.apps.take(8).toList(),
                    onAppTap: _launchApp,
                  ),
                ),
              ),

              // Dock area with hint
              Container(
                height: 60,
                color: colorScheme.surface,
                child: Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: colorScheme.outline.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // App drawer overlay
          if (_showDrawer)
            GestureDetector(
              onVerticalDragEnd: (details) {
                // Swipe down to close drawer
                if (details.velocity.pixelsPerSecond.dy > 300) {
                  _toggleDrawer();
                }
              },
              onTap: _toggleDrawer,
              child: Container(
                color: Colors.black54,
              ),
            ),

          // App drawer
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            left: 0,
            right: 0,
            bottom: _showDrawer ? 0 : -screenHeight * 0.85,
            height: screenHeight * 0.85,
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Column(
                children: [
                  // Drag handle
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: colorScheme.outline.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  // App drawer content
                  Expanded(
                    child: AppDrawer(
                      apps: MockApps.apps,
                      onAppTap: (app) {
                        _toggleDrawer();
                        _launchApp(app);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // App switcher overlay
          if (_showAppSwitcher)
            ListenableBuilder(
              listenable: WindowService.instance,
              builder: (context, child) {
                return AppSwitcher(
                  windows: WindowService.instance.windows,
                  onClose: () {
                    setState(() => _showAppSwitcher = false);
                  },
                  onWindowSelected: (windowId) {
                    log.info('Switching to window: $windowId');
                    WindowService.instance.focusWindow(windowId);
                    setState(() => _showAppSwitcher = false);
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  String _formatTime() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
