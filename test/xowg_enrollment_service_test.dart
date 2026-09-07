import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wgfytunnel/xowg_config.dart';
import 'package:wgfytunnel/xowg_enrollment_service.dart';

void main() {
  for (final profile in <String>[
    'off',
    'interactive',
    'web',
    'streaming',
    'mixed',
    'unknown',
  ]) {
    test('negotiates TrafficMorpher profile $profile', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.created
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, dynamic>{
              'tunnel': <String, String>{
                'protocol': 'hyperwg',
                'traffic_morpher': profile,
              },
              'native_config': _nativeXowgConfig,
            }),
          );
        await request.response.close();
      });
      try {
        final config = XowgConfig.parse('''
hyperwg
Version = 1
Endpoint = http://127.0.0.1:${server.port}
AccessKey = access-key
''');
        final future = const XowgEnrollmentService().enroll(
          config: config,
          deviceId: '12345678-1234-4123-8123-123456789abc',
        );
        if (profile == 'unknown') {
          await expectLater(
            future,
            throwsA(
              isA<XowgEnrollmentException>().having(
                (error) => error.code,
                'code',
                'unsupported_traffic_morpher',
              ),
            ),
          );
        } else {
          final result = await future;
          expect(
            result.nativeConfig,
            contains('[Interface]\nTrafficMorpher = $profile\n'),
          );
          expect(
            result.nativeConfig,
            contains('HeaderProtectionKey = header-key'),
          );
          expect(result.nativeConfig, contains('Endpoint = 127.0.0.1:51820'));
        }
      } finally {
        await server.close(force: true);
      }
    });
  }

  test('sends device_id and accepts the issued native config', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, dynamic>? receivedBody;
    server.listen((request) async {
      receivedBody =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
      request.response
        ..statusCode = HttpStatus.created
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, dynamic>{
            'tunnel': <String, String>{'protocol': 'hyperwg'},
            'native_config': _nativeXowgConfig,
            'evicted_device': <String, String>{'external_id': 'old-device'},
          }),
        );
      await request.response.close();
    });

    try {
      final config = XowgConfig.parse('''
xowg
Version = 1
Endpoint = http://127.0.0.1:${server.port}
AccessKey = access-key
''');
      final result = await const XowgEnrollmentService().enroll(
        config: config,
        deviceId: '12345678-1234-4123-8123-123456789abc',
      );

      expect(receivedBody, containsPair('access_key', 'access-key'));
      expect(
        receivedBody,
        containsPair('device_id', '12345678-1234-4123-8123-123456789abc'),
      );
      expect(result.nativeConfig, _nativeXowgConfig);
      expect(result.evictedDeviceId, 'old-device');
    } finally {
      await server.close(force: true);
    }
  });

  test('surfaces the API error without accepting a config', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, String>{
            'error': 'Access key is invalid',
            'code': 'invalid_access_key',
          }),
        );
      await request.response.close();
    });

    try {
      final config = XowgConfig.parse('''
xowg
Version = 1
Endpoint = http://127.0.0.1:${server.port}/api
AccessKey = invalid
''');

      await expectLater(
        const XowgEnrollmentService().enroll(
          config: config,
          deviceId: '12345678-1234-4123-8123-123456789abc',
        ),
        throwsA(
          isA<XowgEnrollmentException>()
              .having((error) => error.code, 'code', 'invalid_access_key')
              .having(
                (error) => error.message,
                'message',
                'Access key is invalid',
              ),
        ),
      );
    } finally {
      await server.close(force: true);
    }
  });
}

const String _nativeXowgConfig = '''
[Interface]
PrivateKey = private-key
Address = 10.0.0.2/32
Jc = 6
Jmin = 10
Jmax = 50
S1 = 16
S2 = 16
H1 = 1
H2 = 2
HeaderProtectionKey = header-key
ContentPaddingAddition = 10-100

[Peer]
PublicKey = public-key
AllowedIPs = 0.0.0.0/0
Endpoint = 127.0.0.1:51820
''';
