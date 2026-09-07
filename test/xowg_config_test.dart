import 'package:flutter_test/flutter_test.dart';
import 'package:wgfytunnel/xowg_config.dart';

void main() {
  test('accepts HyperWG and legacy XOWG with a canonical protocol label', () {
    for (final marker in ['hyperwg', 'HyperWG', 'xowg']) {
      final config = XowgConfig.parse('''
$marker
Version = 1
Endpoint = https://vpn.example.test
AccessKey = shared-secret
''');
      expect(config.toParsedConfig()['protocol'], 'hyperwg');
    }
  });
  test('parses the xowg marker and builds the enrollment endpoint', () {
    final config = XowgConfig.parse('''
xowg
Version = 1
Endpoint = https://vpn.example.test/control
AccessKey = shared-secret
''');

    expect(
      config.enrollmentUri.toString(),
      'https://vpn.example.test/control/api/enroll',
    );
    expect(config.accessKey, 'shared-secret');
    expect(config.toParsedConfig()['isValid'], isTrue);
    expect(
      (config.toParsedConfig()['global'] as Map)['AccessKey'],
      isNot('shared-secret'),
    );
  });

  test('accepts an Endpoint that already points to api/enroll', () {
    final config = XowgConfig.parse('''
xowg
Version = 1
Endpoint = https://vpn.example.test/api/enroll
AccessKey = shared-secret
''');

    expect(
      config.enrollmentUri.toString(),
      'https://vpn.example.test/api/enroll',
    );
  });

  test('does not identify a native WireGuard config as XOWG', () {
    expect(
      XowgConfig.hasMarker('''
# xowg
[Interface]
PrivateKey = private-key
Address = 10.0.0.2/32
'''),
      isFalse,
    );
  });

  test('rejects an incomplete XOWG provisioning config', () {
    expect(
      () => XowgConfig.parse('xowg\nVersion = 1\n'),
      throwsFormatException,
    );
  });

  test('rejects removed ApiUrl, Name, and Transport fields', () {
    for (final removedField in const <String>[
      'ApiUrl = https://vpn.example.test',
      'Name = Family',
      'Transport = amneziawg',
    ]) {
      expect(
        () => XowgConfig.parse('''
xowg
Version = 1
Endpoint = https://vpn.example.test
AccessKey = shared-secret
$removedField
'''),
        throwsFormatException,
      );
    }
  });
}
