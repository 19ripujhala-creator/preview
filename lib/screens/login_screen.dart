import 'package:shaladarpan/experiments/direct_school_session.dart';
import 'package:shaladarpan/services/portals/shaladarpan/student_service.dart';
import 'package:lottie/lottie.dart';

import 'package:shaladarpan/widgets/account_avatar.dart';

// C:\shaladarpan_app\lib\screens\login_screen.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:shaladarpan/experiments/direct_portal_probe.dart';
import 'package:shaladarpan/experiments/direct_portal_auth.dart';
import 'package:shaladarpan/services/portals/staff_login/direct/staff_runtime.dart';
import 'package:shaladarpan/services/portals/rajsims/direct/rajsims_runtime.dart';


import 'package:flutter/cupertino.dart';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'package:video_player/video_player.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:shaladarpan/services/core/secure_storage_service.dart';

import 'package:shaladarpan/services/core/ecosystem_service.dart';

import 'package:shaladarpan/services/portals/shaladarpan/dashboard_bootstrap.dart';

import 'package:shaladarpan/services/portals/shaladarpan/leave_approval_service.dart';

class LoginDesignScreen extends StatefulWidget {
  final ValueChanged<String> onLoginSuccess;

  const LoginDesignScreen({super.key, required this.onLoginSuccess});

  @override
  LoginDesignScreenState createState() => LoginDesignScreenState();
}

