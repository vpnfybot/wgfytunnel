import 'package:shared_preferences/shared_preferences.dart';

class ImportedConfigsPrefs {
  static const String _pathsKey = 'imported_config_paths';
  static const String _pinnedPathsKey = 'pinned_config_paths';
  static const String _selectedPathKey = 'selected_config_path';
  static final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  static Future<SharedPreferences> _instance() => _prefs;

  static Future<({
    List<String> paths,
    List<String> pinnedPaths,
    String? selectedPath,
  })> loadState() async {
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

  static Future<void> savePaths(List<String> paths) async {
    final prefs = await _instance();
    await prefs.setStringList(_pathsKey, paths);
  }

  static Future<List<String>> loadPinnedPaths() async {
    final prefs = await _instance();
    return prefs.getStringList(_pinnedPathsKey) ?? <String>[];
  }

  static Future<void> savePinnedPaths(List<String> paths) async {
    final prefs = await _instance();
    await prefs.setStringList(_pinnedPathsKey, paths);
  }

  static Future<String?> loadSelectedPath() async {
    final prefs = await _instance();
    return prefs.getString(_selectedPathKey);
  }

  static Future<void> saveSelectedPath(String? path) async {
    final prefs = await _instance();
    if (path == null || path.isEmpty) {
      await prefs.remove(_selectedPathKey);
      return;
    }

    await prefs.setString(_selectedPathKey, path);
  }
}