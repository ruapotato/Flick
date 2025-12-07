import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/app_model.dart';
import '../../core/gesture_service.dart';
import '../../core/window_service.dart';
import '../../core/logger.dart';
import 'app_grid.dart';
import 'app_switcher.dart';

/// Main home screen of Flick shell with gesture-driven animations
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // Subscriptions
  StreamSubscription<GestureProgress>? _progressSubscription;

  // Animation controllers for smooth transitions
  late AnimationController _bottomSheetController;  // Swipe up - app drawer
  late AnimationController _closeAppController;     // Swipe down - close app
  late AnimationController _appSwitcherController;  // Swipe left - app switcher
  late AnimationController _backController;         // Swipe right - back

  // Track active gesture
  GestureEdge? _activeGesture;
  bool _gestureCompleted = false;

  // UI state
  bool _showAppSwitcher = false;
  bool _showAppDrawer = false;

  @override
  void initState() {
    super.initState();

    // Initialize services
    WindowService.instance;

    // Create animation controllers
    _bottomSheetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _closeAppController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _appSwitcherController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _backController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Listen to gesture progress for animations
    _progressSubscription = GestureService.instance.progress.listen(_handleGestureProgress);
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _bottomSheetController.dispose();
    _closeAppController.dispose();
    _appSwitcherController.dispose();
    _backController.dispose();
    super.dispose();
  }

  void _handleGestureProgress(GestureProgress gesture) {
    log.debug('Gesture: $gesture');

    if (gesture.isStart) {
      _activeGesture = gesture.edge;
      _gestureCompleted = false;
    }

    if (_activeGesture != gesture.edge) return;

    // Update the appropriate animation based on edge
    switch (gesture.edge) {
      case GestureEdge.bottom:
        // Swipe up - reveal app drawer
        if (gesture.isStart) {
          setState(() => _showAppDrawer = true);
        }
        if (gesture.isUpdate) {
          _bottomSheetController.value = gesture.progress.clamp(0.0, 1.0);
        } else if (gesture.isEnd) {
          if (gesture.isCompleted) {
            _bottomSheetController.animateTo(1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          } else {
            _bottomSheetController.animateTo(0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            ).then((_) {
              if (mounted) setState(() => _showAppDrawer = false);
            });
          }
          _activeGesture = null;
        }
        break;

      case GestureEdge.top:
        // Swipe down - close app animation
        if (gesture.isUpdate) {
          _closeAppController.value = gesture.progress.clamp(0.0, 1.0);
        } else if (gesture.isEnd) {
          _finishAnimation(_closeAppController, gesture.isCompleted, gesture.velocity, onComplete: () {
            // Reset after animation completes
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) {
                _closeAppController.value = 0;
              }
            });
          });
          _activeGesture = null;
        }
        break;

      case GestureEdge.right:
        // Swipe left - app switcher
        if (gesture.isStart) {
          setState(() => _showAppSwitcher = true);
        }
        if (gesture.isUpdate) {
          _appSwitcherController.value = gesture.progress.clamp(0.0, 1.0);
        } else if (gesture.isEnd) {
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
        // Swipe right - back gesture
        if (gesture.isUpdate) {
          _backController.value = gesture.progress.clamp(0.0, 1.0);
        } else if (gesture.isEnd) {
          _finishAnimation(_backController, gesture.isCompleted, gesture.velocity, onComplete: () {
            _backController.value = 0;
          });
          _activeGesture = null;
        }
        break;
    }
  }

  void _finishAnimation(AnimationController controller, bool complete, double velocity, {VoidCallback? onComplete}) {
    final target = complete ? 1.0 : 0.0;
    final distance = (target - controller.value).abs();

    // Calculate duration based on velocity
    var duration = const Duration(milliseconds: 200);
    if (velocity.abs() > 500) {
      duration = Duration(milliseconds: (distance * 150).toInt().clamp(50, 300));
    }

    controller.animateTo(
      target,
      duration: duration,
      curve: complete ? Curves.easeOut : Curves.easeOutCubic,
    ).then((_) => onComplete?.call());
  }

  /// Get XWayland display from compositor's runtime file
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

  void _closeAppDrawer() {
    _bottomSheetController.animateTo(0.0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    ).then((_) {
      if (mounted) setState(() => _showAppDrawer = false);
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
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Stack(
        children: [
          // Base layer - App Grid (always visible as background)
          _buildHomeContent(colorScheme),

          // Close app animation overlay (swipe down)
          AnimatedBuilder(
            animation: _closeAppController,
            builder: (context, child) {
              if (_closeAppController.value == 0) return const SizedBox.shrink();
              return Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.5 * _closeAppController.value),
                  child: Center(
                    child: Transform.translate(
                      offset: Offset(0, _closeAppController.value * 100),
                      child: Transform.scale(
                        scale: 1.0 - (_closeAppController.value * 0.3),
                        child: Opacity(
                          opacity: 1.0 - _closeAppController.value,
                          child: Icon(
                            Icons.close,
                            size: 80,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // Back gesture indicator (swipe right from left)
          AnimatedBuilder(
            animation: _backController,
            builder: (context, child) {
              if (_backController.value == 0) return const SizedBox.shrink();
              return Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 60 + (_backController.value * 40),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.3 * _backController.value),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Center(
                    child: Transform.translate(
                      offset: Offset(-20 + (_backController.value * 40), 0),
                      child: Icon(
                        Icons.arrow_back_ios,
                        size: 32,
                        color: Colors.white.withOpacity(_backController.value),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // App drawer overlay (swipe up from bottom)
          if (_showAppDrawer)
            AnimatedBuilder(
              animation: _bottomSheetController,
              builder: (context, child) {
                final slideOffset = screenHeight * (1 - _bottomSheetController.value);
                return Positioned.fill(
                  child: GestureDetector(
                    onTap: _closeAppDrawer,
                    onVerticalDragEnd: (details) {
                      if (details.velocity.pixelsPerSecond.dy > 300) {
                        _closeAppDrawer();
                      }
                    },
                    child: Stack(
                      children: [
                        // Dim background
                        Container(
                          color: Colors.black.withOpacity(0.5 * _bottomSheetController.value),
                        ),
                        // Sliding drawer
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: -screenHeight * 0.85 + (screenHeight * 0.85 * _bottomSheetController.value),
                          height: screenHeight * 0.85,
                          child: Container(
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(28),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 20,
                                  offset: const Offset(0, -5),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                // Drag handle
                                GestureDetector(
                                  onVerticalDragEnd: (details) {
                                    if (details.velocity.pixelsPerSecond.dy > 300) {
                                      _closeAppDrawer();
                                    }
                                  },
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
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
                                ),
                                // App drawer content
                                Expanded(
                                  child: AppDrawer(
                                    apps: MockApps.apps,
                                    onAppTap: (app) {
                                      _closeAppDrawer();
                                      _launchApp(app);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

          // App switcher overlay (swipe left from right)
          if (_showAppSwitcher)
            AnimatedBuilder(
              animation: _appSwitcherController,
              builder: (context, child) {
                return Positioned.fill(
                  child: GestureDetector(
                    onTap: _closeAppSwitcher,
                    child: Container(
                      color: Colors.black.withOpacity(0.85 * _appSwitcherController.value),
                      child: Transform.translate(
                        offset: Offset(screenWidth * (1 - _appSwitcherController.value), 0),
                        child: _buildAppSwitcherContent(colorScheme),
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

        // App grid
        Expanded(
          child: AppGrid(
            apps: MockApps.apps.take(8).toList(),
            onAppTap: _launchApp,
          ),
        ),

        // Dock hint
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

          // Hint
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Swipe to browse, tap to switch',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white54,
              ),
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
      controller: PageController(viewportFraction: 0.85),
      itemCount: windows.length,
      itemBuilder: (context, index) {
        final window = windows[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
          child: GestureDetector(
            onTap: () => _onWindowSelected(window.id),
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 20,
                    offset: const Offset(0, 10),
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
                          color: colorScheme.primary.withOpacity(0.7),
                        ),
                      ),
                    ),
                  ),
                  // App info
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          window.displayName,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          window.appClass,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
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
