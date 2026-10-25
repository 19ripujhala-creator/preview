import 'package:shaladarpan/widgets/page_transitions.dart';
import 'services/portals/rajsims/direct/rajsims_runtime.dart';

// C:\shaladarpan_app\lib\main.dart (or your main file path)
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shaladarpan/dashboard.dart';
import 'package:shaladarpan/screens/login_screen.dart';
import 'package:shaladarpan/services/core/local_db_service.dart';
import 'package:shaladarpan/services/core/sync_coordinator.dart';
import 'package:shaladarpan/services/core/network_sync_dispatcher.dart';
import 'package:shaladarpan/services/core/secure_storage_service.dart';
import 'package:shaladarpan/services/core/ecosystem_service.dart';
import 'package:shaladarpan/experiments/direct_school_session.dart';
import 'package:shaladarpan/services/portals/shaladarpan/student_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/school_login_service.dart';
import 'package:shaladarpan/services/portals/staff_login/direct/staff_runtime.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Local Offline Database (Hive) initialize karein
  try {
    await LocalDbService.init();
  } catch (e) {
    debugPrint("⚠️ LocalDbService init warning: $e");
  }

  // 4. Orientation guard (Safe for both Mobile and Web)
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  runApp(const RajShalaMobileApp());
}

class RajShalaMobileApp extends StatelessWidget {
  const RajShalaMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Shaladarpan Ecosystem Automation',
      theme: ThemeData(
        pageTransitionsTheme: desktopPageTransitions,
        fontFamily: 'PlusJakartaSans',
        textTheme: const TextTheme(
          headlineSmall: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -.4,
            color: Color(0xFF0F172A),
          ),
          titleLarge: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -.35,
            color: Color(0xFF0F172A),
          ),
          titleMedium: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -.2,
            color: Color(0xFF0F172A),
          ),
          titleSmall: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: -.1,
            color: Color(0xFF0F172A),
          ),
          bodyMedium: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: Color(0xFF475569),
          ),
          bodySmall: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w400,
            color: Color(0xFF64748B),
          ),
        ),
        appBarTheme: const AppBarTheme(
          titleTextStyle: TextStyle(
            fontFamily: 'PlusJakartaSans',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -.3,
            color: Color(0xFF0F172A),
          ),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFD3D9E1),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      ),
      builder: (context, child) => AppNavigationBackdrop(
        child: child ?? const SizedBox.shrink(),
      ),
      home: const AppRootCoordinator(),
    );
  }
}

class AppRootCoordinator extends StatefulWidget {
  const AppRootCoordinator({super.key});

  @override
  State<AppRootCoordinator> createState() => AppRootCoordinatorState();

  static AppRootCoordinatorState of(BuildContext context) {
    return context.findAncestorStateOfType<AppRootCoordinatorState>()!;
  }
}

