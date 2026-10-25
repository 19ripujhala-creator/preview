import 'package:shaladarpan/widgets/page_content_motion.dart';
import 'package:shaladarpan/widgets/page_transitions.dart';
import 'package:shaladarpan/widgets/route_completion.dart';
import 'package:shaladarpan/widgets/adaptive_layout.dart';
import 'package:shaladarpan/services/core/account_identity.dart';

import 'dart:async';
import 'dart:convert';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shaladarpan/services/core/profile_photo_store.dart';

import 'report_issue_screen.dart';

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shaladarpan/services/core/account_service.dart';
import 'package:shaladarpan/services/core/secure_storage_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/dashboard_bootstrap.dart';

const String kAppFont = 'PlusJakartaSans';
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _border = Color(0xFFE2E8F0);

class AccountTabView extends StatefulWidget {
  final String schoolId;
  final VoidCallback onLogoutRequested;
  const AccountTabView({
    super.key,
    required this.schoolId,
    required this.onLogoutRequested,
  });
  @override
  State<AccountTabView> createState() => _AccountTabViewState();
}

class _AccountTabViewState extends State<AccountTabView>
    with WidgetsBindingObserver {
  Timer? _sessionTimer;
  bool _sessionPolling = false;
  bool _profilePolling = false;
  Map<String, String> _ids = {};
  Map<String, dynamic> _portals = {};
  String? _name;
  String? _designation;
  String? _schoolName;
  DateTime? _checkedAt;
  bool _loading = true;
  bool _refreshing = false;
  bool _editing = false;
  bool _storageFailed = false;
  bool _statusFailed = false;
  int _epoch = 0;
  Uint8List? _photo;
  bool _photoChanging = false;
  bool _lostPhotoChecked = false;
  String get _photoKey =>
      'account_photo_v1/${widget.schoolId}/${_ids['staff_id'] ?? ""}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _refreshSessions(),
    );
    DashboardBootstrap.mdmStatus.addListener(_readSchoolName);
    _readSchoolName();
    _load();
  }

  @override
  void didUpdateWidget(covariant AccountTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schoolId != widget.schoolId) {
      _epoch++;
      _refreshing = false;
      _ids = {};
      _portals = {};
      _name = null;
      _designation = null;
      _schoolName = null;
      _checkedAt = null;
      _photo = null;
      _load();
    }
  }

  @override
  void dispose() {
    _epoch++;
    _sessionTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    DashboardBootstrap.mdmStatus.removeListener(_readSchoolName);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshSessions();
  }

  Future<void> _refreshSessions() async {
    if (!mounted ||
        _refreshing ||
        _editing ||
        _sessionPolling ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused)
      return;
    _sessionPolling = true;
    final epoch = _epoch;
    try {
      final status = await AccountService.connections();
      if (!mounted || epoch != _epoch) return;
      final current = await SecureStorageService.getAllPortalCreds();
      if (!mounted || epoch != _epoch || !_sameAccount(current, _ids)) return;
      final portals = status['portals'];
      setState(() {
        _statusFailed = status['success'] != true || portals is! Map;
        _portals = _statusFailed ? {} : Map<String, dynamic>.from(portals);
        _checkedAt = _statusFailed ? null : DateTime.now();
      });
      final staff = _portals['staff_login'];
      if (_name == null && staff is Map && _ready(staff)) await _loadProfile();
    } catch (_) {
      if (mounted && epoch == _epoch)
        setState(() {
          _statusFailed = true;
          _portals = {};
          _checkedAt = null;
        });
    } finally {
      _sessionPolling = false;
    }
  }

  Future<void> _loadProfile() async {
    if (_profilePolling) return;
    _profilePolling = true;
    final epoch = _epoch;
    try {
      final credentials = await SecureStorageService.getAllPortalCreds();
      if (!mounted || epoch != _epoch || !_sameAccount(credentials, _ids))
        return;
      final response = await AccountService.profile();
      if (!mounted || epoch != _epoch) return;
      final current = await SecureStorageService.getAllPortalCreds();
      if (!mounted || epoch != _epoch || !_sameAccount(current, credentials))
        return;
      final profile = response['profile'];
      if (response['success'] == true &&
          profile is Map &&
          profile['staffLoginId']?.toString().trim() == _ids['staff_id']) {
        await AccountIdentity.remember(
          widget.schoolId,
          _ids['staff_id'] ?? '',
          profile,
        );
        if (!mounted || epoch != _epoch) return;
        setState(() {
          _name = _text(profile['name']);
          _designation = _text(profile['designation']);
        });
      }
    } catch (_) {
      // A profile failure must not erase independently observed portal health.
    } finally {
      _profilePolling = false;
    }
  }

  static String _clock(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    return '$hour:${local.minute.toString().padLeft(2, '0')} ${local.hour < 12 ? 'AM' : 'PM'}';
  }

  static String? _text(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ||
            ['--', 'unknown', 'staff user'].contains(text.toLowerCase())
        ? null
        : text;
  }

  void _readSchoolName() {
    final snapshot = DashboardBootstrap.mdmStatus.value;
    final result = snapshot?['result'];
    if (snapshot?['school_id'] != widget.schoolId ||
        result is! Map ||
        result['success'] != true)
      return;
    final name = _text(result['school_name']);
    final reported =
        result['school_id']?.toString() ??
        RegExp(r'\((\d{6})\)').firstMatch(name ?? '')?.group(1);
    if (reported != widget.schoolId || name == null) return;
    if (mounted) setState(() => _schoolName = name);
  }

  Future<void> _load() async {
    if (_refreshing || _editing || _photoChanging) return;
    final epoch = ++_epoch;
    final school = widget.schoolId;
    setState(() {
      _refreshing = true;
      _statusFailed = false;
    });
    try {
      final credentials = await SecureStorageService.getAllPortalCreds();
      if (!mounted || epoch != _epoch) return;
      if (credentials['school_id'] != school) {
        setState(() {
          _storageFailed = true;
          _loading = false;
          _portals = {};
        });
        return;
      }
      final same = _sameAccount(credentials, _ids);
      setState(() {
        _ids = {
          'school_id': credentials['school_id'] ?? '',
          'staff_id': credentials['staff_id'] ?? '',
          'sso_id': credentials['sso_id'] ?? '',
        };
        _storageFailed = false;
        _loading = false;
        _portals = {};
        if (!same) {
          _name = null;
          _designation = null;
        }
      });
      final cached = await AccountIdentity.load(school, allowFetch: false);
      if (!mounted || epoch != _epoch) return;
      if (cached['name'] != 'Account' && _text(cached['name']) != null)
        setState(() => _name = _text(cached['name']));
      await _loadPhoto();
      if (!mounted || epoch != _epoch) return;
      final status = await AccountService.connections();
      if (!mounted || epoch != _epoch) return;
      final current = await SecureStorageService.getAllPortalCreds();
      if (!mounted || epoch != _epoch || !_sameAccount(current, credentials))
        return;
      final raw = status['portals'];
      setState(() {
        _statusFailed = status['success'] != true || raw is! Map;
        _portals = _statusFailed ? {} : Map<String, dynamic>.from(raw);
        _checkedAt = _statusFailed ? null : DateTime.now();
        _refreshing = false;
      });
      final staff = _portals['staff_login'];
      if (staff is! Map || !_ready(staff)) return;
      await _loadProfile();
    } catch (_) {
      if (mounted && epoch == _epoch)
        setState(() {
          _storageFailed = _ids.isEmpty;
          _statusFailed = true;
          _portals = {};
        });
    } finally {
      if (mounted && epoch == _epoch)
        setState(() {
          _refreshing = false;
          _loading = false;
        });
    }
  }

  bool _sameAccount(Map<String, String> a, Map<String, String> b) =>
      ['school_id', 'staff_id', 'sso_id'].every((key) => a[key] == b[key]) &&
      a['school_id'] == widget.schoolId;

  static bool _ready(Map portal) =>
      portal['state'] == 'ready' &&
      portal['live'] == true &&
      portal['stale'] != true &&
      '${portal['coordinator_health'] ?? ''}'.toLowerCase() == 'ready';

  ({String label, Color color}) _status(String key) {
    final portal = _portals[key];
    if (portal is! Map)
      return (label: _refreshing ? 'Checking' : 'Unknown', color: _muted);
    if (_ready(portal) &&
        _checkedAt != null &&
        DateTime.now().difference(_checkedAt!).inSeconds < 45)
      return (label: 'Active', color: const Color(0xFF248B60));
    final health = '${portal['coordinator_health'] ?? ''}'.toLowerCase();
    if (['authenticating', 'recovering'].contains(health) ||
        portal['state'] == 'loading') {
      return (label: 'Connecting', color: const Color(0xFFB7791F));
    }
    if (health == 'unknown')
      return (label: 'Not confirmed', color: const Color(0xFFB7791F));
    if (['expired', 'failed', 'idle'].contains(health))
      return (label: 'Inactive', color: _muted);
    return (label: 'Unknown', color: _muted);
  }

  void _notice(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _loadPhoto() async {
    final key = _photoKey;
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = prefs.getString(key);
      if (mounted && key == _photoKey) {
        setState(() => _photo = encoded == null ? null : base64Decode(encoded));
      }
      if (!_lostPhotoChecked &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android) {
        _lostPhotoChecked = true;
        final pending = prefs.getString('account_photo_pending');
        final lost = await ImagePicker().retrieveLostData();
        if (pending == key &&
            lost.files?.isNotEmpty == true &&
            mounted &&
            key == _photoKey) {
          await _savePhoto(lost.files!.first, key);
        }
        if (prefs.getString('account_photo_pending') == pending)
          await prefs.remove('account_photo_pending');
      }
    } catch (_) {
      if (mounted && key == _photoKey) setState(() => _photo = null);
    }
  }

  Future<void> _savePhoto(XFile file, String key) async {
    if (await file.length() > 5 * 1024 * 1024)
      throw StateError('Choose a photo smaller than 5 MB.');
    final original = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(
      original,
      targetWidth: 512,
      allowUpscaling: false,
    );
    Uint8List? bytes;
    try {
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (data != null)
          bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
    if (bytes == null || bytes.length > 2 * 1024 * 1024)
      throw StateError('Choose a smaller photo.');
    final current = await SecureStorageService.getAllPortalCreds();
    if (!mounted ||
        key != _photoKey ||
        current['school_id'] != widget.schoolId ||
        current['staff_id'] != _ids['staff_id'])
      return;
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, base64Encode(bytes)))
      throw StateError('Photo could not be saved.');
    ProfilePhotoStore.changed();
    if (mounted && key == _photoKey) setState(() => _photo = bytes);
  }

  Future<void> _changePhoto() async {
    if (_photoChanging || _editing || _loading || _storageFailed) return;
    final key = _photoKey;
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Text('Profile photo', style: _style(16, FontWeight.w600)),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.photo),
              title: Text('Choose a photo', style: _style(13)),
              onTap: () => Navigator.pop(context, 'choose'),
            ),
            if (_photo != null)
              ListTile(
                leading: const Icon(
                  CupertinoIcons.trash,
                  size: 18,
                  color: Color(0xFFFF214B),
                ),
                title: Text(
                  'Remove photo',
                  style: _style(13, FontWeight.w500, const Color(0xFFFF214B)),
                ),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Saved on this device. Your portal profile is unchanged.',
                style: _style(11.5, FontWeight.w400, _muted),
              ),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted || key != _photoKey) return;
    setState(() => _photoChanging = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (action == 'remove') {
        if (!await prefs.remove(key))
          throw StateError('Photo could not be removed.');
        ProfilePhotoStore.changed();
        if (mounted && key == _photoKey) setState(() => _photo = null);
      } else {
        await prefs.setString('account_photo_pending', key);
        final image = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 85,
          requestFullMetadata: false,
        );
        if (image != null) await _savePhoto(image, key);
        if (prefs.getString('account_photo_pending') == key)
          await prefs.remove('account_photo_pending');
      }
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('account_photo_pending') == key)
        await prefs.remove('account_photo_pending');
      _notice(
        'Photo could not be saved. Choose a JPG or PNG image smaller than 5 MB.',
      );
    } finally {
      if (mounted) setState(() => _photoChanging = false);
    }
  }

  Widget _avatar() => Semantics(
    button: true,
    label: 'Change profile photo',
    child: InkWell(
      onTap: _photoChanging || _editing || _storageFailed ? null : _changePhoto,
      borderRadius: BorderRadius.circular(40),
      child: SizedBox(
        width: 74,
        height: 74,
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFF1F5F9),
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: ClipOval(
                  child: _photo == null
                      ? const Icon(CupertinoIcons.person, size: 31, color: _ink)
                      : Image.memory(
                          _photo!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            CupertinoIcons.person,
                            size: 31,
                            color: _ink,
                          ),
                        ),
                ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 25,
                height: 25,
                decoration: BoxDecoration(
                  color: _ink,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: _photoChanging
                    ? const Padding(
                        padding: EdgeInsets.all(5),
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 1.5,
                        ),
                      )
                    : const Icon(
                        CupertinoIcons.camera,
                        color: Colors.white,
                        size: 12,
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  String _connectionSummary() => [
    'Shaladarpan — connection summary',
    'School NIC: ${widget.schoolId}',
    'Status updated: ${_checkedAt == null ? "Not checked" : _clock(_checkedAt!)}',
    ...{
      'shaladarpan': 'Shala Darpan',
      'staff_login': 'Staff Login',
      'rajsims': 'RajSIMS',
    }.entries.map((e) => '${e.value}: ${_status(e.key).label}'),
    'Describe what happened, the screen and the time before sharing this summary.',
  ].join('\n');

  void _aboutApp() => Navigator.of(context)
      .push(appPageRoute<void>(builder: (_) => const _AboutAppScreen()));

  void _openReport() => Navigator.of(context).push(
    appPageRoute<void>(
      builder: (_) =>
          ReportIssueScreen(connectionSummary: _connectionSummary()),
    ),
  );

  void _openHelp() => Navigator.of(context).push(
    appPageRoute<void>(
      builder: (_) => _HelpCenterScreen(connectionSummary: _connectionSummary),
    ),
  );

  Widget _signOutFooter() => _surface([
    Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Account settings', style: _style(12.5, FontWeight.w600)),
                const SizedBox(height: 3),
                Text(
                  'Saved details stay on this device',
                  style: _style(10.5, FontWeight.w400, _muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _editing || _photoChanging ? null : _signOut,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF214B),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
            icon: const Icon(Icons.logout_rounded, size: 15),
            label: Text(
              'Sign Out',
              style: _style(11.5, FontWeight.w600, Colors.white),
            ),
          ),
        ],
      ),
    ),
  ]);

  Future<void> _editAccount() async {
    if (_editing || _refreshing || _photoChanging) return;
    setState(() => _editing = true);
    final formKey = GlobalKey<FormState>();
    final controls = <String, TextEditingController>{};
    try {
      final saved = await SecureStorageService.getAllPortalCreds();
      if (!mounted) return;
      if (saved['school_id'] != widget.schoolId) {
        _notice('Account changed. Sign in again before editing.');
        return;
      }
      for (final key in ['school_id', 'staff_id', 'sso_id']) {
        controls[key] = TextEditingController(text: saved[key]);
      }
      for (final key in ['school_password', 'staff_password', 'sso_password']) {
        controls[key] = TextEditingController(text: saved[key]);
      }
      final visiblePasswords = <String, bool>{};
      bool saving = false;
      String? error;
      final savedSuccessfully = await pushPageAndWaitForExit<bool>(
        context,
        appPageRoute<bool>(
          builder: (sheetContext) => StatefulBuilder(
            builder: (context, update) {
              Widget pair(String title, String idKey, String passKey) {
                final label = idKey == 'school_id'
                    ? 'School NIC ID'
                    : idKey == 'sso_id'
                    ? 'SSO ID'
                    : 'Staff NIC-SD ID';
                Widget labelled(String text, Widget input) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(text, style: _style(10.5, FontWeight.w400, _muted)),
                    const SizedBox(height: 4),
                    input,
                  ],
                );
                final idField = labelled(
                  label,
                  TextFormField(
                    controller: controls[idKey],
                    enabled: !saving,
                    cursorColor: _ink,
                    onChanged: (value) {
                      if (value.trim() != saved[idKey] &&
                          controls[passKey]!.text == saved[passKey])
                        controls[passKey]!.clear();
                    },
                    autocorrect: false,
                    enableSuggestions: false,
                    style: _style(12),
                    decoration: _input(label).copyWith(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Enter login ID' : null,
                  ),
                );
                final passwordField = labelled(
                  'Password',
                  TextFormField(
                    controller: controls[passKey],
                    enabled: !saving,
                    cursorColor: _ink,
                    obscureText: !(visiblePasswords[passKey] ?? false),
                    autocorrect: false,
                    enableSuggestions: false,
                    style: _style(12),
                    decoration: _input('Password').copyWith(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      suffixIcon: IconButton(
                        tooltip: visiblePasswords[passKey] == true
                            ? 'Hide password'
                            : 'Show password',
                        onPressed: saving
                            ? null
                            : () => update(
                                () => visiblePasswords[passKey] =
                                    !(visiblePasswords[passKey] ?? false),
                              ),
                        icon: Icon(
                          visiblePasswords[passKey] == true
                              ? CupertinoIcons.eye_slash
                              : CupertinoIcons.eye,
                          size: 16,
                          color: _muted,
                        ),
                      ),
                    ),
                    validator: (v) =>
                        (v ?? '').isEmpty ? 'Enter password' : null,
                  ),
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 26,
                              height: 26,
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F5F7),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Image.asset(
                                idKey == 'school_id'
                                    ? 'assets/icons/shaladarpan.png'
                                    : idKey == 'staff_id'
                                    ? 'assets/icons/staff.png'
                                    : 'assets/icons/rajsims.png',
                                errorBuilder: (_, __, ___) =>
                                    const Icon(CupertinoIcons.lock, size: 15),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(title, style: _style(12.5, FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Column(
                          children: [
                            idField,
                            const SizedBox(height: 8),
                            passwordField,
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: Theme.of(context).colorScheme
                      .copyWith(primary: _ink, secondary: _ink, error: _muted),
                  textSelectionTheme: const TextSelectionThemeData(
                    cursorColor: _ink,
                    selectionColor: Color(0xFFCBD5E1),
                    selectionHandleColor: _ink,
                  ),
                ),
                child: PopScope(
                  canPop: !saving,
                  child: Scaffold(
                    backgroundColor: const Color(0xFFF8FAFC),
                    appBar: AppBar(
                      backgroundColor: const Color(0xFFF8FAFC),
                      surfaceTintColor: Colors.transparent,
                      elevation: 0,
                      leading: IconButton(
                        onPressed: saving
                            ? null
                            : () => Navigator.pop(sheetContext, false),
                        icon: const Icon(CupertinoIcons.chevron_back, size: 19),
                      ),
                      title: Text(
                        'Account details',
                        style: _style(18, FontWeight.w600),
                      ),
                    ),
                    body: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0, .45, 1],
                          colors: [
                            Color(0xFFF8FAFC),
                            Color(0xFFF1F5F9),
                            Color(0xFFFEF3C7),
                          ],
                        ),
                      ),
                      child: PageContentMotion(child: SizedBox.expand(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 620),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                10,
                                16,
                                16,
                              ),
                              child: Form(
                                key: formKey,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Manage your portal logins',
                                      style: _style(
                                        12,
                                        FontWeight.w400,
                                        _muted,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    pair(
                                      'Shaladarpan',
                                      'school_id',
                                      'school_password',
                                    ),
                                    pair(
                                      'Staff Login',
                                      'staff_id',
                                      'staff_password',
                                    ),
                                    pair('RajSIMS', 'sso_id', 'sso_password'),
                                    if (error != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        child: Text(
                                          error!,
                                          style: _style(
                                            12,
                                            FontWeight.w400,
                                            _ink,
                                          ),
                                        ),
                                      ),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: saving
                                                ? null
                                                : () => Navigator.pop(
                                                    sheetContext,
                                                    false,
                                                  ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: _ink,
                                              backgroundColor: Colors.white,
                                              side: const BorderSide(
                                                color: _border,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 14,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(11),
                                              ),
                                            ),
                                            child: Text(
                                              'Cancel',
                                              style: _style(
                                                12,
                                                FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: FilledButton(
                                            onPressed: saving
                                                ? null
                                                : () async {
                                                    if (!formKey.currentState!
                                                        .validate())
                                                      return;
                                                    if (controls['school_id']!
                                                            .text
                                                            .trim() ==
                                                        controls['staff_id']!
                                                            .text
                                                            .trim()) {
                                                      update(
                                                        () => error = 'School ID and Staff ID must be different.',
                                                      );
                                                      return;
                                                    }
                                                    update(() {
                                                      saving = true;
                                                      error = null;
                                                    });
                                                    try {
                                                      final current =
                                                          await SecureStorageService.getAllPortalCreds();
                                                      if (!_sameAccount(
                                                        current,
                                                        saved,
                                                      ))
                                                        throw StateError(
                                                          'Account changed. Reopen login details.',
                                                        );
                                                      String password(
                                                        String key,
                                                      ) => controls[key]!.text;
                                                      await SecureStorageService.saveAllPortals(
                                                        shalaId:
                                                            controls['school_id']!
                                                                .text
                                                                .trim(),
                                                        shalaPass: password(
                                                          'school_password',
                                                        ),
                                                        staffId:
                                                            controls['staff_id']!
                                                                .text
                                                                .trim(),
                                                        staffPass: password(
                                                          'staff_password',
                                                        ),
                                                        rajsimsId:
                                                            controls['sso_id']!
                                                                .text
                                                                .trim(),
                                                        rajsimsPass: password(
                                                          'sso_password',
                                                        ),
                                                      );
                                                      if (sheetContext.mounted)
                                                        Navigator.pop(
                                                          sheetContext,
                                                          true,
                                                        );
                                                    } catch (_) {
                                                      if (sheetContext.mounted)
                                                        update(() {
                                                          saving = false;
                                                          error = 'Could not save login details. Please try again.';
                                                        });
                                                    }
                                                  },
                                            style: FilledButton.styleFrom(
                                              backgroundColor: _ink,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 16,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(11),
                                              ),
                                            ),
                                            child: saving
                                                ? const SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.white,
                                                        ),
                                                  )
                                                : Text(
                                                    'Save & sign out',
                                                    style: _style(
                                                      12,
                                                      FontWeight.w500,
                                                      Colors.white,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      )),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      if (savedSuccessfully == true && mounted) {
        _epoch++;
        widget.onLogoutRequested();
      }
    } catch (_) {
      _notice('Saved login details could not be loaded.');
    } finally {
      for (final controller in controls.values) {
        controller.dispose();
      }
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _signOut() async {
    if (_editing || _photoChanging) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 520),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Sign out?',
                      style: _style(18, FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(sheetContext, false),
                    color: _ink,
                    icon: const Icon(CupertinoIcons.xmark, size: 16),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Your saved login details will stay on this device. Use Continue as to sign in again.',
                style: _style(12, FontWeight.w400, _muted),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(sheetContext, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _ink,
                        side: const BorderSide(color: _border),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: _style(12.5, FontWeight.w500),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(sheetContext, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF214B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                      child: Text(
                        'Sign out',
                        style: _style(12.5, FontWeight.w600, Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true && mounted) {
      _epoch++;
      widget.onLogoutRequested();
    }
  }

  static TextStyle _style(
    double size, [
    FontWeight weight = FontWeight.w500,
    Color color = _ink,
  ]) => TextStyle(
    fontFamily: kAppFont,
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: 1.35,
    letterSpacing: size >= 16 ? -0.35 : -0.1,
  );

  static InputDecoration _input(String label) => InputDecoration(
    hintText: label,
    hintStyle: _style(12, FontWeight.w400, _muted),
    filled: true,
    fillColor: const Color(0xFFF3F5F7),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF94A3B8)),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _ink),
    ),
    errorStyle: _style(11, FontWeight.w400, _muted),
  );

  Widget _surface(List<Widget> children) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _border.withValues(alpha: 0.65)),
      boxShadow: [
        BoxShadow(
          color: _ink.withValues(alpha: 0.025),
          blurRadius: 18,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Column(children: children),
  );

  Widget _section(String title, Widget child) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(title, style: _style(12, FontWeight.w600, _muted)),
        ),
        child,
      ],
    ),
  );

  Widget _row(
    IconData icon,
    String title,
    String subtitle, {
    Widget? trailing,
    VoidCallback? onTap,
  }) => CupertinoButton(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    onPressed: onTap,
    child: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F4F7),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: _ink),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: _style(13, FontWeight.w500)),
              const SizedBox(height: 2),
              Text(subtitle, style: _style(11, FontWeight.w400, _muted)),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    ),
  );

  Widget _portal(String key, String title, String idKey, IconData icon) {
    final state = _status(key);
    final id = _ids[idKey] ?? '';
    final assets = {
      'shaladarpan': 'shaladarpan',
      'staff_login': 'staff',
      'rajsims': 'rajsims',
    };
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.white,
        isScrollControlled: true,
        useSafeArea: true,
        constraints: const BoxConstraints(maxWidth: 520),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (sheetContext) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F7FA),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Image.asset(
                        'assets/icons/${assets[key]}.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            Icon(icon, size: 22, color: _ink),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(title, style: _style(16, FontWeight.w600)),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(
                        CupertinoIcons.xmark,
                        size: 16,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Login ID',
                            style: _style(10.5, FontWeight.w400, _muted),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            id.isEmpty ? 'Not configured' : id,
                            style: _style(12.5, FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: state.label == 'Active'
                            ? const Color(0xFF69F0AE)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        state.label,
                        style: _style(
                          10.5,
                          FontWeight.w500,
                          state.label == 'Active'
                              ? const Color(0xFF064E3B)
                              : state.color,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 26, color: _border),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Last updated',
                        style: _style(11, FontWeight.w400, _muted),
                      ),
                    ),
                    Text(
                      _checkedAt == null
                          ? 'Not confirmed'
                          : _clock(_checkedAt!),
                      style: _style(11, FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  state.label == 'Active'
                      ? 'Session available'
                      : state.label == 'Connecting'
                      ? 'Session is connecting'
                      : state.label == 'Inactive'
                      ? 'Sign in to reconnect'
                      : 'Session status could not be confirmed',
                  style: _style(11, FontWeight.w400, _muted),
                ),
              ],
            ),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Image.asset(
              'assets/icons/${assets[key]}.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(icon, size: 20, color: _ink),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _style(12.5, FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  id.isEmpty ? 'Not configured' : id,
                  style: _style(10.5, FontWeight.w400, _muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (state.label == 'Active')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF69F0AE),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.circle, size: 4, color: Color(0xFF064E3B)),
                  const SizedBox(width: 5),
                  Text(
                    'Active',
                    style: _style(10, FontWeight.w600, const Color(0xFF064E3B)),
                  ),
                ],
              ),
            )
          else ...[
            if (state.label == 'Checking' || state.label == 'Connecting')
              const CupertinoActivityIndicator(radius: 6)
            else
              Icon(Icons.circle, size: 5, color: state.color),
            const SizedBox(width: 5),
            Text(
              state.label,
              style: _style(10.5, FontWeight.w500, state.color),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _name ?? (_loading ? 'Loading account…' : 'School account');
    final school = _ids['school_id'] ?? widget.schoolId;
    final checked = _checkedAt;
    return Container(
      // Inherit the dashboard background so it continues behind navigation.
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide =
              constraints.maxWidth >=
              AppAdaptive.twoPane *
                  (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
                    1.0,
                    1.5,
                  );
          final profile = _surface([
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _avatar(),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: _style(15, FontWeight.w600)),
                            if (_designation != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _designation!,
                                style: _style(11.5, FontWeight.w400, _muted),
                              ),
                            ],
                            const SizedBox(height: 5),
                            CupertinoButton(
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              onPressed:
                                  _photoChanging || _editing || _storageFailed
                                  ? null
                                  : _changePhoto,
                              child: Text(
                                'Change photo',
                                style: _style(11, FontWeight.w500, _muted),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F9FB),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'School NIC ID',
                                style: _style(10.5, FontWeight.w400, _muted),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                school,
                                style: _style(12.5, FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Staff ID',
                                style: _style(10.5, FontWeight.w400, _muted),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _ids['staff_id']?.isNotEmpty == true
                                    ? _ids['staff_id']!
                                    : '—',
                                style: _style(12.5, FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_schoolName != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _schoolName!,
                      style: _style(11.5, FontWeight.w400, _muted),
                    ),
                  ],
                ],
              ),
            ),
          ]);
          final connections = Padding(
            padding: EdgeInsets.only(top: wide ? 0 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 0, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Connections',
                          style: _style(12, FontWeight.w600, _muted),
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.all(8),
                        onPressed: _refreshing || _editing ? null : _load,
                        child: _refreshing
                            ? const CupertinoActivityIndicator(radius: 7)
                            : const Icon(
                                CupertinoIcons.arrow_clockwise,
                                size: 16,
                                color: _muted,
                              ),
                      ),
                    ],
                  ),
                ),
                _surface([
                  _portal(
                    'shaladarpan',
                    'Shaladarpan',
                    'school_id',
                    CupertinoIcons.house,
                  ),
                  const Divider(
                    height: 1,
                    indent: 71,
                    endIndent: 18,
                    color: _border,
                  ),
                  _portal(
                    'staff_login',
                    'Staff Login',
                    'staff_id',
                    CupertinoIcons.person,
                  ),
                  const Divider(
                    height: 1,
                    indent: 71,
                    endIndent: 18,
                    color: _border,
                  ),
                  _portal(
                    'rajsims',
                    'RajSIMS',
                    'sso_id',
                    CupertinoIcons.cube_box,
                  ),
                ]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
                  child: Text(
                    _statusFailed
                        ? 'Could not confirm the latest status'
                        : checked == null
                        ? 'Status has not been checked'
                        : 'Status updated : ${_clock(checked)}',
                    style: _style(10, FontWeight.w400, _muted),
                  ),
                ),
              ],
            ),
          );
          final settings = Column(
            children: [
              _section(
                'Preferences & support',
                _surface([
                  _row(
                    CupertinoIcons.lock,
                    'Account details',
                    'School, staff and SSO login',
                    trailing: _editing
                        ? const CupertinoActivityIndicator(radius: 8)
                        : const Icon(
                            CupertinoIcons.chevron_forward,
                            size: 13,
                            color: _muted,
                          ),
                    onTap: _editing || _refreshing || _storageFailed
                        ? null
                        : _editAccount,
                  ),
                  const Divider(height: 1, indent: 68, color: _border),
                  _row(
                    CupertinoIcons.question_circle,
                    'Help Center',
                    'Answers and guidance',
                    trailing: const Icon(
                      CupertinoIcons.chevron_forward,
                      size: 13,
                      color: _muted,
                    ),
                    onTap: _openHelp,
                  ),
                  const Divider(height: 1, indent: 68, color: _border),
                  _row(
                    CupertinoIcons.envelope,
                    'Report app issue',
                    'Share a problem with the developer',
                    trailing: const Icon(
                      CupertinoIcons.chevron_forward,
                      size: 13,
                      color: _muted,
                    ),
                    onTap: _openReport,
                  ),
                  const Divider(height: 1, indent: 68, color: _border),
                  _row(
                    CupertinoIcons.info_circle,
                    'About app',
                    'Version, developer and terms',
                    trailing: const Icon(
                      CupertinoIcons.chevron_forward,
                      size: 13,
                      color: _muted,
                    ),
                    onTap: _aboutApp,
                  ),
                ]),
              ),
            ],
          );
          return ProgressIndicatorTheme(
            data: const ProgressIndicatorThemeData(
              color: _ink,
              circularTrackColor: Color(0xFFE2E8F0),
            ),
            child: RefreshIndicator(
              onRefresh: _load,
              color: _ink,
              backgroundColor: Colors.white,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth:
                          AppAdaptive.contentWidth(constraints.maxWidth) - 32,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('My account', style: _style(20, FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(
                          'Your school workspace, personalised',
                          style: _style(12, FontWeight.w400, _muted),
                        ),
                        const SizedBox(height: 20),
                        if (_storageFailed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Saved account could not be loaded. Refresh or sign in again.',
                              style: _style(12, FontWeight.w400, _muted),
                            ),
                          ),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    profile,
                                    const SizedBox(height: 20),
                                    connections,
                                  ],
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    settings,
                                    const SizedBox(height: 20),
                                    _signOutFooter(),
                                  ],
                                ),
                              ),
                            ],
                          )
                        else ...[
                          profile,
                          connections,
                          settings,
                          const SizedBox(height: 20),
                          _signOutFooter(),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HelpCenterScreen extends StatefulWidget {
  final String Function() connectionSummary;
  const _HelpCenterScreen({required this.connectionSummary});
  @override
  State<_HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<_HelpCenterScreen> {
  String _search = '';
  static const _guides = <({String category, String question, String answer})>[
    (
      category: 'Getting started',
      question: 'How do I sign in after signing out?',
      answer: 'Choose Continue as on the Welcome back screen. Your saved login details stay on this device. Use Edit account if an ID or password has changed. During first-time setup, Back takes you to a skipped portal step.',
    ),
    (
      category: 'Account',
      question: 'How do I update my login details?',
      answer: 'Open My account → Account details. Saved passwords appear masked; use the eye button to check them. Enter the correct password whenever you change a login ID. Save & sign out stores your changes and returns to login.',
    ),
    (
      category: 'Account',
      question: 'Where is my profile photo saved?',
      answer: 'The photo stays on this device, separately for each saved school and staff account. It does not change your Shala Darpan or RajSIMS profile. Tap the photo or Change photo to choose or remove an image. Use a JPG or PNG smaller than 5 MB.',
    ),
    (
      category: 'Connections',
      question: 'A portal is unavailable. What should I do?',
      answer: 'Use the refresh icon beside Connections to check the current status. Not confirmed means the backend could not verify the session; it does not prove that you are logged out. If the issue continues, check your saved login details and sign in again. A portal outage can also prevent access.',
    ),
    (
      category: 'Attendance',
      question: 'Why is an employee’s attendance locked?',
      answer: 'The app preserves the portal’s locked status. A locked employee may have no editable dropdown. Review the employee ID and existing status before submitting the other rows. Staff attendance cannot be changed after the portal locks it.',
    ),
    (
      category: 'Attendance',
      question: 'Submission needs verification. Should I retry?',
      answer: 'Refresh the attendance screen and independently check the portal first. A delayed or lost response can occur after the portal has saved the attendance. Do not repeatedly submit an unconfirmed request. Review every employee or student ID and status before a new submission.',
    ),
    (
      category: 'Attendance',
      question: 'What does Pending mean in a student report?',
      answer: 'Pending means the portal has not confirmed attendance as marked for that class and date. A fetched student list or generated PDF alone does not prove submission. Verified should reflect confirmed portal attendance status.',
    ),
    (
      category: 'Leave',
      question: 'Why do leave approvals matter before attendance?',
      answer: 'Review the current pending leave applications before staff attendance. Check the employee, dates and leave duration, then approve or reject the intended application. Refresh attendance afterwards to read the portal’s updated leave and lock status.',
    ),
    (
      category: 'MDM',
      question: 'My stock has not changed after distribution.',
      answer: 'Refresh the RajSIMS stock tiles and check the distribution entry on the portal. If saving was unconfirmed, verify the existing entry before submitting again. A stale stock tile alone does not mean the distribution failed.',
    ),
    (
      category: 'Monthly tasks',
      question: 'A monthly task shows no records.',
      answer: 'Check the selected task, reporting period and school applicability on the portal. Some forms are not offered for every school category. No records is not confirmation that a task is complete or locked.',
    ),
  ];

  Future<void> _copySummary() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.connectionSummary()));
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Connection summary copied. Add the issue details before sharing it.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not copy the summary. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.trim().toLowerCase();
    final guides = _guides
        .where(
          (g) => '${g.category} ${g.question} ${g.answer}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Help Center',
          style: _AccountTabViewState._style(18, FontWeight.w600),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0, .45, 1],
            colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9), Color(0xFFFEF3C7)],
          ),
        ),
        child: PageContentMotion(child: SizedBox.expand(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      onChanged: (value) => setState(() => _search = value),
                      style: _AccountTabViewState._style(12.5),
                      decoration: _AccountTabViewState._input('Search help')
                          .copyWith(
                            labelText: null,
                            hintText: 'Search help',
                            fillColor: Colors.white,
                            prefixIcon: const Icon(
                              CupertinoIcons.search,
                              size: 17,
                              color: _muted,
                            ),
                          ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.only(left: 3, bottom: 8),
                      child: Text(
                        query.isEmpty ? 'Common questions' : 'Search results',
                        style: _AccountTabViewState._style(
                          12,
                          FontWeight.w600,
                          _muted,
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _border),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Column(
                          children: [
                            if (guides.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(18),
                                child: Text(
                                  'No matching answers. Try attendance, account or MDM.',
                                  style: _AccountTabViewState._style(
                                    12,
                                    FontWeight.w400,
                                    _muted,
                                  ),
                                ),
                              ),
                            for (var i = 0; i < guides.length; i++) ...[
                              if (i > 0)
                                const Divider(
                                  height: 1,
                                  indent: 16,
                                  endIndent: 16,
                                  color: _border,
                                ),
                              ExpansionTile(
                                key: ValueKey(guides[i].question),
                                shape: const Border(),
                                collapsedShape: const Border(),
                                iconColor: _muted,
                                collapsedIconColor: _muted,
                                tilePadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 0,
                                ),
                                childrenPadding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  14,
                                ),
                                title: Text(
                                  guides[i].question,
                                  style: _AccountTabViewState._style(
                                    12,
                                    FontWeight.w500,
                                  ),
                                ),
                                children: [
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      guides[i].answer,
                                      style: _AccountTabViewState._style(
                                        11.5,
                                        FontWeight.w400,
                                        _muted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Need more help?',
                      style: _AccountTabViewState._style(12.5, FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          appPageRoute<void>(
                            builder: (_) => ReportIssueScreen(
                              connectionSummary: widget.connectionSummary(),
                            ),
                          ),
                        ),
                        icon: const Icon(CupertinoIcons.envelope, size: 16),
                        label: Text(
                          'Report app issue',
                          style: _AccountTabViewState._style(
                            12,
                            FontWeight.w500,
                            Colors.white,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: _ink,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _copySummary,
                        icon: const Icon(CupertinoIcons.doc_on_doc, size: 15),
                        label: Text(
                          'Copy connection summary',
                          style: _AccountTabViewState._style(
                            11.5,
                            FontWeight.w500,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _ink,
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: _border),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        )),
      ),
    );
  }
}

class _AboutAppScreen extends StatefulWidget {
  const _AboutAppScreen();
  @override
  State<_AboutAppScreen> createState() => _AboutAppScreenState();
}

class _AboutAppScreenState extends State<_AboutAppScreen> {
  // Release identifier for this patch. Native build/version codes stay numeric.
  static const _buildId = String.fromEnvironment(
    'APP_BUILD_ID',
    defaultValue: '2026.10.03.01',
  );
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: _AccountTabViewState._style(12, FontWeight.w400, _muted),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SelectableText(
            value,
            style: _AccountTabViewState._style(12.5, FontWeight.w500),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF8FAFC),
    appBar: AppBar(
      backgroundColor: const Color(0xFFF8FAFC),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      title: Text(
        'About',
        style: _AccountTabViewState._style(18, FontWeight.w600),
      ),
    ),
    body: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, .45, 1],
          colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9), Color(0xFFFEF3C7)],
        ),
      ),
      child: PageContentMotion(child: SizedBox.expand(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _border.withValues(alpha: .65)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: Image.asset(
                            'assets/icons/icon.png',
                            width: 34,
                            height: 34,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const SizedBox(
                              width: 34,
                              height: 34,
                              child: Icon(
                                CupertinoIcons.app,
                                size: 28,
                                color: _ink,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Shaladarpan',
                                style: _AccountTabViewState._style(
                                  16,
                                  FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1, color: _border),
                    _detail('Developer', 'Ripudaman Singh Jhala'),
                    const Divider(height: 1, color: _border),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Version',
                                  style: _AccountTabViewState._style(
                                    10.5,
                                    FontWeight.w400,
                                    _muted,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                FutureBuilder<PackageInfo>(
                                  future: _packageInfo,
                                  builder: (context, snapshot) => Text(
                                    snapshot.hasData
                                        ? snapshot.data!.version
                                        : snapshot.hasError
                                        ? 'Unavailable'
                                        : 'Loading…',
                                    style: _AccountTabViewState._style(
                                      12,
                                      FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Build',
                                  style: _AccountTabViewState._style(
                                    10.5,
                                    FontWeight.w400,
                                    _muted,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SelectableText(
                                  _buildId,
                                  style: _AccountTabViewState._style(
                                    12,
                                    FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: _border),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      dense: true,
                      childrenPadding: const EdgeInsets.only(bottom: 14),
                      shape: const Border(),
                      collapsedShape: const Border(),
                      iconColor: _muted,
                      collapsedIconColor: _muted,
                      title: Text(
                        'Terms of use',
                        style: _AccountTabViewState._style(
                          12.5,
                          FontWeight.w500,
                        ),
                      ),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Use this app only with school and staff accounts you are authorised to access.\n\n'
                            'Review employee or student IDs, dates and selected values before submitting attendance, leave or other records. Portal rules and locked records remain applicable.\n\n'
                            'If a submission is unconfirmed, check the portal before submitting again. Portal availability and delayed responses can affect the app.\n\n'
                            'Shaladarpan is an independently developed app. It is not an official government app. The external portals retain control of their records and services.\n\n'
                            'When reporting an issue, remove passwords and unnecessary personal information from descriptions and attachments.',
                            style: _AccountTabViewState._style(
                              11.5,
                              FontWeight.w400,
                              _muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 1, color: _border),
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        '© 2026 Ripudaman Singh Jhala',
                        style: _AccountTabViewState._style(
                          10.5,
                          FontWeight.w400,
                          _muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      )),
    ),
  );
}
