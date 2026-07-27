import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

enum AppUpdateFlow { flexible, immediate, playStore }

class PendingAppUpdate {
  const PendingAppUpdate({required this.flow, this.availableVersionCode});

  final AppUpdateFlow flow;
  final int? availableVersionCode;
}

class AppUpdateService {
  const AppUpdateService._();

  static const Duration _checkTimeout = Duration(seconds: 10);

  static Future<PendingAppUpdate?> checkForUpdate() async {
    try {
      final updateInfo = await InAppUpdate.checkForUpdate().timeout(
        _checkTimeout,
      );
      if (updateInfo.updateAvailability != UpdateAvailability.updateAvailable) {
        return null;
      }

      // Prefer a flexible update. An immediate update hands control to a
      // blocking Google Play activity, which is much more sensitive to Play
      // Store startup/availability issues and can show a system error dialog.
      final flow = updateInfo.flexibleUpdateAllowed
          ? AppUpdateFlow.flexible
          : updateInfo.immediateUpdateAllowed
          ? AppUpdateFlow.immediate
          : AppUpdateFlow.playStore;

      return PendingAppUpdate(
        flow: flow,
        availableVersionCode: updateInfo.availableVersionCode,
      );
    } catch (error, stackTrace) {
      debugPrint('App update check skipped: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  static Future<bool> startUpdate(PendingAppUpdate update) async {
    try {
      switch (update.flow) {
        case AppUpdateFlow.flexible:
          final result = await InAppUpdate.startFlexibleUpdate();
          if (result == AppUpdateResult.userDeniedUpdate) {
            return true;
          }
          if (result != AppUpdateResult.success) {
            return false;
          }
          await InAppUpdate.completeFlexibleUpdate();
          return true;
        case AppUpdateFlow.immediate:
          final result = await InAppUpdate.performImmediateUpdate();
          // Cancellation is a completed user interaction and must not
          // unexpectedly redirect the user to the Play Store.
          return result != AppUpdateResult.inAppUpdateFailed;
        case AppUpdateFlow.playStore:
          return false;
      }
    } catch (error, stackTrace) {
      debugPrint('App update start failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }
}