class AppRootCoordinatorState extends State<AppRootCoordinator>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _isAuthenticated = false;
  String _schoolId = "";
  String? _startupNotice;
  int _sessionEpoch = 0;
  bool _loggingOut = false;
  late AnimationController _fadeController;
  final GlobalKey<LoginDesignScreenState> _loginKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      value: 0.0,
    );
    _checkExistingSession();
  }

  Future<void> _checkExistingSession() async {
    final epoch = _sessionEpoch;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('user_signed_out') == true) return;
      if (prefs.getString(SchoolLoginService.modeKey) == 'direct') {
        if (kIsWeb) return;
        final result = await SchoolLoginService.instance.restore(
          isCurrent: () => mounted && epoch == _sessionEpoch,
        );
        if (!mounted || epoch != _sessionEpoch) return;
        if (result['success'] == true) {
          _schoolId = result['school_id'] as String;
          _isAuthenticated = true;
          _startupNotice = null;
          _fadeController.value = 1.0;
          NetworkSyncDispatcher().dispose();
          SyncCoordinator.dispose();
        }
        // A failed direct restore stays on login; never fall through to Python.
        return;
      }
      final credentials = await SecureStorageService.getAllPortalCreds();
      if (credentials.values.any((value) => value.isEmpty)) return;
      final result = await EcosystemService.initialize(credentials);
      if (!mounted || epoch != _sessionEpoch) return;
      if (result['success'] == true) {
        _schoolId = credentials['school_id']!;
        _isAuthenticated = true;
        _startupNotice = result['all_ready'] == true
            ? null
            : result['message']?.toString();
        _fadeController.value = 1.0;
        if (StudentService.directAttendanceEnabled) {
          NetworkSyncDispatcher().dispose();
          SyncCoordinator.dispose();
        } else {
          _startSyncListeners();
        }
      }
    } catch (e) {
      debugPrint('Saved session could not be restored. Please sign in.');
    } finally {
      if (mounted && epoch == _sessionEpoch) setState(() => _isLoading = false);
    }
  }

  void _startSyncListeners() {
    NetworkSyncDispatcher().initialize();
    SyncCoordinator.startListening();
  }

  @override
  void dispose() {
    _sessionEpoch++;
    _fadeController.dispose();
    SyncCoordinator.dispose();
    NetworkSyncDispatcher().dispose();
    super.dispose();
  }

  Future<void> login(String schoolId, {String password = ""}) async {
    final effectiveId = schoolId.trim();
    final directLogin =
        StudentService.directAttendanceEnabled &&
        DirectSchoolSession.available &&
        DirectSchoolSession.schoolId == effectiveId;
    if (effectiveId.isEmpty ||
        (!directLogin && !EcosystemService.isSchoolReady)) {
      return;
    }
    final epoch = ++_sessionEpoch;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await SchoolLoginService.rememberMode(direct: directLogin);
    } catch (_) {
      debugPrint(
        'School connection mode could not be saved. Please retry login.',
      );
      return;
    }
    if (!mounted || epoch != _sessionEpoch) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_school_id', effectiveId);
      await prefs.setString('school_id', effectiveId);
      await prefs.setBool('user_signed_out', false);
    } catch (_) {}
    if (!mounted || epoch != _sessionEpoch) return;
    if (directLogin) {
      // The verified direct session belongs to this school. Background sync
      // still uses the Python backend, so it must stay stopped in direct mode.
      if (!DirectSchoolSession.available ||
          DirectSchoolSession.schoolId != effectiveId) {
        return;
      }
      NetworkSyncDispatcher().dispose();
      SyncCoordinator.dispose();
    } else {
      StudentService.directAttendanceEnabled = false;
      DirectSchoolSession.reset();
      _startSyncListeners();
    }
    setState(() {
      _schoolId = effectiveId;
      _isAuthenticated = true;
      _startupNotice = directLogin ? null : EcosystemService.summary;
    });
    _fadeController.forward(from: 0.0);
  }

  Future<void> logout() async {
    if (_loggingOut) return;
    _loggingOut = true;
    ++_sessionEpoch;
    StudentService.directAttendanceEnabled = false;
    DirectSchoolSession.reset();
    EcosystemService.reset();
    unawaited(StaffDirectRuntime.reset());
    unawaited(RajsimsDirectRuntime.reset());
    NetworkSyncDispatcher().dispose();
    SyncCoordinator.dispose();
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('user_signed_out', true);
      } catch (_) {}
      if (!mounted) return;
      await _fadeController.reverse();
      if (!mounted) return;
      setState(() {
        _isAuthenticated = false;
        _startupNotice = null;
      });
    } finally {
      _loggingOut = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFD3D9E1),
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF0F172A),
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFD3D9E1),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (!_isAuthenticated)
            LoginDesignScreen(
              key: _loginKey,
              onLoginSuccess: (id) => login(id),
            ),
          if (_isAuthenticated)
            FadeTransition(
              opacity: _fadeController,
              child: DashboardScreen(
                schoolId: _schoolId,
                startupNotice: _startupNotice,
                onLogoutRequested: logout,
              ),
            ),
        ],
      ),
    );
  }
}
