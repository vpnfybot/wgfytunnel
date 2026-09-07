import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

enum AppUpdateFlow { flexible, playStore }

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

      // Never start the blocking immediate flow from the app. On some devices
      // Google Play intermittently replaces the app with its own generic
      // "Something went wrong" screen. A flexible update is non-blocking; when
      // it is unavailable, the caller opens the regular Play Store listing.
      final flow = updateInfo.flexibleUpdateAllowed
          ? AppUpdateFlow.flexible
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
