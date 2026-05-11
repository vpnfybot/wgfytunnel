import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'imported_configs_prefs.dart';
import 'l10n/app_localizations.dart';
import 'wg_config_parser.dart';

const String subscriptionBackgroundTaskUniqueName =
    'com.wgfytunnel.subscription.maintenance';
const String subscriptionBackgroundTaskName = 'subscriptionMaintenance';

@pragma('vm:entry-point')
void subscriptionBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != subscriptionBackgroundTaskName) {
      return true;
    }

    try {
      await SubscriptionService.runBackgroundMaintenance();
      return true;
    } catch (_) {
      return false;
    }
  });
}

class SubscriptionService {
  static const Duration refreshInterval = Duration(hours: 2);
  static const Duration backgroundCheckInterval = Duration(minutes: 20);
  static const Duration _subscriptionRequestTimeout = Duration(seconds: 20);
  static const List<int> _expiryNotificationThresholdHours = <int>[
    24,
    48,
    72,
  ];

  static const String _activeUntilByPathKey =
      'subscription_active_until_by_path';
  static const String _expiredNotifiedPathsKey =
      'subscription_expired_notified_paths';
  static const String _lastRefreshAtMillisKey =
      'subscription_last_refresh_at_millis';

  static const String _notificationChannelId = 'subscription_expiration';
  static const String _notificationChannelName = 'Subscription expiration';
  static const String _notificationChannelDescription =
      'Subscription expiration alerts';
  static const String _appLanguageKey = 'app_language';

  static final HttpClient _subinfoHttpClient = HttpClient()
    ..connectionTimeout = _subscriptionRequestTimeout;
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static bool _notificationsInitialized = false;
  static bool _backgroundWorkInitialized = false;

  static Future<void> initializeAndroidAutomation() async {
    if (!Platform.isAndroid) {
      return;
    }

    await _ensureNotificationsInitialized();
    if (!_backgroundWorkInitialized) {
      await Workmanager().initialize(subscriptionBackgroundDispatcher);
      _backgroundWorkInitialized = true;
    }

    await Workmanager().registerPeriodicTask(
      subscriptionBackgroundTaskUniqueName,
      subscriptionBackgroundTaskName,
      frequency: backgroundCheckInterval,
      flexInterval: const Duration(minutes: 5),
      initialDelay: backgroundCheckInterval,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  static Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) {
      return false;
    }

    await _ensureNotificationsInitialized();
    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await androidImplementation?.requestNotificationsPermission() ??
        false;
  }

  static Future<bool?> areNotificationsEnabled() async {
    if (!Platform.isAndroid) {
      return null;
    }

    await _ensureNotificationsInitialized();
    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await androidImplementation?.areNotificationsEnabled();
  }

  static Future<bool> shouldRefreshSubscriptions({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final lastRefreshAtMillis = prefs.getInt(_lastRefreshAtMillisKey);
    if (lastRefreshAtMillis == null) {
      return true;
    }

    final comparisonTime = now ?? DateTime.now();
    final lastRefreshAt = DateTime.fromMillisecondsSinceEpoch(
      lastRefreshAtMillis,
    );
    return comparisonTime.difference(lastRefreshAt) >= refreshInterval;
  }

  static Future<Map<String, String>> loadStoredActiveUntilByPath() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final rawValue = prefs.getString(_activeUntilByPathKey);
    if (rawValue == null || rawValue.trim().isEmpty) {
      return <String, String>{};
    }

    try {
      final decodedValue = jsonDecode(rawValue);
      if (decodedValue is! Map) {
        return <String, String>{};
      }

      final result = <String, String>{};
      decodedValue.forEach((key, value) {
        if (key is! String) {
          return;
        }

        final formattedValue = _formatSubscriptionActiveUntil(
          _extractForDateValue(value),
        );
        if (formattedValue != null) {
          result[key] = formattedValue;
        }
      });
      return result;
    } catch (_) {
      return <String, String>{};
    }
  }

