import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:video_player/video_player.dart';
import 'dashboard.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const RajShalaMobileApp());
}

class RajShalaMobileApp extends StatelessWidget {
  const RajShalaMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Shaladarpan Automation',
      theme: ThemeData(
        fontFamily: 'Segoe UI',
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFD3D9E1),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
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
  bool _isAuthenticated = false;
  String _schoolId = "480481";
  late AnimationController _fadeController;
  final GlobalKey<LoginDesignScreenState> _loginKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void login(String schoolId) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _schoolId = schoolId.isNotEmpty ? schoolId : "480481";
      _isAuthenticated = true;
    });
    _fadeController.forward(from: 0.0);
  }

  void logout() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _fadeController.reverse();
    if (mounted) {
      setState(() {
        _isAuthenticated = false;
      });
      _loginKey.currentState?.resetToDefaultState();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD3D9E1),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: _isAuthenticated,
            child: TickerMode(
              enabled: !_isAuthenticated,
              child: LoginDesignScreen(
                key: _loginKey,
                onLoginSuccess: login,
              ),
            ),
          ),
          if (_isAuthenticated)
            FadeTransition(
              opacity: _fadeController,
              child: DashboardScreen(
                schoolId: _schoolId,
                onLogoutRequested: logout,
              ),
            ),
        ],
      ),
    );
  }
}

class LoginDesignScreen extends StatefulWidget {
  final ValueChanged<String> onLoginSuccess;
  const LoginDesignScreen({super.key, required this.onLoginSuccess});

  @override
  LoginDesignScreenState createState() => LoginDesignScreenState();
}

