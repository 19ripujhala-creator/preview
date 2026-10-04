import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Account-scoped photo notifications; unrelated accounts never share an avatar.
class ProfilePhotoStore {
  static final revision = ValueNotifier<int>(0);
  static Future<Uint8List?> read(String key) async {
    try {
      final value = (await SharedPreferences.getInstance()).getString(key);
      return value == null ? null : base64Decode(value);
    } catch (_) { return null; }
  }
  static void changed() => revision.value++;
}
