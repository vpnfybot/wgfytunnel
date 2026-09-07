import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wgfytunnel/xowg_device_identity.dart';

void main() {
  test('generates and persists one stable random device id', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();

    final first = await XowgDeviceIdentity.loadOrCreate(
      preferences: preferences,
    );
    final second = await XowgDeviceIdentity.loadOrCreate(
      preferences: preferences,
    );

    expect(second, first);
    expect(
      first,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });
}
