import 'package:flutter/material.dart';
import '../../core/app_model.dart';
import '../../core/logger.dart';

/// Grid of application icons for the home screen
class AppGrid extends StatelessWidget {
  final List<AppInfo> apps;
  final void Function(AppInfo app)? onAppTap;
  final int crossAxisCount;

  const AppGrid({
    super.key,
    required this.apps,
    this.onAppTap,
    this.crossAxisCount = 4,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: apps.length,
      itemBuilder: (context, index) {
        final app = apps[index];
        return AppGridItem(
          app: app,
          onTap: () => onAppTap?.call(app),
        );
      },
    );
  }
}

/// Individual app icon in the grid
class AppGridItem extends StatelessWidget {
  final AppInfo app;
  final VoidCallback? onTap;

  const AppGridItem({
    super.key,
    required this.app,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              app.icon,
              size: 28,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            app.displayName,
            style: Theme.of(context).textTheme.labelMedium,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// App drawer - full list of apps with search
class AppDrawer extends StatefulWidget {
  final List<AppInfo> apps;
  final void Function(AppInfo app)? onAppTap;

  const AppDrawer({
    super.key,
    required this.apps,
    this.onAppTap,
  });

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  List<AppInfo> get _filteredApps {
    if (_searchQuery.isEmpty) return widget.apps;
    final query = _searchQuery.toLowerCase();
    return widget.apps.where((app) {
      return app.name.toLowerCase().contains(query) ||
          (app.genericName?.toLowerCase().contains(query) ?? false) ||
          (app.comment?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search apps...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _filteredApps.length,
            itemBuilder: (context, index) {
              final app = _filteredApps[index];
              return ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    app.icon,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                title: Text(app.displayName),
                subtitle: app.comment != null ? Text(app.comment!) : null,
                onTap: () => widget.onAppTap?.call(app),
              );
            },
          ),
        ),
      ],
    );
  }
}
