import 'dart:async';

import 'package:flutter/material.dart';

/// Runs native/local initialization behind a visible, recoverable startup view.
/// Raw exception strings are never rendered: they can include file paths, remote
/// service data or removed vendor text.
class ReelboxBootstrap extends StatefulWidget {
  const ReelboxBootstrap({
    super.key,
    required this.initialize,
    required this.builder,
  });
  final Future<void> Function() initialize;
  final WidgetBuilder builder;
  @override
  State<ReelboxBootstrap> createState() => _ReelboxBootstrapState();
}

class _ReelboxBootstrapState extends State<ReelboxBootstrap> {
  bool _ready = false, _failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final generation = ++_generation;
    setState(() {
      _ready = false;
      _failed = false;
    });
    try {
      await widget.initialize();
      if (mounted && generation == _generation) setState(() => _ready = true);
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.builder(context);
    return MaterialApp(
      title: 'Reelbox',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFFBC3D34),
      ),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.local_movies_outlined, size: 48),
                const SizedBox(height: 24),
                const Text('Reelbox', style: TextStyle(fontSize: 28)),
                const SizedBox(height: 24),
                if (!_failed) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                  const Text('Opening your library'),
                ] else ...[
                  const Text(
                    'Reelbox could not start',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your library has not been reset. Try starting again.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => unawaited(_start()),
                    child: const Text('Try again'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
