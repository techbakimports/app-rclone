import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/providers/rclone_providers.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/remotes/remotes_screen.dart';
import 'features/transfers/transfers_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/setup/binary_download_screen.dart';

class RcloneApp extends ConsumerWidget {
  const RcloneApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final binaryStatus = ref.watch(binaryStatusProvider);

    return MaterialApp(
      title: 'RcloneApp',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      themeMode: ThemeMode.dark,
      home: switch (binaryStatus) {
        BinaryStatus.checking => const _SplashScreen(),
        BinaryStatus.notInstalled => const BinaryDownloadScreen(),
        BinaryStatus.ready => const _AppLifecycleWrapper(),
      },
    );
  }
}

// ── Splash ────────────────────────────────────────────────────────────────────

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

// ── Lifecycle wrapper (resumes daemon check on foreground) ────────────────────

class _AppLifecycleWrapper extends ConsumerStatefulWidget {
  const _AppLifecycleWrapper();

  @override
  ConsumerState<_AppLifecycleWrapper> createState() =>
      _AppLifecycleWrapperState();
}

class _AppLifecycleWrapperState extends ConsumerState<_AppLifecycleWrapper>
    with WidgetsBindingObserver {
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
    if (state == AppLifecycleState.resumed) {
      ref.read(daemonProvider.notifier).checkRunning();
    }
  }

  @override
  Widget build(BuildContext context) => const AppShell();
}

// ── App shell with bottom nav ─────────────────────────────────────────────────

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _currentIndex = 0;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard),
      label: 'Dashboard',
    ),
    NavigationDestination(
      icon: Icon(Icons.cloud_outlined),
      selectedIcon: Icon(Icons.cloud),
      label: 'Remotes',
    ),
    NavigationDestination(
      icon: Icon(Icons.swap_horiz_outlined),
      selectedIcon: Icon(Icons.swap_horiz),
      label: 'Transfers',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Settings',
    ),
  ];

  static const _screens = [
    DashboardScreen(),
    RemotesScreen(),
    TransfersScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: _destinations,
      ),
    );
  }
}

// ── Palette & Theme ───────────────────────────────────────────────────────────

abstract final class AppColors {
  static const neonGreen = Color(0xFF39FF14);
  static const violet = Color(0xFFAA00FF);
  static const bg = Color(0xFF0F0F0F);
  static const surface = Color(0xFF1A1A1A);
  static const card = Color(0xFF242424);
  static const onCard = Color(0xFFE0E0E0);
  static const muted = Color(0xFF888888);
}

ThemeData _buildTheme() {
  const cs = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.neonGreen,
    onPrimary: Color(0xFF000000),
    primaryContainer: Color(0xFF003D00),
    onPrimaryContainer: AppColors.neonGreen,
    secondary: AppColors.violet,
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFF2D0050),
    onSecondaryContainer: AppColors.violet,
    tertiary: Color(0xFF00C853),
    onTertiary: Color(0xFF000000),
    tertiaryContainer: Color(0xFF003818),
    onTertiaryContainer: Color(0xFF00C853),
    error: Color(0xFFFF5252),
    onError: Color(0xFF000000),
    errorContainer: Color(0xFF3D0000),
    onErrorContainer: Color(0xFFFF5252),
    surface: AppColors.surface,
    onSurface: Color(0xFFE8E8E8),
    surfaceContainerHighest: AppColors.card,
    surfaceContainerHigh: Color(0xFF1E1E1E),
    surfaceContainer: AppColors.surface,
    surfaceContainerLow: Color(0xFF141414),
    surfaceContainerLowest: AppColors.bg,
    onSurfaceVariant: AppColors.muted,
    outline: Color(0xFF3A3A3A),
    outlineVariant: Color(0xFF2A2A2A),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE8E8E8),
    onInverseSurface: Color(0xFF1A1A1A),
    inversePrimary: Color(0xFF006400),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: Color(0xFFE8E8E8),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: Color(0xFFE8E8E8),
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.neonGreen.withAlpha(30),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColors.neonGreen, size: 22);
        }
        return const IconThemeData(color: AppColors.muted, size: 22);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            color: AppColors.neonGreen,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          );
        }
        return const TextStyle(color: AppColors.muted, fontSize: 11);
      }),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        side: BorderSide(color: Color(0xFF2E2E2E)),
      ),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.neonGreen,
        foregroundColor: Colors.black,
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.violet,
        side: const BorderSide(color: AppColors.violet),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.neonGreen),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bg,
      labelStyle: const TextStyle(color: AppColors.muted),
      hintStyle: TextStyle(color: AppColors.muted.withAlpha(180)),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF3A3A3A)),
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.neonGreen, width: 1.5),
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      errorBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFFFF5252)),
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFFFF5252), width: 1.5),
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.card,
      selectedColor: AppColors.neonGreen.withAlpha(40),
      labelStyle: const TextStyle(fontSize: 12),
      side: const BorderSide(color: Color(0xFF3A3A3A)),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFF2A2A2A),
      thickness: 1,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.muted,
      textColor: Color(0xFFE8E8E8),
      tileColor: Colors.transparent,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.neonGreen,
      linearTrackColor: Color(0xFF2A2A2A),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.violet,
      foregroundColor: Colors.white,
      extendedTextStyle: TextStyle(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.card,
      contentTextStyle: TextStyle(color: Color(0xFFE8E8E8)),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        side: BorderSide(color: Color(0xFF3A3A3A)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: AppColors.card,
        foregroundColor: AppColors.muted,
        selectedForegroundColor: Colors.black,
        selectedBackgroundColor: AppColors.neonGreen,
        side: const BorderSide(color: Color(0xFF3A3A3A)),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
      ),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: AppColors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        side: BorderSide(color: Color(0xFF3A3A3A)),
      ),
    ),
  );
}