  static Future<void> saveStoredActiveUntilByPath(
    Map<String, String> activeUntilByPath,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (activeUntilByPath.isEmpty) {
      await prefs.remove(_activeUntilByPathKey);
      return;
    }

    await prefs.setString(
      _activeUntilByPathKey,
      jsonEncode(activeUntilByPath),
    );
  }

  static Future<void> removeConfigPathState(String path) async {
    final activeUntilByPath = await loadStoredActiveUntilByPath();
    if (activeUntilByPath.remove(path) != null) {
      await saveStoredActiveUntilByPath(activeUntilByPath);
    }

    final notifiedPaths = await _loadExpiredNotifiedPaths();
    if (_removeNotificationCheckpointsForPath(notifiedPaths, path)) {
      await _saveExpiredNotifiedPaths(notifiedPaths);
    }
  }

  static Future<void> renameConfigPathState(
    String oldPath,
    String newPath,
  ) async {
    final activeUntilByPath = await loadStoredActiveUntilByPath();
    final activeUntil = activeUntilByPath.remove(oldPath);
    if (activeUntil != null) {
      activeUntilByPath[newPath] = activeUntil;
      await saveStoredActiveUntilByPath(activeUntilByPath);
    }

    final notifiedPaths = await _loadExpiredNotifiedPaths();
    var hasNotificationStateChanged = false;
    final updatedNotifiedPaths = notifiedPaths.map((entry) {
      final updatedEntry = _renameNotificationCheckpointPath(
        entry,
        oldPath,
        newPath,
      );
      if (updatedEntry != entry) {
        hasNotificationStateChanged = true;
      }
      return updatedEntry;
    }).toSet();
    if (hasNotificationStateChanged) {
      await _saveExpiredNotifiedPaths(updatedNotifiedPaths);
    }
  }

  static void _syncNotificationCheckpointsForActiveUntil(
    Set<String> checkpoints,
    String path,
    String activeUntil,
  ) {
    final hadLegacyExpiredNotification = checkpoints.remove(path);
    checkpoints.removeWhere(
      (entry) =>
          _notificationEntryMatchesPath(entry, path) &&
          !_notificationEntryMatchesActiveUntil(entry, path, activeUntil),
    );
    if (hadLegacyExpiredNotification && isSubscriptionExpired(activeUntil)) {
      checkpoints.add(_notificationCheckpointKey(path, activeUntil, 0));
    }
  }

  static bool _removeNotificationCheckpointsForPath(
    Set<String> checkpoints,
    String path,
  ) {
    final originalLength = checkpoints.length;
    checkpoints.removeWhere((entry) => _notificationEntryMatchesPath(entry, path));
    return checkpoints.length != originalLength;
  }

  static bool _notificationEntryMatchesPath(String entry, String path) {
    return entry == path || entry.startsWith('$path|');
  }

  static bool _notificationEntryMatchesActiveUntil(
    String entry,
    String path,
    String activeUntil,
  ) {
    return entry.startsWith('$path|$activeUntil|');
  }

  static bool _notificationEntryMatchesImportedPaths(
    String entry,
    Set<String> importedPaths,
  ) {
    return importedPaths.any((path) => _notificationEntryMatchesPath(entry, path));
  }

  static String _notificationCheckpointKey(
    String path,
    String activeUntil,
    int hoursBeforeExpiry,
  ) {
    return '$path|$activeUntil|$hoursBeforeExpiry';
  }

  static String _renameNotificationCheckpointPath(
    String entry,
    String oldPath,
    String newPath,
  ) {
    if (entry == oldPath) {
      return newPath;
    }
    if (entry.startsWith('$oldPath|')) {
      return '$newPath${entry.substring(oldPath.length)}';
    }
    return entry;
  }

  static int? _notificationCheckpointHours(String activeUntil) {
    final expiresAt = _parseSubscriptionDate(activeUntil);
    if (expiresAt == null) {
      return null;
    }

    final expiryMoment = expiresAt.add(const Duration(days: 1));
    final remaining = expiryMoment.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      return 0;
    }

