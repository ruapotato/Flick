import 'package:flutter/material.dart';
import 'lock_screen_settings.dart';
import 'about_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          _SettingsSection(
            title: 'Security',
            children: [
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Lock Screen'),
                subtitle: const Text('PIN, pattern, or password'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LockScreenSettings(),
                    ),
                  );
                },
              ),
            ],
          ),
          _SettingsSection(
            title: 'Display',
            children: [
              ListTile(
                leading: const Icon(Icons.brightness_6),
                title: const Text('Brightness'),
                subtitle: const Text('Coming soon'),
                enabled: false,
              ),
              ListTile(
                leading: const Icon(Icons.wallpaper),
                title: const Text('Wallpaper'),
                subtitle: const Text('Coming soon'),
                enabled: false,
              ),
            ],
          ),
          _SettingsSection(
            title: 'System',
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('About'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AboutScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
        ...children,
        const Divider(),
      ],
    );
  }
}
