import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'endpoint_country_service.dart';

class ImportedConfigsPrefs {
  static const String _pathsKey = 'imported_config_paths';
  static const String _pinnedPathsKey = 'pinned_config_paths';
  static const String _selectedPathKey = 'selected_config_path';
  static const String _countryInfoCacheKey = 'endpoint_country_info_cache';
  static final Future<SharedPreferences> _prefs =
      SharedPreferences.getInstance();
  static Future<void> _writeQueue = Future<void>.value();

  static Future<SharedPreferences> _instance() => _prefs;

  static Future<
    ({List<String> paths, List<String> pinnedPaths, String? selectedPath})
  >
  loadState() async {
    final prefs = await _instance();
    return (
      paths: prefs.getStringList(_pathsKey) ?? <String>[],
      pinnedPaths: prefs.getStringList(_pinnedPathsKey) ?? <String>[],
      selectedPath: prefs.getString(_selectedPathKey),
    );
  }

  static Future<List<String>> loadPaths() async {
    final prefs = await _instance();
    return prefs.getStringList(_pathsKey) ?? <String>[];
  }

  static Future<void> savePaths(List<String> paths) {
    return _enqueueWrite(() async {
      final prefs = await _instance();
      await prefs.setStringList(_pathsKey, paths);
    });
  }

  static Future<List<String>> loadPinnedPaths() async {
    final prefs = await _instance();
    return prefs.getStringList(_pinnedPathsKey) ?? <String>[];
  }

  static Future<void> savePinnedPaths(List<String> paths) {
    return _enqueueWrite(() async {
      final prefs = await _instance();
      await prefs.setStringList(_pinnedPathsKey, paths);
    });
  }

  static Future<String?> loadSelectedPath() async {
    final prefs = await _instance();
    return prefs.getString(_selectedPathKey);
  }

  static Future<void> saveSelectedPath(String? path) {
    return _enqueueWrite(() async {
      final prefs = await _instance();
      if (path == null || path.isEmpty) {
        await prefs.remove(_selectedPathKey);
        return;
      }

      await prefs.setString(_selectedPathKey, path);
    });
  }

  static Future<void> saveState({
    required List<String> paths,
    required List<String> pinnedPaths,
    String? selectedPath,
  }) {
    return _enqueueWrite(() async {
      final prefs = await _instance();
      await prefs.setStringList(_pathsKey, paths);
      await prefs.setStringList(_pinnedPathsKey, pinnedPaths);
      if (selectedPath == null || selectedPath.isEmpty) {
        await prefs.remove(_selectedPathKey);
      } else {
        await prefs.setString(_selectedPathKey, selectedPath);
      }
    });
  }

  static Future<Map<String, EndpointCountryInfo>> loadCountryInfoCache() async {
    final prefs = await _instance();
    final rawCache = prefs.getString(_countryInfoCacheKey);
    if (rawCache == null || rawCache.isEmpty) {
      return <String, EndpointCountryInfo>{};
    }

    try {
      final decodedCache = jsonDecode(rawCache);
      if (decodedCache is! Map) {
        return <String, EndpointCountryInfo>{};
      }

      final countryInfoByLookupKey = <String, EndpointCountryInfo>{};
      for (final entry in decodedCache.entries) {
        if (entry.key is! String || entry.value is! Map) {
          continue;
        }

        final value = entry.value as Map;
        final countryCode = value['countryCode'];
        final countryName = value['countryName'];
        if (countryCode is! String || countryName is! String) {
          continue;
        }
        if (countryCode.trim().isEmpty || countryName.trim().isEmpty) {
          continue;
        }

        countryInfoByLookupKey[entry.key as String] = EndpointCountryInfo(
          countryCode: countryCode,
          countryName: countryName,
        );
      }

      return countryInfoByLookupKey;
    } catch (_) {
      return <String, EndpointCountryInfo>{};
    }
  }

  static Future<void> saveCountryInfoCache(
    Map<String, EndpointCountryInfo> countryInfoByLookupKey,
  ) {
    final serializedCache = <String, dynamic>{
      for (final entry in countryInfoByLookupKey.entries)
        entry.key: <String, String>{
          'countryCode': entry.value.countryCode,
          'countryName': entry.value.countryName,
        },
    };
    return _enqueueWrite(() async {
      final prefs = await _instance();
      await prefs.setString(_countryInfoCacheKey, jsonEncode(serializedCache));
    });
  }

  static Future<void> _enqueueWrite(Future<void> Function() action) {
    _writeQueue = _writeQueue.catchError((_) {}).then((_) => action());
    return _writeQueue;
  }
}
