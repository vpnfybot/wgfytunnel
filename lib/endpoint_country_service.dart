import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class EndpointCountryInfo {
  const EndpointCountryInfo({
    required this.countryCode,
    required this.countryName,
  });

  final String countryCode;
  final String countryName;

  String get flagEmoji {
    final normalizedCode = countryCode.trim().toUpperCase();
    if (normalizedCode.length != 2) {
      return '\u{1F310}';
    }

    return String.fromCharCodes(
      normalizedCode.codeUnits.map((codeUnit) => codeUnit + 127397),
    );
  }
}

class EndpointCountryService {
  const EndpointCountryService._();

  static final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5);

  static String? lookupKeyForEndpoint(String endpoint) {
    final host = _extractEndpointHost(endpoint);
    if (host == null || host.isEmpty) {
      return null;
    }

    return host.toLowerCase();
  }

  static Future<EndpointCountryInfo?> lookupCountryForEndpoint(
    String endpoint,
  ) async {
    final host = _extractEndpointHost(endpoint);
    if (host == null || host.isEmpty) {
      return null;
    }

    final ipAddress = await _resolveAddress(host);
    if (ipAddress == null || ipAddress.isEmpty) {
      _debugLog('Could not resolve endpoint host: $host');
      return null;
    }

    _debugLog('Looking up endpoint host=$host ip=$ipAddress');
    return _lookupCountryForIp(ipAddress);
  }

  static String? _extractEndpointHost(String endpoint) {
    final trimmedEndpoint = endpoint.trim();
    if (trimmedEndpoint.isEmpty || trimmedEndpoint == '-') {
      return null;
    }

    if (trimmedEndpoint.startsWith('[')) {
      final closingBracketIndex = trimmedEndpoint.indexOf(']');
      if (closingBracketIndex <= 1) {
        return null;
      }

      return trimmedEndpoint.substring(1, closingBracketIndex).trim();
    }

    final colonMatches = ':'.allMatches(trimmedEndpoint).length;
    if (colonMatches == 0) {
      return trimmedEndpoint;
    }

    if (colonMatches == 1) {
      final separatorIndex = trimmedEndpoint.lastIndexOf(':');
      return trimmedEndpoint.substring(0, separatorIndex).trim();
    }

    final parsedAddress = InternetAddress.tryParse(trimmedEndpoint);
    if (parsedAddress != null) {
      return parsedAddress.address;
    }

    final separatorIndex = trimmedEndpoint.lastIndexOf(':');
    final possiblePort = trimmedEndpoint.substring(separatorIndex + 1).trim();
    if (separatorIndex > 0 && int.tryParse(possiblePort) != null) {
      return trimmedEndpoint.substring(0, separatorIndex).trim();
    }

    return trimmedEndpoint;
  }

  static Future<String?> _resolveAddress(String host) async {
    final parsedAddress = InternetAddress.tryParse(host);
    if (parsedAddress != null) {
      return parsedAddress.address;
    }

    try {
      final addresses = await InternetAddress.lookup(
        host,
      ).timeout(const Duration(seconds: 5));
      if (addresses.isEmpty) {
        return null;
      }

      for (final address in addresses) {
        if (address.type == InternetAddressType.IPv4) {
          return address.address;
        }
      }

      return addresses.first.address;
    } catch (_) {
      return null;
    }
  }

  static Future<EndpointCountryInfo?> _lookupCountryForIp(
    String ipAddress,
  ) async {
    final primaryResult = await _lookupCountryFromIpWho(ipAddress);
    if (primaryResult != null) {
      _debugLog(
        'Country lookup succeeded with ipwho.is: ${primaryResult.countryCode}',
      );
      return primaryResult;
    }

    // ipwho.is can be temporarily unavailable or rate-limited. Keep a
    // separate provider as a fallback so the flag is still shown when the
    // primary lookup fails.
    _debugLog('ipwho.is returned no usable country data; trying countries.dev');
    final fallbackResult = await _lookupCountryFromCountriesDev(ipAddress);
    if (fallbackResult != null) {
      _debugLog(
        'Country lookup succeeded with countries.dev: '
        '${fallbackResult.countryCode}',
      );
      return fallbackResult;
    }

    _debugLog('countries.dev returned no usable country data; trying ipapi.co');
    final lastResult = await _lookupCountryFromIpApi(ipAddress);
    _debugLog(
      lastResult == null
          ? 'Country lookup failed in all providers'
          : 'Country lookup succeeded with ipapi.co: ${lastResult.countryCode}',
    );
    return lastResult;
  }

  static Future<EndpointCountryInfo?> _lookupCountryFromIpWho(
    String ipAddress,
  ) async {
    try {
      final body = await _getJson(Uri.parse('https://ipwho.is/$ipAddress'));
      if (body == null || body['success'] == false) {
        return null;
      }

      return _countryInfoFromFields(
        countryCode: body['country_code'],
        countryName: body['country'],
      );
    } catch (_) {
      return null;
    }
  }

  static Future<EndpointCountryInfo?> _lookupCountryFromIpApi(
    String ipAddress,
  ) async {
    try {
      final body = await _getJson(
        Uri.parse('https://ipapi.co/$ipAddress/json/'),
      );
      if (body == null || body['error'] == true) {
        return null;
      }

      return _countryInfoFromFields(
        countryCode: body['country_code'] ?? body['country'],
        countryName: body['country_name'] ?? body['country'],
      );
    } catch (_) {
      return null;
    }
  }

  static Future<EndpointCountryInfo?> _lookupCountryFromCountriesDev(
    String ipAddress,
  ) async {
    try {
      final body = await _getJson(
        Uri.parse('https://countries.dev/ip/$ipAddress'),
      );
      if (body == null) {
        return null;
      }

      final country = body['country'];
      final countryMap = country is Map ? country : null;
      return _countryInfoFromFields(
        countryCode:
            body['countryCode'] ?? countryMap?['alpha2Code'] ?? country,
        countryName: countryMap?['name'] ?? body['country_name'] ?? country,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    try {
      final request = await _httpClient
          .getUrl(uri)
          .timeout(const Duration(seconds: 5));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      _debugLog(
        'Country API ${uri.host} responded with ${response.statusCode}',
      );
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }

      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 5));
      final decodedBody = jsonDecode(responseBody);
      if (decodedBody is! Map) {
        return null;
      }

      return decodedBody.cast<String, dynamic>();
    } catch (error) {
      _debugLog('Country API request failed for ${uri.host}: $error');
      return null;
    }
  }

  static void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint('[EndpointCountry] $message');
    }
  }

  static EndpointCountryInfo? _countryInfoFromFields({
    required Object? countryCode,
    required Object? countryName,
  }) {
    final normalizedCountryCode = countryCode is String
        ? countryCode.trim()
        : null;
    final normalizedCountryName = countryName is String
        ? countryName.trim()
        : null;
    if (normalizedCountryCode == null ||
        normalizedCountryCode.length != 2 ||
        !RegExp(r'^[A-Za-z]{2}$').hasMatch(normalizedCountryCode)) {
      return null;
    }
    if (normalizedCountryName == null || normalizedCountryName.isEmpty) {
      return null;
    }

    return EndpointCountryInfo(
      countryCode: normalizedCountryCode.toUpperCase(),
      countryName: normalizedCountryName,
    );
  }
}
