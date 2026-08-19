import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wgfytunnel/imported_configs_prefs.dart';
import 'package:wgfytunnel/endpoint_country_service.dart';

void main() {
  test('persists endpoint country information between app launches', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await ImportedConfigsPrefs.saveCountryInfoCache(
      <String, EndpointCountryInfo>{
        '193.233.49.168': const EndpointCountryInfo(
          countryCode: 'RU',
          countryName: 'Russia',
        ),
      },
    );

    final restored = await ImportedConfigsPrefs.loadCountryInfoCache();

    expect(restored, hasLength(1));
    expect(restored['193.233.49.168']?.countryCode, 'RU');
    expect(restored['193.233.49.168']?.countryName, 'Russia');
  });
}