class LoginDesignScreenState extends State<LoginDesignScreen>
    with SingleTickerProviderStateMixin {
  final PageController _wizardController = PageController();

  int _currentStep = 0;

  final Map<TextEditingController, bool> _passwordVisible = {};

  final TextEditingController _shalaIdController = TextEditingController();

  final TextEditingController _shalaPassController = TextEditingController();

  final TextEditingController _staffIdController = TextEditingController();

  final TextEditingController _staffPassController = TextEditingController();

  final TextEditingController _rajsimsIdController = TextEditingController();

  final TextEditingController _rajsimsPassController = TextEditingController();

  bool _isLoggedOutState = false;

  bool _credentialsReady = false;

  String? _consentedSchoolId;

  bool get _hasSavedAccount => [
    _shalaIdController.text.trim(),
    _shalaPassController.text,

    _staffIdController.text.trim(),
    _staffPassController.text,

    _rajsimsIdController.text.trim(),
    _rajsimsPassController.text,
  ].every((value) => value.isNotEmpty);

  bool _directTestRunning = false;

  Future<void> _testDirectHttp() async {
    if (_directTestRunning ||
        _directLoginRunning ||
        _directStaffRunning ||
        _directRajsimsRunning ||
        _isLoading)
      return;
    setState(() => _directTestRunning = true);
    DirectPortalProbe? probe;
    try {
      probe = DirectPortalProbe();
      final result = await probe.run(node: 'SD1');
      debugPrint('DIRECT HTTP TEST: ${result.toJson()}');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Direct HTTP Test'),
          content: SingleChildScrollView(
            child: SelectableText(result.toJson().toString()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      debugPrint('DIRECT HTTP TEST ERROR: ${error.runtimeType}');
      if (mounted) {
        _showErrorSnackBar('Direct HTTP test failed. Check debug console.');
      }
    } finally {
      probe?.close();
      if (mounted) setState(() => _directTestRunning = false);
    }
  }

  bool _directLoginRunning = false;
  bool _directStaffRunning = false;

  bool _directRajsimsRunning = false;

  Future<void> _showRajsimsLoginFailure(Map failure) async {
    if (!mounted) return;
    final message =
        failure['message']?.toString() ??
        failure['code']?.toString() ??
        'RajSIMS login was not verified.';
    final diagnostics = EcosystemService.safeLoginDiagnostics(
      failure['diagnostics'],
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('RajSIMS login'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(message),
              if (failure['code'] != null || diagnostics.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Technical details'),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        const JsonEncoder.withIndent('  ').convert({
                          if (failure['code'] != null) 'code': failure['code'],
                          if (failure['message_source'] != null)
                            'message_source': failure['message_source'],
                          ...diagnostics,
                        }),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _testDirectRajsimsLogin() async {
    if (_directRajsimsRunning ||
        _directStaffRunning ||
        _directLoginRunning ||
        _directTestRunning ||
        _isLoading ||
        kIsWeb)
      return;
    await _credentialsLoaded;
    if (!mounted) return;
    final user = _rajsimsIdController.text.trim();
    final password = _rajsimsPassController.text;
    if (user.isEmpty || password.trim().isEmpty) {
      _showErrorSnackBar('Enter SSO ID and Password first.');
      return;
    }
    setState(() => _directRajsimsRunning = true);
    try {
      final runtime = await RajsimsDirectRuntime.get();
      final result = await runtime.coordinator.authenticate(user, password);
      if (!mounted) return;
      final message =
          result['message']?.toString() ??
          result['code']?.toString() ??
          'RajSIMS login was not verified.';
      if (result['success'] != true) {
        await _showRajsimsLoginFailure(result);
        return;
      }
      final profile = runtime.registry.auth.getUserInfo();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            result['success'] == true
                ? (result['session_verified'] == false
                      ? 'Direct RajSIMS Session Retained'
                      : 'Direct RajSIMS Login Verified')
                : 'Direct RajSIMS Login Failed',
          ),
          content: SingleChildScrollView(
            child: SelectableText(
              result['success'] == true
                  ? '$message\nOffice: ${profile['office_id']} · Organization: ${profile['org_id']}\n${profile['name'] ?? ''}'
                  : message,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        _showErrorSnackBar(
          error is ArgumentError
              ? error.message?.toString() ?? 'RajSIMS OCR version is required.'
              : 'Direct RajSIMS login error: ${error.runtimeType}',
        );
      }
    } finally {
      if (mounted) setState(() => _directRajsimsRunning = false);
    }
  }

  Future<void> _testDirectStaffLogin() async {
    if (_directStaffRunning ||
        _directRajsimsRunning ||
        _directLoginRunning ||
        _directTestRunning ||
        _isLoading ||
        kIsWeb)
      return;
    await _credentialsLoaded;
    if (!mounted) return;
    final user = _staffIdController.text.trim();
    final password = _staffPassController.text;
    if (user.isEmpty || password.trim().isEmpty) {
      _showErrorSnackBar('Enter Staff ID and Password first.');
      return;
    }
    setState(() => _directStaffRunning = true);
    try {
      final runtime = await StaffDirectRuntime.get();
      final result = await runtime.coordinator.authenticate(user, password);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            result['success'] == true
                ? 'Direct Staff Login Verified'
                : 'Direct Staff Login Failed',
          ),
          content: SelectableText(
            result['success'] == true
                ? 'Staff Portal Live on ${result['server_name'] ?? ''}. Saved session: ${result['cached'] == true}.'
                : result['message']?.toString() ??
                      result['code']?.toString() ??
                      'Staff login was not verified.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted)
        _showErrorSnackBar('Direct Staff login error: ${error.runtimeType}');
    } finally {
      if (mounted) setState(() => _directStaffRunning = false);
    }
  }

  Future<void> _testDirectLogin() async {
    if (_directLoginRunning ||
        _directStaffRunning ||
        _directRajsimsRunning ||
        _isLoading ||
        kIsWeb)
      return;
    await _credentialsLoaded;
    if (!mounted) return;
    final user = _shalaIdController.text.trim();
    final password = _shalaPassController.text;
    if (user.isEmpty || password.isEmpty) {
      _showErrorSnackBar('Enter School ID and Password first.');
      return;
    }
    setState(() => _directLoginRunning = true);
    DirectPortalAuth? auth;
    try {
      final outcome = await DirectPortalAuth.automaticLogin(
        user: user,
        password: password,
      );
      auth = outcome.auth;
      final result = outcome.result;
      if (!mounted) return;
      if (result.success && auth?.isVerified == true) {
        // Persist the credentials used by this verified login so a cold start
        // restores the same School account without requiring Staff/SSO data.
        await SecureStorageService.saveAllPortals(
          shalaId: user,
          shalaPass: password,
          staffId: _staffIdController.text.trim(),
          staffPass: _staffPassController.text,
          rajsimsId: _rajsimsIdController.text.trim(),
          rajsimsPass: _rajsimsPassController.text,
        );
        if (!mounted) return;
        // Transfer ownership of the authenticated HttpClient/cookies. The
        // Attendance Screen must use this SAME session, not log in again.
        DirectSchoolSession.attach(auth!, user);
        StudentService.directAttendanceEnabled = true;
        auth = null;

        // The existing onLoginSuccess callback owns Dashboard navigation.
        // Do NOT run EcosystemService.initialize here: that is the old
        // three-portal backend login and would undo the direct-only flow.
        widget.onLoginSuccess(user);
        return;
      }

      // Failed login stays on this page for CAPTCHA retry.
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Direct Login Failed'),
          content: SelectableText(result.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('DIRECT LOGIN TEST ERROR TYPE: ${e.runtimeType}');
      if (mounted)
        _showErrorSnackBar('Direct login test error: ${e.runtimeType}');
    } finally {
      auth?.close();
      if (mounted) setState(() => _directLoginRunning = false);
    }
  }

  bool _isLoading = false;

  bool _progressKnown = false;

  double _loginProgressTarget = 0.0;

  void _advanceLoginProgress(double next) {
    if (!mounted || next <= _loginProgressTarget) return;

    _loginProgressTarget = next.clamp(0.0, 0.95).toDouble();

    _progressController.animateTo(
      _loginProgressTarget,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
    );
  }

  bool _isApiCallInProgress = false; // 🛡️ Double-Hit Guard Flag

  String _liveStatusMessage = "Connecting to Ecosystem...";

  late AnimationController _progressController;

  VideoPlayerController? _videoController;

  bool get _supportsOptionalVideo =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  Future<void> _initOptionalVideo() async {
    if (!_supportsOptionalVideo) return;
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.asset(
        'assets/images/fpo@1x.mp4',
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await controller.initialize();
    } catch (_) {
      return;
    }
    if (!mounted) {
      unawaited(controller.dispose().catchError((_) {}));
      return;
    }
    _videoController = controller;
    try {
      await controller.setLooping(true);
      await controller.setVolume(0.0);
      await controller.play();
      if (!mounted || !identical(_videoController, controller)) return;
      setState(() => _isVideoReady = true);
      Future.delayed(const Duration(milliseconds: 60), () {
        if (mounted && _isVideoReady) setState(() => _showVideo = true);
      });
    } catch (_) {}
  }

  bool _isVideoReady = false;

  bool _showVideo = false;

  late final PageController _factsPageController;

  Timer? _carouselTimer;

  late final Future<void> _credentialsLoaded;

  int _currentFactIndex = 0;

  final List<Map<String, String>> _schoolFacts = [
    {
      "title": "Triple-Portal Ecosystem",
      "subtitle":
          "Connect Shala Darpan, Staff Corner, and RajSIMS from one place.",
    },

    {
      "title": "MDM Entry Optimization",

      "subtitle": "Daily automated reconciliation reduces manual grain calculation errors by over 90%.",
    },

    {
      "title": "Smart Portal Automation",

      "subtitle": "One-click batch sync saves up to 45 minutes of daily manual entry per school.",
    },
  ];

  void resetToDefaultState() {
    if (!mounted) return;

    setState(() {
      _isLoading = false;

      _isApiCallInProgress = false;

      _isLoggedOutState = _hasSavedAccount;

      _currentStep = _isLoggedOutState ? 3 : 0;

      _liveStatusMessage = "Connecting to Ecosystem...";
    });

    _progressController.value = 0.0;

    if (!_isLoggedOutState && _wizardController.hasClients) {
      _wizardController.jumpToPage(0);
    }

    final video = _videoController;
    if (_isVideoReady && video != null && !video.value.isPlaying) {
      unawaited(video.play().catchError((_) {}));
    }
  }

  @override
  void initState() {
    super.initState();

    _credentialsLoaded = _loadSavedCredentials();

    unawaited(_initOptionalVideo());

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );

    _factsPageController = PageController();

    _startFactsAutoPlay();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final credentials = await SecureStorageService.getAllPortalCreds();

      if (!mounted) return;

      void restore(
        TextEditingController id,
        TextEditingController pass,
        String idKey,
        String passKey,
      ) {
        if (id.text.isEmpty && pass.text.isEmpty) {
          id.text = credentials[idKey] ?? '';

          pass.text = credentials[passKey] ?? '';
        }
      }

      restore(
        _shalaIdController,
        _shalaPassController,
        'school_id',
        'school_password',
      );

      restore(
        _staffIdController,
        _staffPassController,
        'staff_id',
        'staff_password',
      );

      restore(
        _rajsimsIdController,
        _rajsimsPassController,
        'sso_id',
        'sso_password',
      );

      setState(() {
        _isLoggedOutState = _hasSavedAccount;

        _currentStep = _isLoggedOutState ? 3 : 0;
      });
    } catch (_) {
      // Manual entry remains available when storage is unavailable.
    } finally {
      if (mounted) setState(() => _credentialsReady = true);
    }
  }

  void _startFactsAutoPlay() {
    _carouselTimer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
      if (_factsPageController.hasClients) {
        int nextPage = _currentFactIndex + 1;

        if (nextPage >= _schoolFacts.length) {
          nextPage = 0;
        }

        _factsPageController.animateToPage(
          nextPage,

          duration: const Duration(milliseconds: 450),

          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();

    _factsPageController.dispose();

    _wizardController.dispose();

    final video = _videoController;
    _videoController = null;
    if (video != null) {
      unawaited(video.dispose().catchError((_) {}));
    }

    _progressController.dispose();

    _shalaIdController.dispose();

    _shalaPassController.dispose();

    _staffIdController.dispose();

    _staffPassController.dispose();

    _rajsimsIdController.dispose();

    _rajsimsPassController.dispose();

    super.dispose();
  }

  Future<void> _performActualLogin() async {
    if (_isLoading ||
        _isApiCallInProgress ||
        _directLoginRunning ||
        _directStaffRunning ||
        _directRajsimsRunning ||
        _directTestRunning)
      return;

    _isApiCallInProgress = true;

    bool completed = false;

    try {
      await _credentialsLoaded;

      if (!mounted) return;

      FocusManager.instance.primaryFocus?.unfocus();

      final schoolId = _shalaIdController.text.trim();

      final schoolPass = _shalaPassController.text;

      final staffId = _staffIdController.text.trim();

      final staffPass = _staffPassController.text;

      final ssoId = _rajsimsIdController.text.trim();

      final ssoPass = _rajsimsPassController.text;

      if ([
        schoolId,
        schoolPass,
        staffId,
        staffPass,
        ssoId,
        ssoPass,
      ].any((v) => v.isEmpty)) {
        _showErrorSnackBar(
          'Teeno portals ki ID aur password bharna zaroori hai.',
        );

        return;
      }

      if (schoolId == staffId) {
        _showErrorSnackBar('Staff ID aur School ID alag honi chahiye.');

        return;
      }

      final hasConsent = await _ensureDataPrivacyConsent(
        schoolId: schoolId,
        staffId: staffId,
        ssoId: ssoId,
      );
      if (!mounted || !hasConsent) {
        return;
      }

      setState(() {
        _isLoading = true;

        _liveStatusMessage = 'Logging in to all three portals...';
      });

      setState(() => _progressKnown = true);

      _progressController.value = 0.0;

      _loginProgressTarget = 0.0;

      _advanceLoginProgress(0.05);

      await SecureStorageService.saveAllPortals(
        shalaId: schoolId,

        shalaPass: schoolPass,

        staffId: staffId,

        staffPass: staffPass,

        rajsimsId: ssoId,

        rajsimsPass: ssoPass,
      );

      final result = await EcosystemService.initialize(
        {
          'school_id': schoolId,

          'school_password': schoolPass,

          'staff_id': staffId,

          'staff_password': staffPass,

          'sso_id': ssoId,

          'sso_password': ssoPass,
        },
        onProgress: (progress, message) {
          if (!mounted || completed) return;

          final next = 0.05 + progress.clamp(0.0, 1.0) * 0.45;

          _advanceLoginProgress(next);

          setState(() => _liveStatusMessage = message);
        },
      );

      if (!mounted) return;

      setState(
        () => _liveStatusMessage =
            result['message']?.toString() ?? 'Login finished.',
      );

      if (result['success'] != true) {
        _showErrorSnackBar(
          result['message']?.toString() ?? 'School login failed.',
        );

        return;
      }

      setState(() {
        _progressKnown = true;
        _liveStatusMessage =
            'Checking leave approvals, attendance and MDM data…';
      });

      _advanceLoginProgress(0.5);

      final preload = DashboardBootstrap.load(
        schoolId,
        fresh: true,
        onProgress: (progress, message) {
          if (!mounted || !_isLoading || completed) return;

          final next = (0.5 + progress.clamp(0.0, 1.0) * 0.45).toDouble();

          _advanceLoginProgress(next);

          setState(() => _liveStatusMessage = message);
        },
      );

      final leavePreload = LeaveApprovalService.fetchLeaveApprovals();

      final mdmPreload = DashboardBootstrap.loadMdm(schoolId, fresh: true);

      final results = await Future.wait([preload, mdmPreload, leavePreload])
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () => [
              {'success': false},
              {'success': false},
              {'success': false},
            ],
          );

      final metrics = results[0];

      final mdmReady = results[1]['success'] == true;

      if (!mounted) return;

      final data = metrics['data'];

      final ready =
          results[2]['success'] == true &&
          mdmReady &&
          metrics['success'] == true &&
          data is Map &&
          data['kpi'] is Map &&
          (data['kpi'] as Map)['success'] != false &&
          data['staff_attendance'] is Map &&
          (data['staff_attendance'] as Map)['success'] != false;

      if (ready) {
        setState(() => _liveStatusMessage = 'Dashboard ready');

        await _progressController.animateTo(1.0);
      } else {
        setState(
          () => _liveStatusMessage =
              'Opening dashboard — data will continue loading',
        );
      }

      final portalStates = EcosystemService.statusSnapshot()['portals'];
      final rajsimsState = portalStates is Map ? portalStates['rajsims'] : null;
      if (rajsimsState is Map && rajsimsState['state'] == 'failed') {
        await _showRajsimsLoginFailure(rajsimsState);
        if (!mounted) return;
      }

      HapticFeedback.mediumImpact();

      if (_isVideoReady && _videoController != null) {
        try {
          await _videoController!.pause();
        } catch (_) {}
      }

      if (!mounted) return;

      completed = true;

      widget.onLoginSuccess(schoolId);
    } catch (_) {
      if (mounted)
        _showErrorSnackBar(
          'Login could not finish. Check saved credentials and backend connection.',
        );
    } finally {
      if (mounted && !completed) {
        setState(() {
          _isLoading = false;

          _isApiCallInProgress = false;
        });

        _progressController.value = 0.0;
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFDC2626),
      ),
    );
  }

  void _onNextPressed() {
    FocusManager.instance.primaryFocus?.unfocus();

    // Step 0 aur 1 par aage badhein, Step 2 (RajSIMS) ya Step 3 (Logged-out Continue) par direct login initiate karein

    if (!_credentialsReady || _isLoading || _isApiCallInProgress) return;

    if (_isLoggedOutState) {
      _performActualLogin();
    } else if (_currentStep < 2) {
      HapticFeedback.selectionClick();

      _wizardController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _performActualLogin();
    }
  }

  void _onBackPressed() {
    if (!_credentialsReady ||
        _isLoading ||
        _isApiCallInProgress ||
        _isLoggedOutState ||
        _currentStep <= 0 ||
        !_wizardController.hasClients)
      return;

    FocusManager.instance.primaryFocus?.unfocus();

    HapticFeedback.selectionClick();

    _wizardController.previousPage(
      duration: const Duration(milliseconds: 350),

      curve: Curves.easeInOutCubic,
    );
  }

  void _onSkipPressed() {
    if (!_credentialsReady || _isLoading || _isApiCallInProgress) return;

    FocusManager.instance.primaryFocus?.unfocus();

    if (_currentStep < 2) {
      HapticFeedback.lightImpact();

      _wizardController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _performActualLogin();
    }
  }

  void _onSetupDifferentAccount() {
    if (!_credentialsReady || _isLoading || _isApiCallInProgress) return;

    HapticFeedback.mediumImpact();

    setState(() {
      _isLoggedOutState = false;

      _currentStep = 0;

      _consentedSchoolId = null;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isLoggedOutState && _wizardController.hasClients) {
        _wizardController.jumpToPage(0);
      }
    });
  }

  // Keep portal log text readable without emoji, keycaps or joiner fragments.

  static String _cleanLoginStatus(String message) {
    final text = String.fromCharCodes(
      message.runes.where((rune) {
        final emoji =
            (rune >= 0x1F000 && rune <= 0x1FAFF) ||
            (rune >= 0x2600 && rune <= 0x27BF) ||
            (rune >= 0x2300 && rune <= 0x23FF) ||
            (rune >= 0x2B00 && rune <= 0x2BFF) ||
            (rune >= 0x2190 && rune <= 0x21FF) ||
            (rune >= 0xFE00 && rune <= 0xFE0F) ||
            rune == 0x200D ||
            rune == 0x20E3 ||
            rune == 0x00A9 ||
            rune == 0x00AE ||
            rune == 0x203C ||
            rune == 0x2049 ||
            rune == 0x2122 ||
            rune == 0x2139 ||
            rune == 0x3030 ||
            rune == 0x303D ||
            rune == 0x3297 ||
            rune == 0x3299 ||
            (rune >= 0xE0020 && rune <= 0xE007F);

        return !emoji;
      }),
    ).replaceAll(RegExp(r'\s+'), ' ').trim();

    return text.isEmpty ? 'Connecting to portals…' : text;
  }

  @override
  Widget build(BuildContext context) {
    if (!_credentialsReady) {
      return const Scaffold(
        backgroundColor: Color(0xFFD3D9E1),
        body: Center(child: CupertinoActivityIndicator()),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,

        statusBarIconBrightness: Brightness.dark,

        statusBarBrightness: Brightness.light,

        systemNavigationBarColor: Colors.transparent,

        systemNavigationBarIconBrightness: Brightness.dark,
      ),

      child: Scaffold(
        extendBodyBehindAppBar: true,

        backgroundColor: Colors.white,

        resizeToAvoidBottomInset: true,

        body: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,

                    end: Alignment.bottomCenter,

                    stops: [0.0, 0.35, 0.75, 1.0],

                    colors: [
                      Colors.white,

                      Colors.white,

                      Color(0xFFE8EEF2),

                      Color(0xFFF9E7BA),
                    ],
                  ),
                ),
              ),
            ),

            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,

                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 528),

                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),

                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 8.0,
                    ),

                    child: Column(
                      mainAxisSize: MainAxisSize.min,

                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        Center(
                          child: Container(
                            height: 195,

                            alignment: Alignment.center,

                            child: AnimatedOpacity(
                              opacity: _showVideo ? 1.0 : 0.0,

                              duration: const Duration(milliseconds: 600),

                              curve: Curves.easeOut,

                              child: _isVideoReady && _videoController != null
                                  ? AspectRatio(
                                      aspectRatio:
                                          _videoController!.value.aspectRatio,

                                      child: VideoPlayer(_videoController!),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                        ),

                        const SizedBox(height: 6),

                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          mainAxisAlignment: MainAxisAlignment.spaceBetween,

                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,

                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          _isLoggedOutState
                                              ? "Welcome back !"
                                              : "Account setup",

                                          style: const TextStyle(
                                            fontSize: 18.5,

                                            height: 1.15,

                                            fontWeight: FontWeight.w600,

                                            color: Color(0xFF0F172A),

                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                      ),
                                      if (!_isLoggedOutState) ...[
                                        const SizedBox(width: 8),
                                        _portalStack(),
                                      ],
                                    ],
                                  ),

                                  const SizedBox(height: 2),

                                  const Text(
                                    "Shaladarpan · Staff Login · RajSIMS",

                                    style: TextStyle(
                                      fontSize: 12.0,

                                      fontWeight: FontWeight.w500,

                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            Image.asset(
                              'assets/icons/app_icon_v1.ico',

                              width: 36,

                              height: 36,

                              fit: BoxFit.contain,

                              errorBuilder: (context, error, stackTrace) =>
                                  Image.asset(
                                    'assets/icons/icon.png',

                                    width: 36,

                                    height: 36,

                                    fit: BoxFit.contain,
                                  ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        Container(
                          width: double.infinity,

                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 14.0,
                          ),

                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.96),

                            borderRadius: BorderRadius.circular(20),

                            border: Border.all(color: Colors.white, width: 1.2),

                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0F172A)
                                    .withValues(alpha: 0.04),

                                blurRadius: 18,

                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),

                          child: Column(
                            mainAxisSize: MainAxisSize.min,

                            children: [
                              SizedBox(
                                height:
                                    155 +
                                    (MediaQuery.textScalerOf(context)
                                                .scale(13) -
                                            13) *
                                        4,

                                child: _isLoggedOutState
                                    ? _buildContinueAsScreen()
                                    : PageView(
                                        controller: _wizardController,

                                        physics:
                                            const NeverScrollableScrollPhysics(),

                                        onPageChanged: (idx) =>
                                            setState(() => _currentStep = idx),

                                        children: [
                                          _buildPortalForm(
                                            title: "1. Shaladarpan",

                                            userController: _shalaIdController,

                                            passController:
                                                _shalaPassController,

                                            userHint: "School NIC ID",
                                          ),

                                          _buildPortalForm(
                                            title: "2. Staff Corner Login",

                                            userController: _staffIdController,

                                            passController:
                                                _staffPassController,

                                            userHint: "Staff NIC-SD ID",
                                          ),

                                          _buildPortalForm(
                                            title: "3. RajSIMS",

                                            userController:
                                                _rajsimsIdController,

                                            passController:
                                                _rajsimsPassController,

                                            userHint: "SSO ID",
                                          ),
                                        ],
                                      ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 10),

                        if (kDebugMode && !kIsWeb) ...[
                          SizedBox(
                            width: double.infinity,
                            height: 40,
                            child: OutlinedButton.icon(
                              onPressed:
                                  _directTestRunning ||
                                      _directLoginRunning ||
                                      _directStaffRunning ||
                                      _directRajsimsRunning ||
                                      _isLoading
                                  ? null
                                  : _testDirectHttp,
                              icon: _directTestRunning
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CupertinoActivityIndicator(),
                                    )
                                  : const Icon(
                                      Icons.wifi_tethering_rounded,
                                      size: 17,
                                    ),
                              label: Text(
                                _directTestRunning
                                    ? 'Testing Connection...'
                                    : 'Test Direct HTTP',
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            height: 40,
                            child: OutlinedButton.icon(
                              onPressed:
                                  (_directLoginRunning ||
                                      _directStaffRunning ||
                                      _directRajsimsRunning ||
                                      _isLoading ||
                                      _directTestRunning)
                                  ? null
                                  : _testDirectLogin,
                              icon: _directLoginRunning
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CupertinoActivityIndicator(),
                                    )
                                  : const Icon(
                                      Icons.lock_open_rounded,
                                      size: 17,
                                    ),
                              label: Text(
                                _directLoginRunning
                                    ? 'Verifying Direct Login...'
                                    : 'Test Direct Mobile Login',
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            height: 40,
                            child: OutlinedButton.icon(
                              onPressed:
                                  _directStaffRunning ||
                                      _directRajsimsRunning ||
                                      _directLoginRunning ||
                                      _directTestRunning ||
                                      _isLoading
                                  ? null
                                  : _testDirectStaffLogin,
                              icon: _directStaffRunning
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CupertinoActivityIndicator(),
                                    )
                                  : const Icon(Icons.badge_outlined, size: 17),
                              label: Text(
                                _directStaffRunning
                                    ? 'Verifying Staff Login...'
                                    : 'Test Direct Staff Login',
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            height: 40,
                            child: OutlinedButton.icon(
                              onPressed:
                                  _directRajsimsRunning ||
                                      _directStaffRunning ||
                                      _directLoginRunning ||
                                      _directTestRunning ||
                                      _isLoading
                                  ? null
                                  : _testDirectRajsimsLogin,
                              icon: _directRajsimsRunning
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CupertinoActivityIndicator(),
                                    )
                                  : const Icon(
                                      Icons.account_balance_outlined,
                                      size: 17,
                                    ),
                              label: Text(
                                _directRajsimsRunning
                                    ? 'Verifying RajSIMS Login...'
                                    : 'Test Direct RajSIMS Login',
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),

                          child: _isLoading
                              ? Container(
                                  key: const ValueKey('progress_state'),

                                  height: 44,

                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14.0,
                                    vertical: 4.0,
                                  ),

                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),

                                    borderRadius: BorderRadius.circular(22),

                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),

                                      width: 1.0,
                                    ),
                                  ),

                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,

                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,

                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                SizedBox(
                                                  width: 24,

                                                  height: 24,

                                                  child: Lottie.asset(
                                                    'assets/icons/Loading (Buffering).json',

                                                    fit: BoxFit.contain,

                                                    errorBuilder: (_, __, ___) =>
                                                        const CupertinoActivityIndicator(
                                                          radius: 9,
                                                        ),
                                                  ),
                                                ),

                                                const SizedBox(width: 8),

                                                Expanded(
                                                  child: Text(
                                                    _cleanLoginStatus(
                                                      _liveStatusMessage,
                                                    ),

                                                    maxLines: 1,

                                                    overflow:
                                                        TextOverflow.ellipsis,

                                                    style: const TextStyle(
                                                      fontSize: 12.0,

                                                      fontWeight:
                                                          FontWeight.w600,

                                                      color: Color(0xFF0F172A),

                                                      letterSpacing: -0.1,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          const SizedBox(width: 8),

                                          AnimatedBuilder(
                                            animation: _progressController,

                                            builder: (context, child) {
                                              final pct =
                                                  (_progressController.value *
                                                          100)
                                                      .clamp(0, 100)
                                                      .toInt();

                                              return Text(
                                                _progressKnown ? "$pct%" : "",

                                                style: const TextStyle(
                                                  fontSize: 11.5,

                                                  fontWeight: FontWeight.w700,

                                                  color: Color(0xFF0F172A),

                                                  fontFeatures: [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 3),

                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          100,
                                        ),

                                        child: SizedBox(
                                          height: 3.5,

                                          width: double.infinity,

                                          child: AnimatedBuilder(
                                            animation: _progressController,

                                            builder: (context, child) {
                                              return LinearProgressIndicator(
                                                value: _progressKnown
                                                    ? _progressController.value
                                                    : null,

                                                backgroundColor: const Color(
                                                  0xFFE2E8F0,
                                                ),

                                                valueColor:
                                                    const AlwaysStoppedAnimation<
                                                      Color
                                                    >(Color(0xFF0F172A)),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : Row(
                                  children: [
                                    if (!_isLoggedOutState &&
                                        _currentStep > 0) ...[
                                      SizedBox(
                                        width: 44,

                                        height: 44,

                                        child: IconButton(
                                          tooltip: 'Back to previous portal',

                                          onPressed: _onBackPressed,

                                          icon: const Icon(
                                            CupertinoIcons.chevron_left,
                                            size: 18,
                                          ),

                                          style: IconButton.styleFrom(
                                            foregroundColor: const Color(
                                              0xFF0F172A,
                                            ),

                                            backgroundColor: Colors.white,

                                            side: const BorderSide(
                                              color: Color(0xFFE2E8F0),
                                            ),
                                          ),
                                        ),
                                      ),

                                      const SizedBox(width: 8),
                                    ],

                                    if (_currentStep < 3 ||
                                        _isLoggedOutState) ...[
                                      Container(
                                        height: 44,

                                        decoration: BoxDecoration(
                                          color: Colors.white,

                                          borderRadius: BorderRadius.circular(
                                            22,
                                          ),

                                          border: Border.all(
                                            color: const Color(0xFFE2E8F0),
                                            width: 1.0,
                                          ),

                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFF0F172A)
                                                  .withValues(alpha: 0.04),

                                              blurRadius: 8,

                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),

                                        child: Material(
                                          color: Colors.transparent,

                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              22,
                                            ),

                                            onTap: _isLoggedOutState
                                                ? _onSetupDifferentAccount
                                                : _onSkipPressed,

                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                  ),

                                              child: Center(
                                                child: Text(
                                                  _isLoggedOutState
                                                      ? "Setup different account"
                                                      : "Skip",

                                                  style: const TextStyle(
                                                    fontSize: 12.0,

                                                    fontWeight: FontWeight.w600,

                                                    color: Color(0xFF475569),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                      const SizedBox(width: 8),
                                    ],

                                    Expanded(
                                      child: Container(
                                        key: const ValueKey('button_state'),

                                        height: 44,

                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            22,
                                          ),

                                          gradient: const LinearGradient(
                                            begin: Alignment.topCenter,

                                            end: Alignment.bottomCenter,

                                            colors: [
                                              Color(0xFF27272A),

                                              Color(0xFF18181B),

                                              Color(0xFF000000),
                                            ],
                                          ),

                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.28,
                                              ),

                                              blurRadius: 10,

                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),

                                        child: Material(
                                          color: Colors.transparent,

                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              22,
                                            ),

                                            splashColor: Colors.transparent,

                                            highlightColor: Colors.white
                                                .withValues(alpha: 0.06),

                                            onTap: _onNextPressed,

                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                  ),

                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,

                                                children: [
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          left: 6.0,
                                                        ),

                                                    child: Text(
                                                      _isLoggedOutState
                                                          ? "Continue as"
                                                          : (_currentStep == 2
                                                                ? "Finish & Launch All"
                                                                : "Next Portal"),

                                                      style: const TextStyle(
                                                        fontSize: 14.0,

                                                        fontWeight:
                                                            FontWeight.w600,

                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ),

                                                  Container(
                                                    width: 26,

                                                    height: 26,

                                                    decoration:
                                                        const BoxDecoration(
                                                          color: Colors.white,

                                                          shape:
                                                              BoxShape.circle,
                                                        ),

                                                    child: const Icon(
                                                      Icons
                                                          .arrow_forward_rounded,

                                                      color: Colors.black,

                                                      size: 15,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),

                        const SizedBox(height: 10),

                        SizedBox(
                          height: 72,
                          width: double.infinity,
                          child: Container(
                            width: double.infinity,

                            height: 72,

                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),

                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.95),

                              borderRadius: BorderRadius.circular(16),

                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                                width: 1.0,
                              ),

                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0F172A)
                                      .withValues(alpha: 0.03),

                                  blurRadius: 10,

                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),

                            child: Column(
                              children: [
                                Expanded(
                                  child: PageView.builder(
                                    controller: _factsPageController,

                                    onPageChanged: (index) {
                                      setState(() => _currentFactIndex = index);
                                    },

                                    itemCount: _schoolFacts.length,

                                    itemBuilder: (context, index) {
                                      final fact = _schoolFacts[index];

                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,

                                        mainAxisAlignment:
                                            MainAxisAlignment.center,

                                        children: [
                                          Text(
                                            fact["title"]!,

                                            style: const TextStyle(
                                              fontSize: 12.0,

                                              fontWeight: FontWeight.w600,

                                              color: Color(0xFF1E293B),
                                            ),
                                          ),

                                          const SizedBox(height: 1),

                                          Text(
                                            fact["subtitle"]!,

                                            maxLines: 2,

                                            overflow: TextOverflow.ellipsis,

                                            style: const TextStyle(
                                              fontSize: 10.8,

                                              height: 1.25,

                                              color: Color(0xFF475569),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),

                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,

                                  children: List.generate(
                                    _schoolFacts.length,

                                    (dotIndex) => AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 250,
                                      ),

                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 2.5,
                                      ),

                                      width: _currentFactIndex == dotIndex
                                          ? 14
                                          : 4,

                                      height: 3.5,

                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(2),

                                        color: _currentFactIndex == dotIndex
                                            ? const Color(0xFF0F172A)
                                            : const Color(0xFF94A3B8)
                                                  .withValues(alpha: 0.4),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        const Center(
                          child: Text.rich(
                            TextSpan(
                              text: "Creator & Developer\n",

                              style: TextStyle(
                                fontSize: 11.0,

                                fontWeight: FontWeight.w600,

                                color: Color(0xFF1E293B),

                                height: 1.35,
                              ),

                              children: [
                                TextSpan(
                                  text: "Ripudaman Singh Jhala",

                                  style: TextStyle(
                                    fontWeight: FontWeight.normal,

                                    color: Color(0xFF475569),
                                  ),
                                ),
                              ],
                            ),

                            textAlign: TextAlign.center,
                          ),
                        ),

                        const SizedBox(height: 8),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,

                          children: [
                            _buildContactIcon(
                              'assets/icons/support.png',
                              () {},
                            ),

                            const SizedBox(width: 16),

                            _buildContactIcon(
                              'assets/icons/telephone.png',
                              () {},
                            ),

                            const SizedBox(width: 16),

                            _buildContactIcon('assets/icons/email.png', () {}),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _portalStack() => SizedBox(
    width: 68,
    height: 30,
    child: Stack(
      children: [
        for (final entry in [
          'assets/icons/shaladarpan_logo.png',
          'assets/icons/staff_logo.png',
          'assets/icons/rajsims.png',
        ].asMap().entries)
          Positioned(
            left: entry.key * 19,
            child: Container(
              width: 30,
              height: 30,
              padding: const EdgeInsets.all(5),

              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),

              child: Image.asset(
                entry.value,
                fit: BoxFit.contain,

                errorBuilder: (context, error, stack) => Image.asset(
                  [
                    'assets/icons/shaladarpan.png',
                    'assets/icons/staff.png',
                    'assets/icons/rajsims.png',
                  ][entry.key],
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _buildPortalForm({
    required String title,

    required TextEditingController userController,

    required TextEditingController passController,

    required String userHint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      mainAxisAlignment: MainAxisAlignment.center,

      children: [
        Row(
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              size: 17,
              color: Color(0xFF1E293B),
            ),

            const SizedBox(width: 8),

            Text(
              title,

              style: const TextStyle(
                fontSize: 14.0,

                fontWeight: FontWeight.w600,

                color: Color(0xFF1E293B),
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        TextField(
          controller: userController,

          enabled: !_isLoading,
          autocorrect: false,
          enableSuggestions: false,

          style: const TextStyle(
            fontFamily: 'PlusJakartaSans',
            fontSize: 13.0,
            fontWeight: FontWeight.w500,
            color: Color(0xFF111827),
          ),

          decoration: InputDecoration(
            hintText: userHint,

            hintStyle: const TextStyle(
              color: Color(0xFF475569),

              fontSize: 12.5,

              fontWeight: FontWeight.w500,
            ),

            prefixIcon: Padding(
              padding: const EdgeInsets.all(12.0),

              child: Image.asset(
                'assets/icons/username.png',

                width: 16,

                height: 16,

                fit: BoxFit.contain,

                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.person_outline,
                  size: 18,
                  color: Color(0xFF64748B),
                ),
              ),
            ),

            filled: true,

            fillColor: Colors.white,

            contentPadding: const EdgeInsets.symmetric(vertical: 10),

            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),

              borderSide: const BorderSide(
                color: Color(0xFFE2E8F0),
                width: 1.0,
              ),
            ),

            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),

              borderSide: const BorderSide(
                color: Color(0xFFE2E8F0),
                width: 1.0,
              ),
            ),

            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),

              borderSide: const BorderSide(
                color: Color(0xFF2563EB),
                width: 1.2,
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        TextField(
          controller: passController,

          enabled: !_isLoading,

          obscureText: !(_passwordVisible[passController] ?? false),

          autocorrect: false,
          enableSuggestions: false,

          style: const TextStyle(
            fontFamily: 'PlusJakartaSans',
            fontSize: 13.0,
            fontWeight: FontWeight.w500,
            color: Color(0xFF111827),
          ),

          decoration: InputDecoration(
            hintText: "Password",

            suffixIcon: IconButton(
              tooltip: _passwordVisible[passController] == true
                  ? 'Hide password'
                  : 'Show password',

              onPressed: _isLoading
                  ? null
                  : () => setState(
                      () => _passwordVisible[passController] =
                          !(_passwordVisible[passController] ?? false),
                    ),

              icon: Icon(
                _passwordVisible[passController] == true
                    ? CupertinoIcons.eye_slash
                    : CupertinoIcons.eye,
                size: 18,
                color: const Color(0xFF64748B),
              ),
            ),

            hintStyle: const TextStyle(
              color: Color(0xFF475569),

              fontSize: 12.5,

              fontWeight: FontWeight.w500,
            ),

            prefixIcon: Padding(
              padding: const EdgeInsets.all(12.0),

              child: Image.asset(
                'assets/icons/password.png',

                width: 16,

                height: 16,

                fit: BoxFit.contain,

                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.lock_outline,
                  size: 18,
                  color: Color(0xFF64748B),
                ),
              ),
            ),

            filled: true,

            fillColor: Colors.white,

            contentPadding: const EdgeInsets.symmetric(vertical: 10),

            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),

              borderSide: const BorderSide(
                color: Color(0xFFE2E8F0),
                width: 1.0,
              ),
            ),

            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),

              borderSide: const BorderSide(
                color: Color(0xFFE2E8F0),
                width: 1.0,
              ),
            ),

            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),

              borderSide: const BorderSide(
                color: Color(0xFF2563EB),
                width: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContinueAsScreen() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,

      mainAxisAlignment: MainAxisAlignment.center,

      children: [
        Container(
          width: 52,

          height: 52,

          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),

            shape: BoxShape.circle,

            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),

                blurRadius: 6,

                offset: const Offset(0, 2),
              ),
            ],
          ),

          child: AccountAvatar(
            schoolId: _shalaIdController.text.trim(),
            size: 52,
          ),
        ),

        const SizedBox(height: 10),

        Text(
          "Continue as ID: ${_shalaIdController.text}",

          style: const TextStyle(
            fontSize: 14.5,

            fontWeight: FontWeight.w700,

            color: Color(0xFF0F172A),
          ),
        ),

        const SizedBox(height: 3),

        const Text(
          "Saved securely on this device",

          style: TextStyle(fontSize: 11.0, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  Widget _buildContactIcon(String assetPath, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,

      borderRadius: BorderRadius.circular(20),

      child: Container(
        width: 36,

        height: 36,

        padding: const EdgeInsets.all(8.5),

        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),

          shape: BoxShape.circle,

          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),

          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),

              blurRadius: 8,

              offset: const Offset(0, 2),
            ),
          ],
        ),

        child: Image.asset(
          assetPath,

          fit: BoxFit.contain,

          errorBuilder: (context, error, stackTrace) => const Icon(
            Icons.help_outline_rounded,

            size: 16,

            color: Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Future<bool> _ensureDataPrivacyConsent({
    required String schoolId,
    required String staffId,
    required String ssoId,
  }) async {
    final trimmedSchool = schoolId.trim();
    final consentKey = 'data_privacy_consent_v1_$trimmedSchool';
    if (_consentedSchoolId == trimmedSchool) {
      return true;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(consentKey) == true) {
        _consentedSchoolId = trimmedSchool;
        return true;
      }
    } catch (_) {}

    if (!mounted) return false;

    final accepted = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      // Transparent barrier + identical gradient background = the login
      // content simply cross-fades into the consent content.
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (dialogCtx, anim1, anim2) {
        return _DataPrivacyConsentScreen(
          schoolId: schoolId,
          staffId: staffId,
          ssoId: ssoId,
          onAccept: () => Navigator.of(dialogCtx).pop(true),
          onDecline: () => Navigator.of(dialogCtx).pop(false),
        );
      },
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: anim,
            curve: Curves.easeInOut,
            reverseCurve: Curves.easeInOut,
          ),
          child: child,
        );
      },
    );

    if (accepted == true) {
      _consentedSchoolId = trimmedSchool;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(consentKey, true);
        await prefs.setString(
          'data_privacy_consent_timestamp_$trimmedSchool',
          DateTime.now().toIso8601String(),
        );
      } catch (_) {}
      return true;
    }

    return false;
  }
}

class _DataPrivacyConsentScreen extends StatefulWidget {
  final String schoolId;
  final String staffId;
  final String ssoId;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _DataPrivacyConsentScreen({
    required this.schoolId,
    required this.staffId,
    required this.ssoId,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<_DataPrivacyConsentScreen> createState() =>
      _DataPrivacyConsentScreenState();
}

class _DataPrivacyConsentScreenState extends State<_DataPrivacyConsentScreen>
    with SingleTickerProviderStateMixin {
  static const String _font = 'PlusJakartaSans';
  static const Color _ink = Color(0xFF0F172A);
  static const Color _body = Color(0xFF1E293B);
  static const Color _blue = Color(0xFF2563EB);

  late final AnimationController _intro;
  late final Animation<double> _fadeTop;
  late final Animation<double> _fadeText;
  late final Animation<double> _fadeActions;
  late final TapGestureRecognizer _learnMoreTap;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    // Soft staggered fade-in only (no sliding), so it feels like the
    // other setup screens instead of a panel dropping in.
    Animation<double> fadeAt(double start, double end) => CurvedAnimation(
      parent: _intro,
      curve: Interval(start, end, curve: Curves.easeInOut),
    );
    _fadeTop = fadeAt(0.0, 0.55);
    _fadeText = fadeAt(0.15, 0.75);
    _fadeActions = fadeAt(0.35, 1.0);
    _learnMoreTap = TapGestureRecognizer()..onTap = _showLearnMoreSheet;
  }

  @override
  void dispose() {
    _learnMoreTap.dispose();
    _intro.dispose();
    super.dispose();
  }

  void _showLearnMoreSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 520),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'How this app uses & protects your data',
                  style: TextStyle(
                    fontFamily: _font,
                    fontSize: 17.5,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 14),
                _buildDetailItem(
                  icon: Icons.verified_user_outlined,
                  title: 'Portal Authentication & Session Sync',
                  subtitle:
                      'Your ShalaDarpan (${widget.schoolId}), Staff Corner (${widget.staffId}), and RajSIMS (${widget.ssoId}) credentials are used to authenticate your official sessions and load dashboard metrics.',
                ),
                const SizedBox(height: 12),
                _buildDetailItem(
                  icon: Icons.bug_report_outlined,
                  title: 'Beta Testing & Diagnostics',
                  subtitle:
                      'During user testing, account identifiers, setup details, and portal response logs are used to verify synchronization accuracy and resolve login or attendance issues.',
                ),
                const SizedBox(height: 12),
                _buildDetailItem(
                  icon: Icons.lock_outline_rounded,
                  title: 'Device Security & Control',
                  subtitle:
                      'Credentials are stored in encrypted device storage. You can switch accounts or clear your saved setup anytime from the login screen.',
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(sheetCtx).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _ink,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(23),
                      ),
                    ),
                    child: const Text(
                      'Got it',
                      style: TextStyle(
                        fontFamily: _font,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _buildDetailItem({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: _blue, size: 19),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: _font,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontFamily: _font,
                  fontSize: 12,
                  height: 1.4,
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryButton(double height, double fontSize) {
    final radius = height / 2;
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF27272A), Color(0xFF18181B), Color(0xFF000000)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.26),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          splashColor: Colors.transparent,
          highlightColor: Colors.white.withValues(alpha: 0.06),
          onTap: () {
            HapticFeedback.mediumImpact();
            widget.onAccept();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const SizedBox(width: 30),
                Expanded(
                  child: Text(
                    'Yes, agree & continue',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: _font,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.black,
                    size: 17,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: MediaQuery.withClampedTextScaling(
        minScaleFactor: 1.0,
        maxScaleFactor: 1.2,
        child: Scaffold(
          backgroundColor: Colors.white,
          body: Stack(
            children: [
              // Identical to the login screen background, so the switch
              // between the two is a pure cross-fade of the content.
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.0, 0.35, 0.75, 1.0],
                      colors: [
                        Colors.white,
                        Colors.white,
                        Color(0xFFE8EEF2),
                        Color(0xFFF9E7BA),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final screenW = constraints.maxWidth;
                    final screenH = constraints.maxHeight;

                    // Sizes follow the rest of the app (18.5 headings,
                    // 12-14 body, 44-46 high pill buttons), scaled a little
                    // on tablets / desktop.
                    final isWide = screenW >= 600;
                    final isShort = screenH < 620;
                    final hPad = isWide ? 32.0 : 24.0;

                    final illoW = isShort ? 88.0 : (isWide ? 132.0 : 108.0);
                    final titleSize = isWide ? 30.0 : (isShort ? 23.0 : 26.0);
                    final introSize = isWide ? 15.0 : 13.5;
                    final questionSize = isWide ? 19.5 : 17.0;
                    final bodySize = isWide ? 14.0 : 12.8;
                    final buttonH = isWide ? 50.0 : 46.0;
                    final buttonFont = isWide ? 15.5 : 14.5;

                    final bodyStyle = TextStyle(
                      fontFamily: _font,
                      fontSize: bodySize,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                      color: _body,
                    );
                    final boldStyle = bodyStyle.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    );
                    final linkStyle = bodyStyle.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _blue,
                    );

                    return Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 528),
                        child: Column(
                          children: [
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                hPad - 6,
                                10,
                                hPad,
                                0,
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FadeTransition(
                                  opacity: _fadeTop,
                                  child: SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: IconButton(
                                      tooltip: 'Close',
                                      onPressed: () {
                                        HapticFeedback.lightImpact();
                                        widget.onDecline();
                                      },
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 19,
                                      ),
                                      style: IconButton.styleFrom(
                                        foregroundColor: _ink,
                                        backgroundColor: Colors.white
                                            .withValues(alpha: 0.95),
                                        side: const BorderSide(
                                          color: Color(0xFFE2E8F0),
                                        ),
                                        shadowColor: _ink.withValues(
                                          alpha: 0.08,
                                        ),
                                        elevation: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, box) {
                                  return SingleChildScrollView(
                                    physics: const ClampingScrollPhysics(),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: hPad,
                                      vertical: 8,
                                    ),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minHeight: box.maxHeight - 16,
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          FadeTransition(
                                            opacity: _fadeTop,
                                            child: Column(
                                              children: [
                                                SizedBox(
                                                  width: illoW,
                                                  height:
                                                      illoW /
                                                      _PrivacyHandshakePainter
                                                          .aspect,
                                                  child: const CustomPaint(
                                                    painter:
                                                        _PrivacyHandshakePainter(),
                                                  ),
                                                ),
                                                SizedBox(
                                                  height: isShort ? 14 : 20,
                                                ),
                                                Semantics(
                                                  header: true,
                                                  child: Text(
                                                    'Data & Privacy',
                                                    textAlign:
                                                        TextAlign.center,
                                                    style: TextStyle(
                                                      fontFamily: _font,
                                                      fontSize: titleSize,
                                                      height: 1.15,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: _ink,
                                                      letterSpacing: -0.5,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(height: isShort ? 14 : 26),
                                          FadeTransition(
                                            opacity: _fadeText,
                                            child: Column(
                                              children: [
                                                Text(
                                                  'We care about your privacy and data security. We keep this app reliable during testing by verifying your portal setup.',
                                                  textAlign: TextAlign.center,
                                                  style: bodyStyle.copyWith(
                                                    fontSize: introSize,
                                                  ),
                                                ),
                                                SizedBox(
                                                  height: isShort ? 14 : 22,
                                                ),
                                                Text(
                                                  'Can we continue to use your account & credential details to sync portals for you?',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontFamily: _font,
                                                    fontSize: questionSize,
                                                    height: 1.3,
                                                    fontWeight:
                                                        FontWeight.w800,
                                                    color: _ink,
                                                    letterSpacing: -0.2,
                                                  ),
                                                ),
                                                SizedBox(
                                                  height: isShort ? 12 : 18,
                                                ),
                                                Text.rich(
                                                  TextSpan(
                                                    style: bodyStyle,
                                                    children: [
                                                      const TextSpan(
                                                        text:
                                                            'You can change or clear your saved account ',
                                                      ),
                                                      TextSpan(
                                                        text:
                                                            'anytime on the login screen',
                                                        style: boldStyle,
                                                      ),
                                                      const TextSpan(
                                                        text:
                                                            '. During testing, account identifiers and credential details are used to authenticate ',
                                                      ),
                                                      TextSpan(
                                                        text:
                                                            'ShalaDarpan, Staff Corner, and RajSIMS',
                                                        style: boldStyle,
                                                      ),
                                                      const TextSpan(
                                                        text: ' sessions. ',
                                                      ),
                                                      TextSpan(
                                                        text:
                                                            'Learn how this app collects and uses data.',
                                                        style: linkStyle,
                                                        recognizer:
                                                            _learnMoreTap,
                                                      ),
                                                    ],
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            FadeTransition(
                              opacity: _fadeActions,
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  hPad,
                                  8,
                                  hPad,
                                  14,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildPrimaryButton(buttonH, buttonFont),
                                    const SizedBox(height: 4),
                                    TextButton(
                                      onPressed: () {
                                        HapticFeedback.lightImpact();
                                        widget.onDecline();
                                      },
                                      style: TextButton.styleFrom(
                                        foregroundColor: _blue,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 12,
                                        ),
                                      ),
                                      child: Text(
                                        'No, go back to setup',
                                        style: TextStyle(
                                          fontFamily: _font,
                                          fontSize: buttonFont - 0.5,
                                          fontWeight: FontWeight.w600,
                                          color: _blue,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Flat two-tone handshake illustration, traced from the reference design.
/// Draw it inside a box with aspect ratio 1.2556 : 1 (width : height).
class _PrivacyHandshakePainter extends CustomPainter {
  const _PrivacyHandshakePainter();

  static const double aspect = 1.2556;
  static const Color _dark = Color(0xFF4575EC);
  static const Color _light = Color(0xFFAAC8F6);

  static const List<Offset> _darkBody = <Offset>[
    Offset(0.5303, 0.8906), Offset(0.4782, 0.8958), Offset(0.4110, 0.8812),
    Offset(0.3229, 0.8341), Offset(0.3159, 0.8502), Offset(0.3164, 0.9691),
    Offset(0.3040, 0.9946), Offset(0.0227, 0.9958), Offset(0.0078, 0.9893),
    Offset(-0.0003, 0.9727), Offset(-0.0004, 0.8585), Offset(0.0218, 0.6468),
    Offset(0.0496, 0.5303), Offset(0.0860, 0.4471), Offset(0.1203, 0.4036),
    Offset(0.1676, 0.3845), Offset(0.2131, 0.3869), Offset(0.2509, 0.4102),
    Offset(0.2851, 0.4625), Offset(0.3174, 0.5850), Offset(0.3561, 0.6709),
    Offset(0.4063, 0.7206), Offset(0.4797, 0.7479), Offset(0.4865, 0.7586),
    Offset(0.4915, 0.7974), Offset(0.5319, 0.8121), Offset(0.5354, 0.8692),
  ];

  static const List<Offset> _lightBody = <Offset>[
    Offset(0.9983, 0.9822), Offset(0.9896, 0.9953), Offset(0.9763, 1.0005),
    Offset(0.6903, 0.9991), Offset(0.6806, 0.9810), Offset(0.6812, 0.8763),
    Offset(0.6759, 0.8419), Offset(0.6676, 0.8397), Offset(0.5938, 0.8809),
    Offset(0.5407, 0.8931), Offset(0.5350, 0.8835), Offset(0.5336, 0.8157),
    Offset(0.4911, 0.7872), Offset(0.4859, 0.7491), Offset(0.4934, 0.7428),
    Offset(0.5455, 0.7387), Offset(0.5919, 0.7181), Offset(0.6344, 0.6766),
    Offset(0.6610, 0.6337), Offset(0.7149, 0.4507), Offset(0.7443, 0.4067),
    Offset(0.7973, 0.3815), Offset(0.8523, 0.3880), Offset(0.8835, 0.4046),
    Offset(0.9064, 0.4328), Offset(0.9342, 0.4816), Offset(0.9577, 0.5422),
    Offset(0.9792, 0.6433), Offset(1.0004, 0.8704),
  ];

  static Path _smoothClosed(List<Offset> pts, double w, double h) {
    Offset s(Offset o) => Offset(o.dx * w, o.dy * h);
    Offset mid(Offset a, Offset b) =>
        Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    final n = pts.length;
    final path = Path();
    final start = mid(s(pts[n - 1]), s(pts[0]));
    path.moveTo(start.dx, start.dy);
    for (var i = 0; i < n; i++) {
      final c = s(pts[i]);
      final e = mid(c, s(pts[(i + 1) % n]));
      path.quadraticBezierTo(c.dx, c.dy, e.dx, e.dy);
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final darkPaint = Paint()
      ..color = _dark
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final lightPaint = Paint()
      ..color = _light
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final headR = w * 0.1319;

    canvas.drawPath(_smoothClosed(_darkBody, w, h), darkPaint);
    canvas.drawCircle(Offset(w * 0.2211, h * 0.1653), headR, darkPaint);

    canvas.drawPath(_smoothClosed(_lightBody, w, h), lightPaint);
    canvas.drawCircle(Offset(w * 0.7817, h * 0.1665), headR, lightPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}