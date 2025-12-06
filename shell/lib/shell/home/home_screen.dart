import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/app_model.dart';
import '../../core/logger.dart';
import 'app_grid.dart';

/// Main home screen of Flick shell
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _showDrawer = false;

  void _launchApp(AppInfo app) {
    log.info('Launching app: ${app.name} (${app.exec})');

    // Launch the app using shell to handle arguments properly
    Process.start(
      '/bin/sh',
      ['-c', app.exec],
      mode: ProcessStartMode.detached,
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
