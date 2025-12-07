import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 48),
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.settings,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'Flick Settings',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Version 1.0.0',
              style: TextStyle(
                color: Colors.grey.shade500,
              ),
            ),
          ),
          const SizedBox(height: 48),
          const ListTile(
            title: Text('Flick Desktop Environment'),
            subtitle: Text('A mobile-first Linux desktop'),
          ),
          const Divider(),
          const ListTile(
            title: Text('Built with'),
            subtitle: Text('Flutter, Smithay, Wayland'),
          ),
          const Divider(),
          ListTile(
            title: const Text('License'),
            subtitle: const Text('MIT License'),
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: 'Flick Settings',
                applicationVersion: '1.0.0',
              );
            },
          ),
        ],
      ),
    );
  }
}
