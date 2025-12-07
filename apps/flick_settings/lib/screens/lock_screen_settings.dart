import 'package:flutter/material.dart';
import '../services/config_service.dart';
import '../widgets/pin_setup_dialog.dart';
import '../widgets/pattern_setup_widget.dart';

class LockScreenSettings extends StatefulWidget {
  const LockScreenSettings({super.key});

  @override
  State<LockScreenSettings> createState() => _LockScreenSettingsState();
}

class _LockScreenSettingsState extends State<LockScreenSettings> {
  final ConfigService _configService = ConfigService();
  LockConfig? _config;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await _configService.loadConfig();
    setState(() {
      _config = config;
      _loading = false;
    });
  }

  Future<void> _saveConfig() async {
    if (_config != null) {
      await _configService.saveConfig(_config!);
    }
  }

  String _methodLabel(LockMethod method) {
    switch (method) {
      case LockMethod.none:
        return 'None';
      case LockMethod.pin:
        return 'PIN';
      case LockMethod.pattern:
        return 'Pattern';
      case LockMethod.password:
        return 'Password';
    }
  }

  String _timeoutLabel(int seconds) {
    if (seconds == 0) return 'Immediately';
    if (seconds == 60) return '1 minute';
    if (seconds == 300) return '5 minutes';
    if (seconds == 900) return '15 minutes';
    if (seconds < 0) return 'Never';
    return '$seconds seconds';
  }

  Future<void> _showMethodPicker() async {
    final result = await showModalBottomSheet<LockMethod>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Choose Lock Method',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.lock_open),
              title: const Text('None'),
              subtitle: const Text('No lock screen'),
              selected: _config?.method == LockMethod.none,
              onTap: () => Navigator.pop(context, LockMethod.none),
            ),
            ListTile(
              leading: const Icon(Icons.dialpad),
              title: const Text('PIN'),
              subtitle: const Text('4-6 digit code'),
              selected: _config?.method == LockMethod.pin,
              onTap: () => Navigator.pop(context, LockMethod.pin),
            ),
            ListTile(
              leading: const Icon(Icons.pattern),
              title: const Text('Pattern'),
              subtitle: const Text('Draw a pattern'),
              selected: _config?.method == LockMethod.pattern,
              onTap: () => Navigator.pop(context, LockMethod.pattern),
            ),
            ListTile(
              leading: const Icon(Icons.password),
              title: const Text('Password'),
              subtitle: const Text('Use system password'),
              selected: _config?.method == LockMethod.password,
              onTap: () => Navigator.pop(context, LockMethod.password),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (result != null && result != _config?.method) {
      await _handleMethodChange(result);
    }
  }

  Future<void> _handleMethodChange(LockMethod newMethod) async {
    if (newMethod == LockMethod.pin) {
      // Show PIN setup
      final pin = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const PinSetupDialog(),
      );
      if (pin != null) {
        setState(() {
          _config!.method = newMethod;
          _config!.pinHash = _configService.hashPin(pin);
        });
        await _saveConfig();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PIN set successfully')),
          );
        }
      }
    } else if (newMethod == LockMethod.pattern) {
      // Show pattern setup
      final pattern = await Navigator.push<List<int>>(
        context,
        MaterialPageRoute(
          builder: (context) => const PatternSetupScreen(),
        ),
      );
      if (pattern != null) {
        setState(() {
          _config!.method = newMethod;
          _config!.patternHash = _configService.hashPattern(pattern);
        });
        await _saveConfig();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pattern set successfully')),
          );
        }
      }
    } else {
      // None or Password - no additional setup needed
      setState(() {
        _config!.method = newMethod;
      });
      await _saveConfig();
    }
  }

  Future<void> _showTimeoutPicker() async {
    final result = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Lock Timeout',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              title: const Text('Immediately'),
              selected: _config?.timeoutSeconds == 0,
              onTap: () => Navigator.pop(context, 0),
            ),
            ListTile(
              title: const Text('1 minute'),
              selected: _config?.timeoutSeconds == 60,
              onTap: () => Navigator.pop(context, 60),
            ),
            ListTile(
              title: const Text('5 minutes'),
              selected: _config?.timeoutSeconds == 300,
              onTap: () => Navigator.pop(context, 300),
            ),
            ListTile(
              title: const Text('15 minutes'),
              selected: _config?.timeoutSeconds == 900,
              onTap: () => Navigator.pop(context, 900),
            ),
            ListTile(
              title: const Text('Never'),
              selected: _config?.timeoutSeconds == -1,
              onTap: () => Navigator.pop(context, -1),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _config!.timeoutSeconds = result;
      });
      await _saveConfig();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lock Screen'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ListTile(
                  title: const Text('Lock method'),
                  subtitle: Text(_methodLabel(_config!.method)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showMethodPicker,
                ),
                if (_config!.method == LockMethod.pin)
                  ListTile(
                    title: const Text('Change PIN'),
                    leading: const Icon(Icons.dialpad),
                    onTap: () => _handleMethodChange(LockMethod.pin),
                  ),
                if (_config!.method == LockMethod.pattern)
                  ListTile(
                    title: const Text('Change pattern'),
                    leading: const Icon(Icons.pattern),
                    onTap: () => _handleMethodChange(LockMethod.pattern),
                  ),
                const Divider(),
                ListTile(
                  title: const Text('Lock timeout'),
                  subtitle: Text(_timeoutLabel(_config!.timeoutSeconds)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showTimeoutPicker,
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text(
                    'Note: You can always use your system password to unlock, '
                    'even if PIN or pattern is set.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            ),
    );
  }
}
