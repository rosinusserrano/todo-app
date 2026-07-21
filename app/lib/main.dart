// Window-behaviour proof for the Flutter port.
//
// Before porting ~1700 lines of tuned UI, this verifies the one requirement the
// rewrite is not allowed to lose: a frameless, transparent, acrylic window that
// stays on top of other applications *while unfocused*.
//
// Click another window after launching. This one must remain visible.

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:window_manager/window_manager.dart';

bool get isDesktop =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (isDesktop) {
    await acrylic.Window.initialize();
    await windowManager.ensureInitialized();

    // Matches the Tauri window config this replaces: 340x480, frameless,
    // transparent, always on top.
    const options = WindowOptions(
      size: Size(340, 480),
      minimumSize: Size(260, 200),
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      title: 'Todo Widget',
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setHasShadow(true);
      await windowManager.show();
      await windowManager.focus();
    });

    // Windows 11 acrylic. On Windows 10 this can bleed outside the window
    // bounds and lags on drag, but 11 fixed both.
    await acrylic.Window.setEffect(
      effect: acrylic.WindowEffect.acrylic,
      dark: true,
    );
  }

  runApp(const ProofApp());
}

class ProofApp extends StatelessWidget {
  const ProofApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: const ProofPage(),
    );
  }
}

class ProofPage extends StatefulWidget {
  const ProofPage({super.key});

  @override
  State<ProofPage> createState() => _ProofPageState();
}

class _ProofPageState extends State<ProofPage> {
  bool _pinned = true;

  Future<void> _togglePin() async {
    final next = !_pinned;
    await windowManager.setAlwaysOnTop(next);
    // Read the value back rather than trusting the write, so the label
    // reflects the real window state.
    final actual = await windowManager.isAlwaysOnTop();
    setState(() => _pinned = actual);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withValues(alpha: 0.04),
        ),
        child: Column(
          children: [
            // Drag handle, standing in for the .titlebar element.
            DragToMoveArea(
              child: SizedBox(
                height: 38,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    const Text(
                      'Todo Widget',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: _pinned ? 'Unpin' : 'Pin on top',
                      iconSize: 16,
                      icon: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined),
                      onPressed: _togglePin,
                    ),
                    IconButton(
                      tooltip: 'Minimize',
                      iconSize: 16,
                      icon: const Icon(Icons.remove),
                      onPressed: windowManager.minimize,
                    ),
                    IconButton(
                      tooltip: 'Close',
                      iconSize: 16,
                      icon: const Icon(Icons.close),
                      onPressed: windowManager.close,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _pinned ? Icons.layers : Icons.layers_clear,
                        size: 40,
                        color: _pinned ? Colors.lightBlueAccent : Colors.white38,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _pinned ? 'Always on top: ON' : 'Always on top: OFF',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Click another window.\nThis one should stay visible.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.white60),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
