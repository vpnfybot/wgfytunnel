import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class XowgDeviceIdentity {
  static const String _preferenceKey = 'xowg_device_id_v1';
  static const MethodChannel _androidChannel = MethodChannel(
    'wgfytunnel/wireguard',
  );
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  static Future<String> loadOrCreate({SharedPreferences? preferences}) async {
    if (preferences == null && Platform.isAndroid) {
      try {
        final nativeId = (await _androidChannel.invokeMethod<String>(
          'getOrCreateXowgDeviceId',
        ))?.trim().toLowerCase();
        if (nativeId != null && _uuidPattern.hasMatch(nativeId)) {
          return nativeId;
        }
      } on MissingPluginException {
        // SharedPreferences remains a safe fallback on non-standard embedders.
      } on PlatformException {
        // Do not block HyperWG when the no-backup storage is temporarily unavailable.
      }
    }

    final prefs = preferences ?? await SharedPreferences.getInstance();
    final existing = prefs.getString(_preferenceKey)?.trim().toLowerCase();
    if (existing != null && _uuidPattern.hasMatch(existing)) {
      return existing;
    }

    final generated = _generateUuidV4();
    await prefs.setString(_preferenceKey, generated);
    return generated;
  }

  static String _generateUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
