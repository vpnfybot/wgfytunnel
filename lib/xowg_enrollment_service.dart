import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'wg_config_parser.dart';
import 'xowg_config.dart';

class XowgEnrollmentResult {
  const XowgEnrollmentResult({
    required this.nativeConfig,
    required this.evictedDeviceId,
  });

  final String nativeConfig;
  final String? evictedDeviceId;
}

class XowgEnrollmentException implements Exception {
  const XowgEnrollmentException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class XowgEnrollmentService {
  const XowgEnrollmentService();

  static const Duration _requestTimeout = Duration(seconds: 15);
  static const int _maxResponseBytes = 1024 * 1024;

  Future<XowgEnrollmentResult> enroll({
    required XowgConfig config,
    required String deviceId,
  }) async {
    final client = HttpClient()..connectionTimeout = _requestTimeout;
    try {
      final request = await client
          .postUrl(config.enrollmentUri)
          .timeout(_requestTimeout);
      request.persistentConnection = false;
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(
        jsonEncode(<String, String>{
          'access_key': config.accessKey,
          'device_id': deviceId,
          'name': 'wgfytunnel-${deviceId.substring(0, 8)}',
        }),
      );

      final response = await request.close().timeout(_requestTimeout);
      final body = await _readResponse(response);
      final decoded = _decodeObject(body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw XowgEnrollmentException(
          decoded['error']?.toString() ?? 'HyperWG enrollment failed',
          code: decoded['code']?.toString(),
        );
      }

      final nativeConfig = decoded['native_config']?.toString() ?? '';
      if (nativeConfig.isEmpty ||
          parseWireguardConfig(nativeConfig)['isValid'] != true) {
        throw const XowgEnrollmentException(
          'HyperWG API returned an invalid tunnel configuration',
          code: 'invalid_native_config',
        );
      }

      final tunnel = decoded['tunnel'];
      final rawProtocol = tunnel is Map ? tunnel['protocol']?.toString() : null;
      if (!XowgConfig.supportsProtocol(rawProtocol)) {
        throw const XowgEnrollmentException(
          'HyperWG API returned a tunnel for another protocol',
          code: 'invalid_protocol',
        );
      }

      final evicted = decoded['evicted_device'];
      return XowgEnrollmentResult(
        nativeConfig: _withTrafficMorpher(nativeConfig, tunnel),
        evictedDeviceId: evicted is Map
            ? evicted['external_id']?.toString()
            : null,
      );
    } on TimeoutException {
      throw const XowgEnrollmentException(
        'HyperWG API request timed out',
        code: 'timeout',
      );
    } on SocketException catch (error) {
      throw XowgEnrollmentException(
        'Cannot reach HyperWG API: ${error.message}',
        code: 'network_error',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _readResponse(HttpClientResponse response) async {
    final bytes = <int>[];
    await for (final chunk in response.timeout(_requestTimeout)) {
      if (bytes.length + chunk.length > _maxResponseBytes) {
        throw const XowgEnrollmentException(
          'HyperWG API response is too large',
          code: 'response_too_large',
        );
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }

  // Older servers omit this field, and older apps ignore it. Only a HyperWG
  // enrollment opts into the new native sender; ordinary WG/AWG imports do not.
  String _withTrafficMorpher(String nativeConfig, dynamic tunnel) {
    final profile = tunnel is Map ? tunnel['traffic_morpher'] : null;
    if (profile == null) return nativeConfig;
    const profiles = <String>{
      'off',
      'interactive',
      'web',
      'streaming',
      'mixed',
    };
    if (profile is! String || !profiles.contains(profile)) {
      throw const XowgEnrollmentException(
        'HyperWG API returned an unsupported traffic profile',
        code: 'unsupported_traffic_morpher',
      );
    }
    final interface = RegExp(
      r'^[ \t]*\[Interface\][ \t]*\r?$',
      caseSensitive: false,
      multiLine: true,
    );
    return nativeConfig.replaceFirst(
      interface,
      '[Interface]\nTrafficMorpher = $profile',
    );
  }

  Map<String, dynamic> _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } on FormatException {
      // Converted to a stable public error below.
    }
    throw const XowgEnrollmentException(
      'HyperWG API returned invalid JSON',
      code: 'invalid_response',
    );
  }
}
