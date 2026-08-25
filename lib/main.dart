import 'package:flutter/material.dart';

import 'state/radio_controller.dart';
import 'theme/andon_theme.dart';
import 'ui/home_screen.dart';

void main() => runApp(const AndonRadioApp());

class AndonRadioApp extends StatefulWidget {
  const AndonRadioApp({super.key, this.controller});

  /// Injected by tests so the UI can be driven without touching the network.
  final RadioController? controller;

  @override
  State<AndonRadioApp> createState() => _AndonRadioAppState();
}

class _AndonRadioAppState extends State<AndonRadioApp> {
  late final RadioController _controller =
      widget.controller ?? RadioController();

  /// A controller handed in from outside is owned by whoever made it.
  late final bool _ownsController = widget.controller == null;

  @override
  void initState() {
    super.initState();
    _controller.init();
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Andon Radio',
      debugShowCheckedModeBanner: false,
      theme: AndonTheme.light(),
      darkTheme: AndonTheme.dark(),
      home: HomeScreen(controller: _controller),
    );
  }
}
