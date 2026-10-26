import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'audio/audio_runtime.dart';
import 'providers/music_player_provider.dart';
import 'screens/home_screen.dart';
import 'ui/one_ui_9.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  try {
    await AudioRuntime.init(timeout: const Duration(seconds: 4));
  } catch (_) {}

  runApp(
    ChangeNotifierProvider(
      create: (_) => MusicPlayerProvider()..bootstrap(),
      child: const MusicApp(),
    ),
  );
}

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class MusicApp extends StatefulWidget {
  const MusicApp({super.key});

  @override
  State<MusicApp> createState() => _MusicAppState();
}

class _MusicAppState extends State<MusicApp> with WidgetsBindingObserver {
  AppLifecycleState? _lastLifecycleState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final previous = _lastLifecycleState;
    _lastLifecycleState = state;
    if (state == AppLifecycleState.resumed &&
        (previous == AppLifecycleState.paused ||
            previous == AppLifecycleState.inactive ||
            previous == AppLifecycleState.hidden)) {
      // Resuming the app must never mutate the navigation stack. The previous
      // implementation popped every detail route back to Home whenever Android
      // briefly moved the activity to inactive/paused (notification shade,
      // permission UI, app switcher, etc.). Keep the exact route/tab/scroll
      // position and only refresh the playback/runtime state.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<MusicPlayerProvider>().handleAppResumeFromBackground();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicPlayerProvider>();
    final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final dark = brightness == Brightness.dark;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: dark ? const Color(0xFF070B13) : const Color(0xFFF5F7FF),
        systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Music',
      themeMode: ThemeMode.system,
      theme: OneUi9.theme(Brightness.light),
      darkTheme: OneUi9.theme(Brightness.dark),
      locale: provider.locale,
      supportedLocales: const [
        Locale('pt', 'BR'),
        Locale('en'),
        Locale('ja'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorKey: appNavigatorKey,
      builder: (context, child) => OneUi9Backdrop(
        // Keep the visual backdrop edge-to-edge, but constrain the entire
        // Navigator (every screen, dialog and bottom sheet) to Android's safe
        // display area. SafeArea also rewrites MediaQuery padding for its
        // descendants, so screens that already use SafeArea are not padded
        // twice. This prevents controls from ever sitting under the system
        // navigation/gesture bar while preserving the Liquid Glass background.
        child: SafeArea(
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
