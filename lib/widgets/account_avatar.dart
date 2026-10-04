import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shaladarpan/services/core/profile_photo_store.dart';
import 'package:shaladarpan/services/core/secure_storage_service.dart';

class AccountAvatar extends StatefulWidget {
  final String schoolId;
  final double size;
  const AccountAvatar({super.key, required this.schoolId, this.size = 40});
  @override
  State<AccountAvatar> createState() => _AccountAvatarState();
}
class _AccountAvatarState extends State<AccountAvatar> {
  Uint8List? _bytes;
  int _epoch = 0;
  @override
  void initState() { super.initState(); ProfilePhotoStore.revision.addListener(_reload); _reload(); }
  @override
  void didUpdateWidget(covariant AccountAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schoolId != widget.schoolId) { _bytes = null; _reload(); }
  }
  Future<void> _reload() async {
    final epoch = ++_epoch;
    final school = widget.schoolId;
    try {
      final creds = await SecureStorageService.getAllPortalCreds();
      final bytes = creds['school_id'] == school ? await ProfilePhotoStore.read('account_photo_v1/$school/${creds['staff_id'] ?? ''}') : null;
      if (mounted && epoch == _epoch && school == widget.schoolId) setState(() => _bytes = bytes);
    } catch (_) {
      if (mounted && epoch == _epoch) setState(() => _bytes = null);
    }
  }
  @override
  void dispose() { _epoch++; ProfilePhotoStore.revision.removeListener(_reload); super.dispose(); }
  @override
  Widget build(BuildContext context) => ClipOval(child: SizedBox(width: widget.size, height: widget.size,
    child: _bytes == null ? Image.asset('assets/icons/user.png', fit: BoxFit.cover,
      errorBuilder: (context, error, stack) => Icon(CupertinoIcons.person_fill, size: widget.size * .55)) :
      Image.memory(_bytes!, fit: BoxFit.cover, gaplessPlayback: true,
        errorBuilder: (context, error, stack) => Icon(CupertinoIcons.person_fill, size: widget.size * .55))));
}
