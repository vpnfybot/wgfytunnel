import 'dart:convert';
import 'dart:io';

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
      return '🌐';
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
      return null;
    }

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
      final addresses = await InternetAddress.lookup(host).timeout(
        const Duration(seconds: 5),
      );
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

  static Future<EndpointCountryInfo?> _lookupCountryForIp(String ipAddress) async {
    try {
      final request = await _httpClient
          .getUrl(Uri.parse('https://ipwho.is/$ipAddress'))
          .timeout(const Duration(seconds: 5));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close().timeout(const Duration(seconds: 5));
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }

      final responseBody = await response.transform(utf8.decoder).join();
      final decodedBody = jsonDecode(responseBody);
      if (decodedBody is! Map) {
        return null;
      }

      final normalizedBody = decodedBody.cast<String, dynamic>();
      if (normalizedBody['success'] == false) {
        return null;
      }

      final countryCode = (normalizedBody['country_code'] as String?)?.trim();
      final countryName = (normalizedBody['country'] as String?)?.trim();
      if (countryCode == null || countryCode.isEmpty) {
        return null;
      }
      if (countryName == null || countryName.isEmpty) {
        return null;
      }

      return EndpointCountryInfo(
        countryCode: countryCode.toUpperCase(),
        countryName: countryName,
      );
    } catch (_) {
      return null;
    }
  }
}