class LoginDesignScreenState extends State<LoginDesignScreen>
    with SingleTickerProviderStateMixin {
  final _userController = TextEditingController(text: "480481");
  final _passController = TextEditingController(text: "Admin@123");
  bool _isLoading = false;
  late AnimationController _progressController;
  late VideoPlayerController _videoController;
  
  bool _isVideoReady = false;
  bool _showVideo = false;

  late final PageController _factsPageController;
  Timer? _carouselTimer;
  int _currentFactIndex = 0;

  final List<Map<String, String>> _schoolFacts = [
    {
      "title": "Decline in Attendance",
      "subtitle": "Lower employee attendance recorded last year, likely caused by year-end fatigue.",
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
    });
    _progressController.stop();
    _progressController.value = 0.0;
    if (_isVideoReady && !_videoController.value.isPlaying) {
      _videoController.play();
    }
  }

  @override
  void initState() {
    super.initState();

    _videoController = VideoPlayerController.asset(
      'assets/images/fpo@1x.mp4',
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    )..initialize().then((_) {
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
      duration: const Duration(milliseconds: 1800),
    );

    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        if (_isVideoReady && _videoController.value.isPlaying) {
          _videoController.pause();
        }
        widget.onLoginSuccess(_userController.text.trim());
      }
    });

    _factsPageController = PageController();
    _startFactsAutoPlay();
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
    _videoController.dispose();
    _progressController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  void _onLoginPressed() {
    if (_isLoading) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _isLoading = true);
    _progressController.forward(from: 0.0);
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
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
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
                                    aspectRatio: _videoController.value.aspectRatio,
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
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Shaladarpan\nAutomation",
                                style: TextStyle(
                                  fontSize: 18.5,
                                  height: 1.15,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0F172A),
                                  letterSpacing: -0.2,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                "Understanding Your Work!",
                                style: TextStyle(
                                  fontSize: 12.0,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ],
                          ),
                          Image.asset(
                            'assets/icons/app_icon_v1.ico',
                            width: 36,
                            height: 36,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => Image.asset(
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
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.96),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white, width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0F172A).withOpacity(0.04),
                              blurRadius: 18,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.lock_outline_rounded, size: 17, color: Color(0xFF1E293B)),
                                SizedBox(width: 8),
                                Text(
                                  "Login to Shaladarpan",
                                  style: TextStyle(
                                    fontSize: 14.0,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _userController,
                              style: const TextStyle(fontSize: 13.0, color: Color(0xFF0F172A)),
                              decoration: InputDecoration(
                                hintText: "School ID / Username",
                                hintStyle: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                                prefixIcon: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Image.asset(
                                    'assets/icons/username.png',
                                    width: 16,
                                    height: 16,
                                    errorBuilder: (context, error, stackTrace) =>
                                        const Icon(Icons.person_outline, size: 18, color: Color(0xFF64748B)),
                                  ),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _passController,
                              obscureText: true,
                              style: const TextStyle(fontSize: 13.0, color: Color(0xFF0F172A)),
                              decoration: InputDecoration(
                                hintText: "Password",
                                hintStyle: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                                prefixIcon: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Image.asset(
                                    'assets/icons/password.png',
                                    width: 16,
                                    height: 16,
                                    errorBuilder: (context, error, stackTrace) =>
                                        const Icon(Icons.lock_outline, size: 18, color: Color(0xFF64748B)),
                                  ),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  splashFactory: NoSplash.splashFactory,
                                ),
                                onPressed: () {},
                                child: const Text(
                                  "Manage saved accounts",
                                  style: TextStyle(
                                    color: Color(0xFF1E40AF),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: _isLoading
                                  ? Container(
                                      key: const ValueKey('progress_state'),
                                      height: 44,
                                      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 4.0),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: const Color(0xFFE2E8F0),
                                          width: 1.0,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  SizedBox(
                                                    width: 26,
                                                    height: 26,
                                                    child: Lottie.asset(
                                                      'assets/icons/Loading (Buffering).json',
                                                      fit: BoxFit.contain,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  const Text(
                                                    "Authenticating...",
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      fontWeight: FontWeight.w600,
                                                      color: Color(0xFF0F172A),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              AnimatedBuilder(
                                                animation: _progressController,
                                                builder: (context, child) {
                                                  return Text(
                                                    "${(_progressController.value * 100).clamp(0, 100).toInt()}%",
                                                    style: const TextStyle(
                                                      fontSize: 11.5,
                                                      fontWeight: FontWeight.w600,
                                                      color: Color(0xFF475569),
                                                      fontFeatures: [FontFeature.tabularFigures()],
                                                    ),
                                                  );
                                                },
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Container(
                                              height: 4,
                                              width: double.infinity,
                                              color: const Color(0xFFE2E8F0),
                                              child: AnimatedBuilder(
                                                animation: _progressController,
                                                builder: (context, child) {
                                                  return FractionallySizedBox(
                                                    alignment: Alignment.centerLeft,
                                                    widthFactor: _progressController.value.clamp(0.05, 1.0),
                                                    child: Container(
                                                      color: const Color(0xFF0F172A),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : Container(
                                      key: const ValueKey('button_state'),
                                      height: 44,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(22),
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
                                            color: Colors.black.withOpacity(0.28),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(22),
                                          splashColor: Colors.transparent,
                                          highlightColor: Colors.white.withOpacity(0.06),
                                          onTap: _onLoginPressed,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 14),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                const Padding(
                                                  padding: EdgeInsets.only(left: 6.0),
                                                  child: Text(
                                                    "Login",
                                                    style: TextStyle(
                                                      fontSize: 14.0,
                                                      fontWeight: FontWeight.w600,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  width: 26,
                                                  height: 26,
                                                  decoration: const BoxDecoration(
                                                    color: Colors.white,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(
                                                    Icons.arrow_forward_rounded,
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

                      // ====================================================
                      // FIXED FACTS CARD: OPAQUE SURFACE (Zero Zebra Pattern)
                      // ====================================================
                      Container(
                        width: double.infinity,
                        height: 72,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95), // Solves gradient banding/zebra lines
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0F172A).withOpacity(0.03),
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
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
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
                                  duration: const Duration(milliseconds: 250),
                                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                                  width: _currentFactIndex == dotIndex ? 14 : 4,
                                  height: 3.5,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(2),
                                    color: _currentFactIndex == dotIndex
                                        ? const Color(0xFF0F172A)
                                        : const Color(0xFF94A3B8).withOpacity(0.4),
                                  ),
                                ),
                              ),
                            ),
                          ],
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
                          _buildContactIcon('assets/icons/support.png', () {}),
                          const SizedBox(width: 16),
                          _buildContactIcon('assets/icons/telephone.png', () {}),
                          const SizedBox(width: 16),
                          _buildContactIcon('assets/icons/email.png', () {}),
                        ],
                      ),
                      const SizedBox(height: 8),
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

  Widget _buildContactIcon(String assetPath, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        padding: const EdgeInsets.all(8.5),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withOpacity(0.04),
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