import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/app_model.dart';
import '../../core/gesture_service.dart';
import '../../core/window_service.dart';
import '../../core/logger.dart';
import 'app_grid.dart';

/// Main home screen - the app grid IS the home screen
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  StreamSubscription<GestureProgress>? _progressSubscription;

  // Animation controllers
  late AnimationController _appSwitcherController;
  late AnimationController _backController;

  // Track active gesture
  GestureEdge? _activeGesture;

  // UI state
  bool _showAppSwitcher = false;

  @override
  void initState() {
    super.initState();
    WindowService.instance;

    _appSwitcherController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _backController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _progressSubscription = GestureService.instance.progress.listen(_handleGestureProgress);
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _appSwitcherController.dispose();
    _backController.dispose();
    super.dispose();
  }

  void _handleGestureProgress(GestureProgress gesture) {
    log.info('Gesture: $gesture');

    if (gesture.isStart) {
      _activeGesture = gesture.edge;
    }

    if (_activeGesture != gesture.edge) return;

    switch (gesture.edge) {
      case GestureEdge.bottom:
        // Swipe up - compositor brings shell to front, nothing for us to do
        if (gesture.isEnd) {
          _activeGesture = null;
        }
        break;

      case GestureEdge.top:
        // Swipe down - compositor closes app, nothing for shell to do
        if (gesture.isEnd) {
          _activeGesture = null;
        }
        break;

      case GestureEdge.right:
        // Swipe left from right edge - app switcher
        if (gesture.isStart) {
          log.info('App switcher starting');
          setState(() => _showAppSwitcher = true);
        }
        if (gesture.isUpdate) {
          _appSwitcherController.value = gesture.progress.clamp(0.0, 1.0);
        } else if (gesture.isEnd) {
          log.info('App switcher ending, completed: ${gesture.isCompleted}');
          if (gesture.isCompleted) {
            _appSwitcherController.animateTo(1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          } else {
            _appSwitcherController.animateTo(0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            ).then((_) {
              if (mounted) setState(() => _showAppSwitcher = false);
            });
          }
          _activeGesture = null;
        }
        break;

      case GestureEdge.left:
        // Swipe right from left edge - back gesture
        if (gesture.isUpdate) {
          _backController.value = gesture.progress.clamp(0.0, 1.0);
        } else if (gesture.isEnd) {
          _backController.animateTo(0.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
          _activeGesture = null;
        }
        break;
    }
  }

  String _getXWaylandDisplay() {
    final runtimeDir = Platform.environment['XDG_RUNTIME_DIR'] ?? '/run/user/1000';
    final displayFile = File('$runtimeDir/flick-xwayland-display');
    try {
      if (displayFile.existsSync()) {
        return displayFile.readAsStringSync().trim();
      }
    } catch (e) {
      log.warn('Failed to read XWayland display file: $e');
    }
    return ':1';
  }

  void _launchApp(AppInfo app) {
    log.info('Launching app: ${app.name} (${app.exec})');

    final xwaylandDisplay = _getXWaylandDisplay();
    final env = Map<String, String>.from(Platform.environment);
    env['DISPLAY'] = xwaylandDisplay;

    final cmd = 'export DISPLAY=$xwaylandDisplay; ${app.exec}';

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

  void _closeAppSwitcher() {
    _appSwitcherController.animateTo(0.0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    ).then((_) {
      if (mounted) setState(() => _showAppSwitcher = false);
    });
  }

  void _onWindowSelected(int windowId) {
    log.info('Switching to window: $windowId');
    WindowService.instance.focusWindow(windowId);
    _closeAppSwitcher();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Stack(
        children: [
          // Home screen - THE app grid
          _buildHomeContent(colorScheme),

          // Back gesture indicator (swipe right from left edge)
          AnimatedBuilder(
            animation: _backController,
            builder: (context, child) {
              if (_backController.value == 0) return const SizedBox.shrink();
              return Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 80 * _backController.value + 20,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.4 * _backController.value),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(left: 8 + (20 * _backController.value)),
                      child: Icon(
                        Icons.arrow_back_ios,
                        size: 28,
                        color: Colors.white.withOpacity(_backController.value.clamp(0.0, 1.0)),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // App switcher overlay (swipe left from right edge)
          if (_showAppSwitcher)
            AnimatedBuilder(
              animation: _appSwitcherController,
              builder: (context, child) {
                return Positioned.fill(
                  child: GestureDetector(
                    onTap: _closeAppSwitcher,
                    child: Container(
                      color: Colors.black.withOpacity(0.9 * _appSwitcherController.value),
                      child: Transform.translate(
                        offset: Offset(screenWidth * (1 - _appSwitcherController.value), 0),
                        child: Opacity(
                          opacity: _appSwitcherController.value,
                          child: _buildAppSwitcherContent(colorScheme),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildHomeContent(ColorScheme colorScheme) {
    return Column(
      children: [
        // Status bar
        Container(
          height: MediaQuery.of(context).padding.top + 24,
          color: colorScheme.surface,
          child: SafeArea(
            bottom: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: StreamBuilder(
                    stream: Stream.periodic(const Duration(seconds: 1)),
                    builder: (context, snapshot) {
                      return Text(
                        _formatTime(),
                        style: Theme.of(context).textTheme.bodyMedium,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // App grid - ALL apps
        Expanded(
          child: AppGrid(
            apps: MockApps.apps,
            onAppTap: _launchApp,
          ),
        ),

        // Home indicator
        Container(
          height: 40,
          color: colorScheme.surface,
          child: Center(
            child: Container(
              width: 134,
              height: 5,
              decoration: BoxDecoration(
                color: colorScheme.outline.withOpacity(0.5),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppSwitcherContent(ColorScheme colorScheme) {
    return SafeArea(
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Apps',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: _closeAppSwitcher,
                ),
              ],
            ),
          ),

          // Horizontal scrolling app cards
          Expanded(
            child: ListenableBuilder(
              listenable: WindowService.instance,
              builder: (context, child) {
                final windows = WindowService.instance.windows;
                if (windows.isEmpty) {
                  return _buildEmptyAppSwitcher();
                }
                return _buildHorizontalAppList(windows, colorScheme);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyAppSwitcher() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.apps_outage, size: 64, color: Colors.white30),
          const SizedBox(height: 16),
          Text(
            'No running apps',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalAppList(List<WindowInfo> windows, ColorScheme colorScheme) {
    return PageView.builder(
      controller: PageController(viewportFraction: 0.8),
      itemCount: windows.length,
      itemBuilder: (context, index) {
        final window = windows[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 40),
          child: GestureDetector(
            onTap: () => _onWindowSelected(window.id),
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // App preview area
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          _getAppIcon(window.appClass),
                          size: 80,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  // App info
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      window.displayName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _getAppIcon(String appClass) {
    final className = appClass.toLowerCase();
    if (className.contains('firefox')) return Icons.public;
    if (className.contains('chrom')) return Icons.language;
    if (className.contains('term') || className.contains('foot') || className.contains('xterm')) {
      return Icons.terminal;
    }
    if (className.contains('kate') || className.contains('edit')) return Icons.edit_note;
    if (className.contains('file')) return Icons.folder;
    return Icons.apps;
  }

  String _formatTime() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
