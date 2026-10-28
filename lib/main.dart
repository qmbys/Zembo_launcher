import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';
import 'screens/launcher_screen.dart';
import 'widgets/setup_wizard.dart';
import 'services/settings_service.dart';
import 'services/tray_service.dart';
import 'widgets/zembo_title_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await TrayService.instance.initialize();

  const windowOptions = WindowOptions(
    title: 'Zembo Launcher',
    size: Size(1200, 700),
    minimumSize: Size(1000, 600),
    center: true,
    backgroundColor: Color(0xFF07110E),
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const ZemboLauncherApp());
}

class ZemboLauncherApp extends StatelessWidget {
  const ZemboLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZemboLauncher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF43E477),
          brightness: Brightness.dark,
          primary: const Color(0xFF43E477),
          secondary: const Color(0xFF8CEFA8),
          surface: const Color(0xFF0D1713),
          surfaceVariant: const Color(0xFF14221A),
          outline: const Color(0xFF294333),
          onSurface: Colors.white,
          onSurfaceVariant: const Color(0xFF91A497),
        ),
        scaffoldBackgroundColor: const Color(0xFF080F0D),
        cardTheme: CardThemeData(
          color: const Color(0xFF111C16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFF26392D), width: 0.8),
          ),
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
          headlineLarge: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, letterSpacing: -0.7),
          headlineMedium: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, letterSpacing: -0.4),
          titleLarge: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600),
          titleMedium: GoogleFonts.inter(fontWeight: FontWeight.w600),
          labelLarge: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D1713),
          foregroundColor: Color(0xFFEAF4ED),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0B1510),
          labelStyle: const TextStyle(color: Color(0xFF91A497)),
          hintStyle: const TextStyle(color: Color(0xFF65786C)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF26392D)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF26392D)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF43E477), width: 1.4),
          ),
        ),
      ),
      home: const AppRouter(),
      builder: (context, child) => Column(
        children: [
          const ZemboTitleBar(),
          Expanded(child: child ?? const SizedBox.shrink()),
        ],
      ),
    );
  }
}

class AppRouter extends StatefulWidget {
  const AppRouter({super.key});

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> {
  bool _isLoading = true;
  bool _isSetupCompleted = false;

  @override
  void initState() {
    super.initState();
    _checkSetup();
  }

  Future<void> _checkSetup() async {
    final isSetup = await SettingsService.isSetupCompleted();
    if (mounted) {
      setState(() {
        _isSetupCompleted = isSetup;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_isSetupCompleted) {
      return const LauncherScreen();
    }

    return SetupWizard(
      onSetupComplete: () {
        // Переходим на лаунчер после завершения установки
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LauncherScreen()),
        );
      },
    );
  }
}