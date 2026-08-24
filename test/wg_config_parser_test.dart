import 'package:flutter_test/flutter_test.dart';
import 'package:wgfytunnel/wg_config_parser.dart';

void main() {
  test('does not leak values from unknown sections into global values', () {
    final parsed = parseWireguardConfig('''
[Interface]
PrivateKey = private-key
Address = 10.0.0.2/32

[Metadata]
PrivateKey = not-a-wireguard-key
Address = not-an-address
''');

    expect(parsed['isValid'], isTrue);
    expect(parsed['global'], isNull);
    expect(
      (parsed['interfaces'] as List).single,
      containsPair('Address', '10.0.0.2/32'),
    );
  });

  test('accepts a valid interface after an incomplete interface', () {
    final parsed = parseWireguardConfig('''
[Interface]
PrivateKey =
Address =

[Interface]
PrivateKey = private-key
Address = 10.0.0.2/32
''');

    expect(parsed['isValid'], isTrue);
  });

  test('does not treat an empty key as a global setting', () {
    final parsed = parseWireguardConfig(' = value\n');

    expect(parsed['global'], isNull);
    expect(parsed['isValid'], isFalse);
  });
}
