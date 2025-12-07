import 'package:flutter/material.dart';

class PatternSetupScreen extends StatefulWidget {
  const PatternSetupScreen({super.key});

  @override
  State<PatternSetupScreen> createState() => _PatternSetupScreenState();
}

class _PatternSetupScreenState extends State<PatternSetupScreen> {
  List<int> _pattern = [];
  List<int> _confirmPattern = [];
  bool _isConfirming = false;
  String? _error;
  Offset? _currentTouch;

  void _onPatternComplete(List<int> pattern) {
    if (!_isConfirming) {
      if (pattern.length < 4) {
        setState(() {
          _error = 'Pattern must connect at least 4 dots';
          _pattern = [];
        });
        return;
      }
      setState(() {
        _pattern = pattern;
        _isConfirming = true;
        _error = null;
      });
    } else {
      if (!_listEquals(pattern, _pattern)) {
        setState(() {
          _error = 'Patterns do not match. Try again.';
          _confirmPattern = [];
        });
        return;
      }
      Navigator.pop(context, _pattern);
    }
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _reset() {
    setState(() {
      _pattern = [];
      _confirmPattern = [];
      _isConfirming = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Pattern'),
        actions: [
          if (_isConfirming)
            TextButton(
              onPressed: _reset,
              child: const Text('Reset'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            Text(
              _isConfirming ? 'Confirm your pattern' : 'Draw an unlock pattern',
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text(
              _isConfirming
                  ? 'Draw the same pattern again'
                  : 'Connect at least 4 dots',
              style: const TextStyle(color: Colors.grey),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const Spacer(),
            PatternGridWidget(
              key: ValueKey(_isConfirming),
              onPatternComplete: _onPatternComplete,
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class PatternGridWidget extends StatefulWidget {
  final void Function(List<int>) onPatternComplete;

  const PatternGridWidget({
    super.key,
    required this.onPatternComplete,
  });

  @override
  State<PatternGridWidget> createState() => _PatternGridWidgetState();
}

class _PatternGridWidgetState extends State<PatternGridWidget> {
  List<int> _selectedNodes = [];
  Offset? _currentTouch;
  final List<Offset> _nodePositions = [];
  static const double _nodeRadius = 24.0;
  static const double _gridSize = 280.0;

  @override
  void initState() {
    super.initState();
    // Calculate node positions for a 3x3 grid
    const spacing = _gridSize / 3;
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        _nodePositions.add(Offset(
          spacing / 2 + col * spacing,
          spacing / 2 + row * spacing,
        ));
      }
    }
  }

  int? _getNodeAtPosition(Offset position) {
    for (int i = 0; i < _nodePositions.length; i++) {
      final node = _nodePositions[i];
      final distance = (position - node).distance;
      if (distance < _nodeRadius * 1.5) {
        return i;
      }
    }
    return null;
  }

  void _onPanStart(DragStartDetails details) {
    final pos = details.localPosition;
    final node = _getNodeAtPosition(pos);
    setState(() {
      _selectedNodes = [];
      _currentTouch = pos;
      if (node != null) {
        _selectedNodes.add(node);
      }
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final pos = details.localPosition;
    final node = _getNodeAtPosition(pos);
    setState(() {
      _currentTouch = pos;
      if (node != null && !_selectedNodes.contains(node)) {
        _selectedNodes.add(node);
      }
    });
  }

  void _onPanEnd(DragEndDetails details) {
    final pattern = List<int>.from(_selectedNodes);
    setState(() {
      _selectedNodes = [];
      _currentTouch = null;
    });
    if (pattern.isNotEmpty) {
      widget.onPatternComplete(pattern);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: CustomPaint(
        size: const Size(_gridSize, _gridSize),
        painter: PatternPainter(
          nodePositions: _nodePositions,
          selectedNodes: _selectedNodes,
          currentTouch: _currentTouch,
          nodeRadius: _nodeRadius,
          primaryColor: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class PatternPainter extends CustomPainter {
  final List<Offset> nodePositions;
  final List<int> selectedNodes;
  final Offset? currentTouch;
  final double nodeRadius;
  final Color primaryColor;

  PatternPainter({
    required this.nodePositions,
    required this.selectedNodes,
    required this.currentTouch,
    required this.nodeRadius,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final nodePaint = Paint()
      ..color = Colors.grey.shade600
      ..style = PaintingStyle.fill;

    final selectedNodePaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.7)
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    // Draw lines between selected nodes
    if (selectedNodes.length > 1) {
      for (int i = 0; i < selectedNodes.length - 1; i++) {
        canvas.drawLine(
          nodePositions[selectedNodes[i]],
          nodePositions[selectedNodes[i + 1]],
          linePaint,
        );
      }
    }

    // Draw line to current touch position
    if (selectedNodes.isNotEmpty && currentTouch != null) {
      canvas.drawLine(
        nodePositions[selectedNodes.last],
        currentTouch!,
        linePaint,
      );
    }

    // Draw all nodes
    for (int i = 0; i < nodePositions.length; i++) {
      final isSelected = selectedNodes.contains(i);
      final paint = isSelected ? selectedNodePaint : nodePaint;

      // Outer circle
      canvas.drawCircle(
        nodePositions[i],
        nodeRadius,
        paint,
      );

      // Inner circle (lighter)
      canvas.drawCircle(
        nodePositions[i],
        nodeRadius * 0.4,
        Paint()
          ..color = isSelected
              ? Colors.white.withValues(alpha: 0.5)
              : Colors.grey.shade400,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PatternPainter oldDelegate) {
    return oldDelegate.selectedNodes != selectedNodes ||
        oldDelegate.currentTouch != currentTouch;
  }
}
