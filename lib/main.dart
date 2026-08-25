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

class _AndonRadioAppState extends State<AndonRadioApp>
    with WidgetsBindingObserver {
  late final RadioController _controller =
      widget.controller ?? RadioController();

  /// A controller handed in from outside is owned by whoever made it.
  late final bool _ownsController = widget.controller == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.init();
  }

  /// Poll only while the app is actually in front.
  ///
  /// Two people share these speakers, so the screen has to catch up with
  /// whatever the other one did - and the moment it is most likely to be out
  /// of date is the moment it comes back into view. Stopping the timer in the
  /// background keeps that from costing anything while nobody is looking.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _controller.resumePolling();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _controller.pausePolling();
      case AppLifecycleState.inactive:
        // Transient - a notification shade pulled down, a permission dialog.
        // Not worth tearing the timer down for.
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
