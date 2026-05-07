import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

enum AppUpdateFlow {
  immediate,
  flexible,
  playStore,
}

class PendingAppUpdate {
  const PendingAppUpdate({
    required this.flow,
    this.availableVersionCode,
  });

  final AppUpdateFlow flow;
  final int? availableVersionCode;
}

class AppUpdateService {
  const AppUpdateService._();

  static Future<PendingAppUpdate?> checkForUpdate() async {
    try {
      final updateInfo = await InAppUpdate.checkForUpdate();
      if (updateInfo.updateAvailability != UpdateAvailability.updateAvailable) {
        return null;
      }

      final flow = updateInfo.immediateUpdateAllowed
          ? AppUpdateFlow.immediate
          : updateInfo.flexibleUpdateAllowed
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
        case AppUpdateFlow.immediate:
          await InAppUpdate.performImmediateUpdate();
          return true;
        case AppUpdateFlow.flexible:
          await InAppUpdate.startFlexibleUpdate();
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