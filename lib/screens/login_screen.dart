import 'package:shaladarpan/experiments/direct_school_session.dart';
import 'package:shaladarpan/services/portals/shaladarpan/student_service.dart';
import 'package:lottie/lottie.dart';

import 'package:shaladarpan/widgets/account_avatar.dart';

// C:\shaladarpan_app\lib\screens\login_screen.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shaladarpan/experiments/direct_portal_probe.dart';
import 'package:shaladarpan/experiments/direct_portal_auth.dart';
import 'package:shaladarpan/services/portals/staff_login/direct/staff_runtime.dart';
import 'package:shaladarpan/services/portals/rajsims/direct/rajsims_runtime.dart';

import 'dart:ui';

import 'package:flutter/cupertino.dart';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'package:video_player/video_player.dart';

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
      final profile = runtime.registry.auth.getUserInfo();
      final message =
          result['message']?.toString() ??
          result['code']?.toString() ??
          'RajSIMS login was not verified.';
      final details = result['diagnostics'];
      final diagnosticText = details is Map
          ? '\n\nTechnical response details:\n${const JsonEncoder.withIndent('  ').convert(details)}'
          : '';
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
                  : message + diagnosticText,
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

  late VideoPlayerController _videoController;

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

    if (_isVideoReady && !_videoController.value.isPlaying) {
      _videoController.play();
    }
  }

  @override
  void initState() {
    super.initState();

    _credentialsLoaded = _loadSavedCredentials();

    _videoController =
        VideoPlayerController.asset(
            'assets/images/fpo@1x.mp4',

            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          )
          ..initialize().then((_) {
            if (mounted) {
              _videoController.setLooping(true);

              _videoController.setVolume(0.0);

              _videoController.play();

              setState(() => _isVideoReady = true);

              Future.delayed(const Duration(milliseconds: 60), () {
                if (mounted) setState(() => _showVideo = true);
              });
            }
          });

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

    _videoController.dispose();

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

      HapticFeedback.mediumImpact();

      if (_isVideoReady) await _videoController.pause();

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

                              child: _isVideoReady
                                  ? AspectRatio(
                                      aspectRatio:
                                          _videoController.value.aspectRatio,

                                      child: VideoPlayer(_videoController),
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
}
