import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'treel/model.dart';
import 'treel/scanner.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

void main() => runApp(const TpmsLibreApp());

class TpmsLibreApp extends StatefulWidget {
  const TpmsLibreApp({super.key});

  @override
  State<TpmsLibreApp> createState() => _TpmsLibreAppState();
}

class _TpmsLibreAppState extends State<TpmsLibreApp>
    with WidgetsBindingObserver {
  final TreelModel _model = TreelModel();
  late final TreelScanner _scanner = TreelScanner(_model);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The moment a stale number becomes real.
    _model.onSensorWake = (_) {
      if (!_model.haptics) return;
      // lightImpact is close to imperceptible on a Pixel. This is a real
      // event -- a stale number becoming true -- not a UI tick, so it gets
      // something you can actually feel.
      HapticFeedback.mediumImpact();
    };
    _model.load();
    // Separate from load, and not awaited by it: see TreelModel.openPhotos.
    _model.openPhotos();
    _scanner.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _model.flush();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanner.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TPMS Libre',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: HomePage(model: _model, scanner: _scanner),
    );
  }
}