    for (final hours in _expiryNotificationThresholdHours) {
      if (remaining <= Duration(hours: hours)) {
        return hours;
      }
    }

    return null;
  }

  static Future<AppLanguage> _loadNotificationLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLanguage = prefs.getString(_appLanguageKey);
    return savedLanguage == 'en' ? AppLanguage.en : AppLanguage.ru;
  }

  static String _configDisplayName(String path) {
    return path.split(Platform.pathSeparator).last;
  }

  static String _notificationTitleForHours(
    AppLanguage language,
    String configPath,
    int hoursBeforeExpiry,
  ) {
    final l10n = AppLocalizations(language);
    final configName = _configDisplayName(configPath);
    if (hoursBeforeExpiry == 0) {
      return l10n.subscriptionExpiredNotificationForConfig(configName);
    }
    return l10n.subscriptionExpiringLessThan48HoursForConfig(configName);
  }

  static String? _notificationBodyForHours(int hoursBeforeExpiry) {
    if (hoursBeforeExpiry == 0) {
      return null;
    }
    return null;
  }

  static const NotificationDetails _subscriptionNotificationDetails =
      NotificationDetails(
        android: AndroidNotificationDetails(
          _notificationChannelId,
          _notificationChannelName,
          channelDescription: _notificationChannelDescription,
          icon: 'ic_stat_vpnfy',
          importance: Importance.max,
          priority: Priority.high,
        ),
      );

  static Future<({String? activeUntil, Object? error})>
  updateSubscriptionForPath(String configPath) async {
    final file = File(configPath);
    if (!await file.exists()) {
      await removeConfigPathState(configPath);
      return (activeUntil: null, error: FileSystemException('Config not found', configPath));
    }

    final parsedConfig = await _readParsedConfig(file);
    if (parsedConfig == null) {
      return (
        activeUntil: null,
        error: 'Не удалось прочитать выбранную конфигурацию',
      );
    }

    final host = _configEndpointHost(parsedConfig);
    final privateKey = _configPrivateKey(parsedConfig);
    if (host == null || privateKey == null) {
      return (
        activeUntil: null,
        error: 'Не удалось найти host или PrivateKey в выбранной конфигурации',
      );
    }

    final requestResult = await _requestSubscriptionActiveUntil(
      host: host,
      privateKey: privateKey,
    );
    if (requestResult.error != null) {
      return requestResult;
    }

    final activeUntil = requestResult.activeUntil;
    if (activeUntil == null) {
      return (activeUntil: null, error: null);
    }

    final activeUntilByPath = await loadStoredActiveUntilByPath();
    activeUntilByPath[configPath] = activeUntil;
    await saveStoredActiveUntilByPath(activeUntilByPath);

    final notifiedPaths = await _loadExpiredNotifiedPaths();
    _syncNotificationCheckpointsForActiveUntil(
      notifiedPaths,
      configPath,
      activeUntil,
    );
    await _saveExpiredNotifiedPaths(notifiedPaths);

    return (activeUntil: activeUntil, error: null);
  }

  static Future<Map<String, String>> refreshAllSubscriptions({
    List<String>? configPaths,
    bool markAsRefreshed = true,
  }) async {
    final isFullRefresh = configPaths == null;
    final paths = (configPaths ?? await ImportedConfigsPrefs.loadPaths())
        .where((path) => path.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);

    var activeUntilByPath = await loadStoredActiveUntilByPath();
    final notifiedPaths = await _loadExpiredNotifiedPaths();

    for (final path in paths) {
      final result = await updateSubscriptionForPath(path);
      if (result.activeUntil != null) {
        activeUntilByPath[path] = result.activeUntil!;
        _syncNotificationCheckpointsForActiveUntil(
          notifiedPaths,
          path,
          result.activeUntil!,
        );
      } else if (!await File(path).exists()) {
        activeUntilByPath.remove(path);
        _removeNotificationCheckpointsForPath(notifiedPaths, path);
      }
    }

    if (isFullRefresh) {
      final importedPathSet = paths.toSet();
      activeUntilByPath = Map<String, String>.fromEntries(
        activeUntilByPath.entries.where(
          (entry) => importedPathSet.contains(entry.key),
        ),
      );
      notifiedPaths.removeWhere(
        (entry) => !_notificationEntryMatchesImportedPaths(entry, importedPathSet),
      );
    }

    await saveStoredActiveUntilByPath(activeUntilByPath);
    await _saveExpiredNotifiedPaths(notifiedPaths);

    if (markAsRefreshed) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastRefreshAtMillisKey, DateTime.now().millisecondsSinceEpoch);
    }

    return activeUntilByPath;
  }

  static Future<void> runBackgroundMaintenance() async {
    if (!Platform.isAndroid) {
      return;
    }

    await _ensureNotificationsInitialized();
    if (await shouldRefreshSubscriptions()) {
      await refreshAllSubscriptions();
    }
    await notifyExpiredSubscriptionsIfNeeded();
  }

  static Future<int> notifyExpiredSubscriptionsIfNeeded() async {
    if (!Platform.isAndroid) {
      return 0;
    }

    await _ensureNotificationsInitialized();
    final importedPaths = (await ImportedConfigsPrefs.loadPaths()).toSet();
    final activeUntilByPath = await loadStoredActiveUntilByPath();
    final notifiedPaths = await _loadExpiredNotifiedPaths();
    final notificationLanguage = await _loadNotificationLanguage();
    var shownNotificationsCount = 0;

    notifiedPaths.removeWhere(
      (entry) => !_notificationEntryMatchesImportedPaths(entry, importedPaths),
    );

    for (final entry in activeUntilByPath.entries) {
      if (!importedPaths.contains(entry.key)) {
        continue;
      }

      final notificationHours = _notificationCheckpointHours(entry.value);
      if (notificationHours == null) {
        continue;
      }

      final checkpointKey = _notificationCheckpointKey(
        entry.key,
        entry.value,
        notificationHours,
      );
      final hasLegacyExpiredNotification =
          notificationHours == 0 && notifiedPaths.contains(entry.key);
      if (hasLegacyExpiredNotification || notifiedPaths.contains(checkpointKey)) {
        continue;
      }

      await _notificationsPlugin.show(
        _notificationIdForPath(entry.key),
        _notificationTitleForHours(
          notificationLanguage,
          entry.key,
          notificationHours,
        ),
        _notificationBodyForHours(notificationHours),
        _subscriptionNotificationDetails,
      );
      notifiedPaths.add(checkpointKey);
      shownNotificationsCount += 1;
    }

    await _saveExpiredNotifiedPaths(notifiedPaths);
    return shownNotificationsCount;
  }

  static bool isSubscriptionExpired(String activeUntil) {
    final expiresAt = _parseSubscriptionDate(activeUntil);
    if (expiresAt == null) {
      return false;
    }

    final now = DateTime.now();
    final currentDate = DateTime(now.year, now.month, now.day);
    return currentDate.isAfter(expiresAt);
  }

  static Future<void> _ensureNotificationsInitialized() async {
    if (_notificationsInitialized || !Platform.isAndroid) {
      return;
    }

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _notificationsPlugin.initialize(initializationSettings);

    const notificationChannel = AndroidNotificationChannel(
      _notificationChannelId,
      _notificationChannelName,
      description: _notificationChannelDescription,
      importance: Importance.max,
    );
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(notificationChannel);

    _notificationsInitialized = true;
  }

  static Future<Set<String>> _loadExpiredNotifiedPaths() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return (prefs.getStringList(_expiredNotifiedPathsKey) ?? const <String>[])
        .toSet();
  }

  static Future<void> _saveExpiredNotifiedPaths(Set<String> paths) async {
    final prefs = await SharedPreferences.getInstance();
    if (paths.isEmpty) {
      await prefs.remove(_expiredNotifiedPathsKey);
      return;
    }

    await prefs.setStringList(
      _expiredNotifiedPathsKey,
      paths.toList(growable: false),
    );
  }

  static Future<Map<String, dynamic>?> _readParsedConfig(File file) async {
    try {
      final content = await file.readAsString();
      final parsedConfig = parseWireguardConfig(content);
      if (parsedConfig['isValid'] != true) {
        return null;
      }

      return parsedConfig;
    } catch (_) {
      return null;
    }
  }

  static Future<({String? activeUntil, Object? error})>
  _requestSubscriptionActiveUntil({
    required String host,
    required String privateKey,
  }) async {
    final payload = jsonEncode(<String, String>{
      'host': host,
      'private_key': privateKey,
    });

    Object? lastError;
    for (final uri in _subinfoRequestUris()) {
      try {
        final request = await _subinfoHttpClient.postUrl(uri).timeout(
          _subscriptionRequestTimeout,
        );
        request.persistentConnection = false;
        request.headers.contentType = ContentType.json;
        request.headers.set(
          HttpHeaders.cacheControlHeader,
          'no-cache, no-store, max-age=0, must-revalidate',
        );
        request.headers.set(HttpHeaders.pragmaHeader, 'no-cache');
        request.headers.set(HttpHeaders.expiresHeader, '0');
        request.add(utf8.encode(payload));

        final response = await request.close().timeout(
          _subscriptionRequestTimeout,
        );
        final responseText = await utf8.decoder.bind(response).join();
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return (
            activeUntil: _extractSubscriptionActiveUntil(responseText),
            error: null,
          );
        }

        final trimmedResponseText = responseText.trim();
        lastError = HttpException(
          trimmedResponseText.isEmpty
              ? 'HTTP ${response.statusCode}'
              : 'HTTP ${response.statusCode}: $trimmedResponseText',
          uri: uri,
        );
      } catch (error) {
        lastError = error;
      }
    }

    return (activeUntil: null, error: lastError);
  }

  static int _notificationIdForPath(String path) {
    var hash = 0;
    for (final codeUnit in path.codeUnits) {
      hash = 0x1fffffff & (hash + codeUnit);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= hash >> 6;
    }
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash ^= hash >> 11;
    hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
    return hash & 0x7fffffff;
  }

  static String? _firstNonEmptyValue(
    Map<String, String> values,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = values[key];
      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    return null;
  }

  static List<Map<String, String>> _stringSections(Object? value) {
    if (value is! List) {
      return const <Map<String, String>>[];
    }

    return value.whereType<Map>().map((entry) {
      return entry.map(
        (key, nestedValue) => MapEntry(key.toString(), nestedValue.toString()),
      );
    }).toList(growable: false);
  }

  static String _configEndpointText(Map<String, dynamic>? parsedConfig) {
    if (parsedConfig == null) {
      return '-';
    }

    final peers = _stringSections(parsedConfig['peers']);
    if (peers.isEmpty) {
      return '-';
    }

    return _firstNonEmptyValue(peers.first, const ['Endpoint']) ?? '-';
  }

  static String? _extractEndpointHost(String endpoint) {
    final trimmedEndpoint = endpoint.trim();
    if (trimmedEndpoint.isEmpty || trimmedEndpoint == '-') {
      return null;
    }

    if (trimmedEndpoint.startsWith('[')) {
      final closingBracketIndex = trimmedEndpoint.indexOf(']');
      if (closingBracketIndex <= 1) {
        return null;
      }

      return trimmedEndpoint.substring(1, closingBracketIndex).trim();
    }

    final colonMatches = ':'.allMatches(trimmedEndpoint).length;
    if (colonMatches == 0) {
      return trimmedEndpoint;
    }

    if (colonMatches == 1) {
      final separatorIndex = trimmedEndpoint.lastIndexOf(':');
      return trimmedEndpoint.substring(0, separatorIndex).trim();
    }

    final parsedAddress = InternetAddress.tryParse(trimmedEndpoint);
    if (parsedAddress != null) {
      return parsedAddress.address;
    }

    final separatorIndex = trimmedEndpoint.lastIndexOf(':');
    final possiblePort = trimmedEndpoint.substring(separatorIndex + 1).trim();
    if (separatorIndex > 0 && int.tryParse(possiblePort) != null) {
      return trimmedEndpoint.substring(0, separatorIndex).trim();
    }

    return trimmedEndpoint;
  }

  static String? _configEndpointHost(Map<String, dynamic>? parsedConfig) {
    return _extractEndpointHost(_configEndpointText(parsedConfig));
  }

  static String? _configPrivateKey(Map<String, dynamic>? parsedConfig) {
    if (parsedConfig == null) {
      return null;
    }

    final interfaces = _stringSections(parsedConfig['interfaces']);
    if (interfaces.isEmpty) {
      return null;
    }

    return _firstNonEmptyValue(interfaces.first, const ['PrivateKey']);
  }

  static List<Uri> _subinfoRequestUris() {
    return <Uri>[Uri.parse('https://vpnfybot.duckdns.org/subinfo')];
  }

  static String? _extractForDateValue(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is String) {
      final trimmedValue = value.trim();
      return trimmedValue.isEmpty ? null : trimmedValue;
    }

    if (value is num || value is bool) {
      return value.toString();
    }

    if (value is List) {
      for (final item in value) {
        final extractedValue = _extractForDateValue(item);
        if (extractedValue != null) {
          return extractedValue;
        }
      }

      return null;
    }

    if (value is Map) {
      final forDateValue = value['for_date'];
      if (forDateValue != null) {
        return _extractForDateValue(forDateValue);
      }

      for (final nestedValue in value.values) {
        final extractedValue = _extractForDateValue(nestedValue);
        if (extractedValue != null) {
          return extractedValue;
        }
      }
    }

    return null;
  }

  static String? _extractSubscriptionActiveUntil(String responseText) {
    final trimmedResponse = responseText.trim();
    if (trimmedResponse.isEmpty) {
      return null;
    }

    try {
      final decodedResponse = jsonDecode(trimmedResponse);
      return _formatSubscriptionActiveUntil(
        _extractForDateValue(decodedResponse),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _formatSubscriptionActiveUntil(String? value) {
    if (value == null) {
      return null;
    }

    final trimmedValue = value.trim();
    if (trimmedValue.isEmpty) {
      return null;
    }

    final dateOnlyMatch = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})$',
    ).firstMatch(trimmedValue);
    if (dateOnlyMatch != null) {
      return '${dateOnlyMatch.group(2)}.${dateOnlyMatch.group(3)}.${dateOnlyMatch.group(1)}';
    }

    final parsedDate = DateTime.tryParse(trimmedValue);
    if (parsedDate == null) {
      return trimmedValue;
    }

    final month = parsedDate.month.toString().padLeft(2, '0');
    final day = parsedDate.day.toString().padLeft(2, '0');
    final year = parsedDate.year.toString().padLeft(4, '0');
    return '$month.$day.$year';
  }

  static DateTime? _parseSubscriptionDate(String value) {
    final trimmedValue = value.trim();
    if (trimmedValue.isEmpty) {
      return null;
    }

    final mmddyyyyMatch = RegExp(
      r'^(\d{2})\.(\d{2})\.(\d{4})$',
    ).firstMatch(trimmedValue);
    if (mmddyyyyMatch != null) {
      final month = int.tryParse(mmddyyyyMatch.group(1)!);
      final day = int.tryParse(mmddyyyyMatch.group(2)!);
      final year = int.tryParse(mmddyyyyMatch.group(3)!);
      if (month == null || day == null || year == null) {
        return null;
      }

      return DateTime(year, month, day);
    }

    final parsedDate = DateTime.tryParse(trimmedValue);
    if (parsedDate == null) {
      return null;
    }

    return DateTime(parsedDate.year, parsedDate.month, parsedDate.day);
  }
}