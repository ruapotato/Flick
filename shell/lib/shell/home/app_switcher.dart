import 'package:flutter/material.dart';
import '../../core/window_service.dart';
import '../../core/logger.dart';

/// App switcher overlay showing running applications
class AppSwitcher extends StatelessWidget {
  final List<WindowInfo> windows;
  final VoidCallback onClose;
  final Function(int windowId) onWindowSelected;

  const AppSwitcher({
    super.key,
    required this.windows,
    required this.onClose,
    required this.onWindowSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.black87,
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Running Apps',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),

              // Window cards
              Expanded(
                child: windows.isEmpty
                    ? _buildEmptyState(context)
                    : _buildWindowGrid(context, colorScheme),
              ),

              // Hint text
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Tap to switch, tap outside to close',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white54,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.apps_outage,
            size: 64,
            color: Colors.white30,
          ),
          const SizedBox(height: 16),
          Text(
            'No running apps',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Launch an app from the home screen',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWindowGrid(BuildContext context, ColorScheme colorScheme) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
      ),
      itemCount: windows.length,
      itemBuilder: (context, index) {
        return _WindowCard(
          window: windows[index],
          onTap: () => onWindowSelected(windows[index].id),
          colorScheme: colorScheme,
        );
      },
    );
  }
}

class _WindowCard extends StatelessWidget {
  final WindowInfo window;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  const _WindowCard({
    required this.window,
    required this.onTap,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outline.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            // Window preview placeholder
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: Center(
                  child: Icon(
                    _getAppIcon(window.appClass),
                    size: 48,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ),
            // Window title
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    window.displayName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    window.appClass,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
    if (className.contains('video') || className.contains('mpv') || className.contains('vlc')) {
      return Icons.play_circle;
    }
    if (className.contains('music') || className.contains('audio')) return Icons.music_note;
    if (className.contains('image') || className.contains('photo')) return Icons.image;
    return Icons.apps;
  }
}
