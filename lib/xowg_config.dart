enum ImportedConfigProtocol { wireGuard, amneziaWireGuard, xowg }

class XowgConfig {
  const XowgConfig({required this.endpoint, required this.accessKey});

  static const String marker = 'hyperwg';
  static bool supportsProtocol(String? value) =>
      const {'hyperwg', 'xowg'}.contains(value?.toLowerCase());
  static const Set<String> _allowedFields = <String>{
    'version',
    'endpoint',
    'accesskey',
  };

  final Uri endpoint;
  final String accessKey;

  Uri get enrollmentUri {
    final segments = List<String>.from(endpoint.pathSegments)
      ..removeWhere((segment) => segment.isEmpty);
    if (segments.length >= 2 &&
        segments[segments.length - 2].toLowerCase() == 'api' &&
        segments.last.toLowerCase() == 'enroll') {
      return endpoint;
    }
    if (segments.isNotEmpty && segments.last.toLowerCase() == 'api') {
      segments.add('enroll');
    } else {
      segments.addAll(const ['api', 'enroll']);
    }
    return endpoint.replace(pathSegments: segments);
  }

  Map<String, dynamic> toParsedConfig() {
    return <String, dynamic>{
      'isValid': true,
      'protocol': marker,
      'global': <String, String>{
        'Version': '1',
        'Endpoint': endpoint.toString(),
        'AccessKey': '••••••••',
      },
      'interfaces': <Map<String, String>>[],
      'peers': <Map<String, String>>[],
    };
  }

  static bool hasMarker(String content) {
    for (final rawLine in content.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
        continue;
      }
      return supportsProtocol(line);
    }
    return false;
  }

  static XowgConfig parse(String content) {
    if (!hasMarker(content)) {
      throw const FormatException('HyperWG marker is missing');
    }

    final values = <String, String>{};
    var markerSeen = false;
    for (final rawLine in content.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
        continue;
      }
      if (!markerSeen) {
        markerSeen = true;
        continue;
      }
      if (line.startsWith('[') && line.endsWith(']')) {
        throw const FormatException('Sections are not allowed in HyperWG config');
      }

      final separatorIndex = line.indexOf('=');
      if (separatorIndex <= 0) {
        throw FormatException('Invalid HyperWG line: $line');
      }
      final key = line.substring(0, separatorIndex).trim().toLowerCase();
      final value = line.substring(separatorIndex + 1).trim();
      if (value.isEmpty || values.containsKey(key)) {
        throw FormatException('Invalid HyperWG field: $key');
      }
      if (!_allowedFields.contains(key)) {
        throw FormatException('Unsupported HyperWG field: $key');
      }
      values[key] = value;
    }

    if (values['version'] != '1') {
      throw const FormatException('Unsupported HyperWG config version');
    }

    final rawEndpoint = values['endpoint'];
    final accessKey = values['accesskey'];
    if (rawEndpoint == null || accessKey == null) {
      throw const FormatException('Endpoint and AccessKey are required');
    }

    final endpoint = Uri.tryParse(rawEndpoint);
    if (endpoint == null ||
        !endpoint.hasAuthority ||
        endpoint.host.isEmpty ||
        !const {'http', 'https'}.contains(endpoint.scheme.toLowerCase()) ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasFragment ||
        endpoint.hasQuery) {
      throw const FormatException('Endpoint must be an absolute HTTP(S) URL');
    }

    return XowgConfig(endpoint: endpoint, accessKey: accessKey);
  }
}
