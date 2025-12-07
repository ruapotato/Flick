import 'package:flutter/material.dart';

class PinSetupDialog extends StatefulWidget {
  const PinSetupDialog({super.key});

  @override
  State<PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<PinSetupDialog> {
  String _pin = '';
  String _confirmPin = '';
  bool _isConfirming = false;
  String? _error;

  void _onDigitPressed(String digit) {
    setState(() {
      _error = null;
      if (_isConfirming) {
        if (_confirmPin.length < 6) {
          _confirmPin += digit;
        }
      } else {
        if (_pin.length < 6) {
          _pin += digit;
        }
      }
    });
  }

  void _onBackspace() {
    setState(() {
      _error = null;
      if (_isConfirming) {
        if (_confirmPin.isNotEmpty) {
          _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
        }
      } else {
        if (_pin.isNotEmpty) {
          _pin = _pin.substring(0, _pin.length - 1);
        }
      }
    });
  }

  void _onSubmit() {
    if (!_isConfirming) {
      if (_pin.length < 4) {
        setState(() {
          _error = 'PIN must be at least 4 digits';
        });
        return;
      }
      setState(() {
        _isConfirming = true;
      });
    } else {
      if (_confirmPin != _pin) {
        setState(() {
          _error = 'PINs do not match';
          _confirmPin = '';
        });
        return;
      }
      Navigator.pop(context, _pin);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPin = _isConfirming ? _confirmPin : _pin;

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isConfirming ? 'Confirm PIN' : 'Enter new PIN',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _isConfirming
                  ? 'Enter the same PIN again'
                  : '4-6 digits',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            // PIN dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (index) {
                final filled = index < currentPin.length;
                return Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
                );
              }),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 24),
            // Number pad
            _buildNumberPad(),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: currentPin.length >= 4 ? _onSubmit : null,
                  child: Text(_isConfirming ? 'Confirm' : 'Next'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberPad() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildDigitButton('1'),
            _buildDigitButton('2'),
            _buildDigitButton('3'),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildDigitButton('4'),
            _buildDigitButton('5'),
            _buildDigitButton('6'),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildDigitButton('7'),
            _buildDigitButton('8'),
            _buildDigitButton('9'),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 72, height: 56),
            _buildDigitButton('0'),
            SizedBox(
              width: 72,
              height: 56,
              child: IconButton(
                onPressed: _onBackspace,
                icon: const Icon(Icons.backspace_outlined),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDigitButton(String digit) {
    return SizedBox(
      width: 72,
      height: 56,
      child: TextButton(
        onPressed: () => _onDigitPressed(digit),
        child: Text(
          digit,
          style: const TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}
