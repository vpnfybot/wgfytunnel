import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wgfytunnel/app_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('de.ffuf.in_app_update/methods');
  final calls = <String>[];

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    calls.clear();
  });

  Map<String, Object?> updateInfo({
    required bool flexibleAllowed,
    required bool immediateAllowed,
  }) {
    return <String, Object?>{
      'updateAvailability': 2,
      'immediateAllowed': immediateAllowed,
      'immediateAllowedPreconditions': <int>[],
      'flexibleAllowed': flexibleAllowed,
      'flexibleAllowedPreconditions': <int>[],
      'availableVersionCode': 63,
      'installStatus': 0,
      'packageName': 'com.wgfytunnel',
      'clientVersionStalenessDays': 1,
      'updatePriority': 0,
    };
  }

  test('prefers a flexible update when both flows are available', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return updateInfo(flexibleAllowed: true, immediateAllowed: true);
        });

    final update = await AppUpdateService.checkForUpdate();

    expect(update?.flow, AppUpdateFlow.flexible);
    expect(update?.availableVersionCode, 63);
    expect(calls, <String>['checkForUpdate']);
  });

  test(
    'uses the Play Store when only an immediate update is available',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return updateInfo(flexibleAllowed: false, immediateAllowed: true);
          });

      final update = await AppUpdateService.checkForUpdate();

      expect(update?.flow, AppUpdateFlow.playStore);
    },
  );

  test(
    'does not invoke the blocking Play updater for a store fallback',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return null;
          });

      final started = await AppUpdateService.startUpdate(
        const PendingAppUpdate(flow: AppUpdateFlow.playStore),
      );

      expect(started, isFalse);
      expect(calls, isEmpty);
    },
  );

  test('completes a successful flexible update', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });

    final started = await AppUpdateService.startUpdate(
      const PendingAppUpdate(flow: AppUpdateFlow.flexible),
    );

    expect(started, isTrue);
    expect(calls, <String>['startFlexibleUpdate', 'completeFlexibleUpdate']);
  });
}
