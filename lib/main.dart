import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'imported_configs_prefs.dart';
import 'l10n/app_localizations.dart';
import 'l10n/language_service.dart';
import 'split_tunnel_prefs.dart';
import 'split_tunnel_settings_page.dart';
import 'theme_service.dart';
import 'wg_config_parser.dart';

enum SplitTunnelMode {
  all('all', 'Вся система через VPN', 'Через VPN будет идти трафик всей системы.'),
  include('include', 'Только выбранные приложения', 'Через VPN будут идти только отмеченные приложения.'),
  exclude('exclude', 'Все приложения кроме выбранных', 'Через VPN будет идти трафик всей системы, кроме отмеченных приложений.');

  const SplitTunnelMode(this.wireValue, this.label, this.description);

  final String wireValue;
  final String label;
  final String description;
}

enum SplitTunnelDomainMode {
  all('all', 'Все сайты через VPN', 'Весь трафик идет через VPN без доменных ограничений.'),
  include('include', 'Только указанные сайты', 'Через VPN идут только перечисленные домены (остальной трафик — напрямую).'),
  exclude('exclude', 'Все сайты кроме указанных', 'Через VPN идет весь трафик, кроме перечисленных доменов.');

  const SplitTunnelDomainMode(this.wireValue, this.label, this.description);

  final String wireValue;
  final String label;
  final String description;
}

class InstalledApp {
  const InstalledApp({required this.label, required this.packageName});

  final String label;
  final String packageName;

  factory InstalledApp.fromMap(Map<dynamic, dynamic> map) {
    return InstalledApp(
      label: (map['label'] as String?) ?? (map['packageName'] as String? ?? ''),
      packageName: (map['packageName'] as String?) ?? '',
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final languageService = LanguageService();
  final themeService = ThemeService();
  await themeService.initialize();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: languageService),
        ChangeNotifierProvider.value(value: themeService),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  ThemeData _lightTheme() {
    const colors = ColorScheme.light(
      primary: Colors.black,
      onPrimary: Colors.white,
      secondary: Colors.black,
      onSecondary: Colors.white,
      surface: Colors.white,
      onSurface: Colors.black,
      error: Colors.black,
      onError: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colors,
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }

  ThemeData _darkTheme() {
    const colors = ColorScheme.dark(
      primary: Colors.white,
      onPrimary: Colors.black,
      secondary: Colors.white,
      onSecondary: Colors.black,
      surface: Colors.black,
      onSurface: Colors.white,
      error: Colors.white,
      onError: Colors.black,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colors,
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<LanguageService, ThemeService>(
      builder: (context, languageService, themeService, child) {
        return MaterialApp(
          title: 'wgfytunnel',
          theme: _lightTheme(),
          darkTheme: _darkTheme(),
          themeMode: themeService.themeMode,
          locale: languageService.locale,
          supportedLocales: const [
            Locale('en'),
            Locale('ru'),
          ],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const MyHomePage(),
        );
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  static const MethodChannel _wireGuardChannel = MethodChannel('wgfytunnel/wireguard');

  List<File> _importedConfigs = const [];
  Set<String> _pinnedConfigPaths = <String>{};
  Map<String, String> _configEndpointsByPath = const <String, String>{};
  File? _selectedConf;
  Map<String, dynamic>? _parsedConf;
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _isLoadingImportedConfigs = true;
  String? _inlineMessageText;
  Timer? _inlineMessageTimer;
  int _rxBytes = 0;
  int _txBytes = 0;
  Timer? _statsTimer;
  DateTime? _connectionStartTime;
  Timer? _uptimeTimer;
  int _tunnelStatusRevision = 0;
  SplitTunnelMode _splitTunnelMode = SplitTunnelMode.all;
  SplitTunnelDomainMode _splitTunnelDomainMode = SplitTunnelDomainMode.all;
  int _selectedAppsCount = 0;
  int _selectedDomainsCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreImportedConfigs();
    _refreshSplitTunnelSelections();
    _refreshTunnelStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clearInlineMessage();
    _statsTimer?.cancel();
    _uptimeTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshSplitTunnelSelections();
      _refreshTunnelStatus();
    }
  }

  Future<void> _refreshSplitTunnelSelections() async {
    final selections = await SplitTunnelPrefs.loadSelections();
    if (!mounted) {
      return;
    }

    setState(() {
      _splitTunnelMode = selections.mode;
      _selectedAppsCount = selections.packages.length;
      _splitTunnelDomainMode = selections.domainMode;
      _selectedDomainsCount = selections.domains.length;
    });
  }

  String? _selectionWarningText(AppLocalizations l10n) {
    final appsMissing =
        _splitTunnelMode != SplitTunnelMode.all && _selectedAppsCount == 0;
    final domainsMissing =
        _splitTunnelDomainMode != SplitTunnelDomainMode.all &&
        _selectedDomainsCount == 0;

    if (appsMissing && domainsMissing) {
      return l10n.selectAppsAndSites;
    }
    if (domainsMissing) {
      return l10n.selectSites;
    }
    if (appsMissing) {
      return l10n.selectApps;
    }
    return null;
  }

  String _translatedRuntimeMessage(String text) {
    return AppLocalizations.of(context).translateRuntimeMessage(text);
  }

  String _configName(File file) {
    return file.path.split(Platform.pathSeparator).last;
  }

  bool _samePaths(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }

    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }

    return true;
  }

  Future<String?> _readConfigContent(File file) async {
    try {
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _parseConfigContent(String content) {
    try {
      return parseWireguardConfig(content);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _readParsedConfig(File file) async {
    final content = await _readConfigContent(file);
    if (content == null) {
      return null;
    }

    return _parseConfigContent(content);
  }

  String _configFingerprintFromContent(String content) {
    final sectionFingerprints = <String>[];
    var currentSection = 'global';
    var currentLines = <String>[];

    void flushSection() {
      if (currentSection == 'global' && currentLines.isEmpty) {
        return;
      }

      final sortedLines = List<String>.from(currentLines)..sort();
      sectionFingerprints.add('$currentSection:${sortedLines.join('|')}');
      currentLines = <String>[];
    }

    for (final rawLine in content.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
        continue;
      }

      if (line.startsWith('[') && line.endsWith(']')) {
        flushSection();
        currentSection = line.substring(1, line.length - 1).trim().toLowerCase();
        continue;
      }

      final separatorIndex = line.indexOf('=');
      if (separatorIndex == -1) {
        currentLines.add(line);
        continue;
      }

      final key = line.substring(0, separatorIndex).trim();
      final value = line.substring(separatorIndex + 1).trim();
      currentLines.add('$key=$value');
    }

    flushSection();
    sectionFingerprints.sort();
    return sectionFingerprints.join('||');
  }

  Future<String?> _readConfigFingerprint(File file) async {
    final content = await _readConfigContent(file);
    if (content == null) {
      return null;
    }

    return _configFingerprintFromContent(content);
  }

  Future<File?> _findImportedConfigMatch(
    File file,
    String configFingerprint,
  ) async {
    for (final importedFile in _importedConfigs) {
      if (importedFile.path == file.path) {
        return importedFile;
      }
    }

    for (final importedFile in _importedConfigs) {
      final importedFingerprint = await _readConfigFingerprint(importedFile);
      if (importedFingerprint == null) {
        continue;
      }

      if (importedFingerprint == configFingerprint) {
        return importedFile;
      }
    }

    return null;
  }

  Map<String, String> _stringMap(Object? rawValue) {
    if (rawValue is! Map) {
      return const <String, String>{};
    }

    final result = <String, String>{};
    rawValue.forEach((key, value) {
      final normalizedKey = key.toString().trim();
      final normalizedValue = value?.toString().trim() ?? '';
      if (normalizedKey.isEmpty || normalizedValue.isEmpty) {
        return;
      }

      result[normalizedKey] = normalizedValue;
    });
    return result;
  }

  List<Map<String, String>> _stringSections(Object? rawValue) {
    if (rawValue is! List) {
      return const <Map<String, String>>[];
    }

    return rawValue
        .whereType<Map>()
        .map(_stringMap)
        .where((section) => section.isNotEmpty)
        .toList(growable: false);
  }

  String? _firstNonEmptyValue(Map<String, String> values, List<String> keys) {
    for (final key in keys) {
      final value = values[key];
      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    return null;
  }

  String _configEndpointText(Map<String, dynamic>? parsedConfig) {
    if (parsedConfig == null) {
      return '-';
    }

    final peers = _stringSections(parsedConfig['peers']);
    if (peers.isEmpty) {
      return '-';
    }

    return _firstNonEmptyValue(peers.first, const ['Endpoint']) ?? '-';
  }

  Future<Map<String, String>> _buildConfigEndpointsMap(
    List<File> configs, {
    File? selectedConfig,
    Map<String, dynamic>? selectedParsedConfig,
  }) async {
    final entries = await Future.wait(
      configs.map((file) async {
        final parsedConfig = selectedConfig != null && selectedConfig.path == file.path
            ? selectedParsedConfig
            : await _readParsedConfig(file);
        return MapEntry(file.path, _configEndpointText(parsedConfig));
      }),
    );

    return Map<String, String>.fromEntries(entries);
  }

  List<File> _sortImportedConfigs(List<File> configs, Set<String> pinnedPaths) {
    final pinnedConfigs = <File>[];
    final regularConfigs = <File>[];

    for (final file in configs) {
      if (pinnedPaths.contains(file.path)) {
        pinnedConfigs.add(file);
      } else {
        regularConfigs.add(file);
      }
    }

    return <File>[...pinnedConfigs, ...regularConfigs];
  }

  Future<void> _persistImportedConfigs(
    List<File> importedConfigs, {
    File? selectedConfig,
    Set<String>? pinnedPaths,
  }) async {
    await ImportedConfigsPrefs.savePaths(
      importedConfigs.map((file) => file.path).toList(growable: false),
    );
    await ImportedConfigsPrefs.savePinnedPaths(
      (pinnedPaths ?? _pinnedConfigPaths).toList(growable: false),
    );
    await ImportedConfigsPrefs.saveSelectedPath(selectedConfig?.path);
  }

  Future<void> _restoreImportedConfigs() async {
    final savedState = await ImportedConfigsPrefs.loadState();
    final savedPaths = savedState.paths;
    final savedPinnedPaths = savedState.pinnedPaths.toSet();
    final savedSelectedPath = savedState.selectedPath;
    final restoredConfigs = (await Future.wait(
      savedPaths.map((path) async {
        final file = File(path);
        return await file.exists() ? file : null;
      }),
    )).whereType<File>().toList(growable: false);

    final restoredPinnedPaths = savedPinnedPaths
        .where((path) => restoredConfigs.any((file) => file.path == path))
        .toSet();
    final orderedConfigs = _sortImportedConfigs(restoredConfigs, restoredPinnedPaths);

    File? selectedConfig;
    if (savedSelectedPath != null) {
      for (final file in orderedConfigs) {
        if (file.path == savedSelectedPath) {
          selectedConfig = file;
          break;
        }
      }
    }
    selectedConfig ??= orderedConfigs.isNotEmpty ? orderedConfigs.first : null;

    final parsedConfig = selectedConfig == null
        ? null
        : await _readParsedConfig(selectedConfig);
    final endpointsByPath = await _buildConfigEndpointsMap(
      orderedConfigs,
      selectedConfig: selectedConfig,
      selectedParsedConfig: parsedConfig,
    );
    final restoredPaths = orderedConfigs
        .map((file) => file.path)
        .toList(growable: false);

    if (!_samePaths(savedPaths, restoredPaths)) {
      await ImportedConfigsPrefs.savePaths(restoredPaths);
    }
    await ImportedConfigsPrefs.savePinnedPaths(
      restoredPinnedPaths.toList(growable: false),
    );
    await ImportedConfigsPrefs.saveSelectedPath(selectedConfig?.path);

    if (!mounted) {
      return;
    }

    setState(() {
      _importedConfigs = orderedConfigs;
      _pinnedConfigPaths = restoredPinnedPaths;
      _configEndpointsByPath = endpointsByPath;
      _selectedConf = selectedConfig;
      _parsedConf = parsedConfig;
      _isLoadingImportedConfigs = false;
    });
  }

  Future<void> _selectImportedConfig(File file) async {
    final l10n = AppLocalizations.of(context);
    if (!await file.exists()) {
      _removeImportedConfig(file);
      _showMessage(l10n.failedReadFile);
      return;
    }

    final parsedConfig = await _readParsedConfig(file);
    if (parsedConfig == null) {
      _showMessage(l10n.failedReadFile);
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _configEndpointsByPath = <String, String>{
        ..._configEndpointsByPath,
        file.path: _configEndpointText(parsedConfig),
      };
      _selectedConf = file;
      _parsedConf = parsedConfig;
    });
    await ImportedConfigsPrefs.saveSelectedPath(file.path);
  }

  void _removeImportedConfig(File file) {
    final updatedPinnedPaths = Set<String>.from(_pinnedConfigPaths)
      ..remove(file.path);
    final updatedConfigs = _importedConfigs
        .where((config) => config.path != file.path)
        .toList(growable: false);
    final updatedEndpointsByPath = Map<String, String>.from(_configEndpointsByPath)
      ..remove(file.path);
    final removedSelectedConfig = _selectedConf?.path == file.path;
    final nextSelectedConfig = removedSelectedConfig
        ? (updatedConfigs.isNotEmpty ? updatedConfigs.first : null)
        : _selectedConf;
    final nextParsedConfig = removedSelectedConfig ? null : _parsedConf;

    setState(() {
      _importedConfigs = updatedConfigs;
      _pinnedConfigPaths = updatedPinnedPaths;
      _configEndpointsByPath = updatedEndpointsByPath;
      _selectedConf = nextSelectedConfig;
      _parsedConf = nextParsedConfig;
    });

    _syncRemovedConfig(
      updatedConfigs,
      nextSelectedConfig,
      removedSelectedConfig,
      updatedPinnedPaths,
    );
  }

  Future<void> _syncRemovedConfig(
    List<File> updatedConfigs,
    File? nextSelectedConfig,
    bool shouldReloadSelectedConfig,
    Set<String> pinnedPaths,
  ) async {
    final selectedPath = nextSelectedConfig?.path;
    final parsedConfig = shouldReloadSelectedConfig && nextSelectedConfig != null
        ? await _readParsedConfig(nextSelectedConfig)
        : _parsedConf;

    await _persistImportedConfigs(
      updatedConfigs,
      selectedConfig: nextSelectedConfig,
      pinnedPaths: pinnedPaths,
    );

    if (!mounted || !shouldReloadSelectedConfig || _selectedConf?.path != selectedPath) {
      return;
    }

    setState(() {
      _parsedConf = parsedConfig;
    });
  }

  Future<void> _refreshTunnelStatus() async {
    final refreshRevision = _tunnelStatusRevision;
    try {
      final status = await _wireGuardChannel.invokeMethod<Map<dynamic, dynamic>>('getWireGuardStatus');
      if (!mounted || refreshRevision != _tunnelStatusRevision) return;
      final connected = status?['connected'] == true;
      setState(() {
        _isConnected = connected;
      });
      if (connected) {
        _startStatsPolling();
      } else {
        _stopStatsPolling();
      }
    } catch (_) {
      if (!mounted || refreshRevision != _tunnelStatusRevision) return;
      setState(() {
        _isConnected = false;
      });
      _stopStatsPolling();
    }
  }

  void _startStatsPolling() {
    _statsTimer?.cancel();
    _uptimeTimer?.cancel();
    _connectionStartTime = DateTime.now();
    _fetchStats();
    _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
        _fetchStats();
      }
    });
  }

  void _stopStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = null;
    _uptimeTimer?.cancel();
    _uptimeTimer = null;
    _connectionStartTime = null;
    if (mounted) {
      setState(() {
        _rxBytes = 0;
        _txBytes = 0;
      });
    }
  }

  Future<void> _fetchStats() async {
    try {
      final stats = await _wireGuardChannel.invokeMethod<Map<dynamic, dynamic>>('getWireGuardStats');
      if (!mounted || !_isConnected) return;
      setState(() {
        _rxBytes = (stats?['rxBytes'] as num?)?.toInt() ?? 0;
        _txBytes = (stats?['txBytes'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {}
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(2)} KB';
  }

  String _formatUptime() {
    if (_connectionStartTime == null) return '00:00:00';
    final d = DateTime.now().difference(_connectionStartTime!);
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<void> _importConf() async {
    final l10n = AppLocalizations.of(context);

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: false,
      );

      if (picked == null || picked.files.isEmpty) {
        _showMessage(l10n.fileSelectionCancelled);
        return;
      }

      final path = picked.files.single.path;
      if (path == null) {
        _showMessage(l10n.failedGetFilePath);
        return;
      }

      final file = File(path);
      if (!await file.exists()) {
        _showMessage(l10n.failedReadFile);
        return;
      }

      final fileNameLower = file.path.toLowerCase();
      if (!fileNameLower.endsWith('.conf')) {
        _showMessage(l10n.invalidConfig);
        return;
      }

      final content = await _readConfigContent(file);
      if (content == null) {
        _showMessage(l10n.failedReadFile);
        return;
      }

      final parsed = _parseConfigContent(content);
      if (parsed == null) {
        _showMessage(l10n.failedParseConfig);
        return;
      }

      final existingConfig = await _findImportedConfigMatch(
        file,
        _configFingerprintFromContent(content),
      );
      if (existingConfig != null) {
        await _selectImportedConfig(existingConfig);
        if (!mounted || _selectedConf?.path != existingConfig.path) {
          return;
        }

        _showMessage(
          '${l10n.configAlreadyImported}: ${_configName(existingConfig)}',
        );
        return;
      }

      final updatedConfigs = <File>[
        file,
        ..._importedConfigs.where((config) => config.path != file.path),
      ];
      final updatedEndpointsByPath = <String, String>{
        file.path: _configEndpointText(parsed),
        ..._configEndpointsByPath,
      };

      setState(() {
        _importedConfigs = updatedConfigs;
        _configEndpointsByPath = updatedEndpointsByPath;
        _selectedConf = file;
        _parsedConf = parsed;
        _isLoadingImportedConfigs = false;
      });
      await _persistImportedConfigs(updatedConfigs, selectedConfig: file);
    } catch (e) {
      _showMessage('Error importing file: $e');
    }
  }

  Future<void> _connectWireGuard() async {
    final l10n = AppLocalizations.of(context);
    if (_selectedConf == null || _parsedConf == null) {
      _showMessage(l10n.configNotSelected);
      return;
    }

    final isValid = _parsedConf?['isValid'] == true;
    if (!isValid) {
      _showMessage(l10n.invalidConfig);
      return;
    }

    _tunnelStatusRevision += 1;
    setState(() {
      _isConnecting = true;
    });

    final selections = await SplitTunnelPrefs.loadSelections();
    final splitMode = selections.mode;
    final selectedPackages = selections.packages;
    final domainMode = selections.domainMode;
    final domainList = selections.domains;

    if (splitMode != SplitTunnelMode.all && selectedPackages.isEmpty) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
      _showMessage(l10n.selectApps);
      return;
    }

    if (domainMode != SplitTunnelDomainMode.all && domainList.isEmpty) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
      _showMessage(l10n.selectSites);
      return;
    }

    try {
      // Use sing-box backend when domain routing is needed (include/exclude domains)
      final useDomainRouting = domainMode != SplitTunnelDomainMode.all;

      final status = await _wireGuardChannel.invokeMethod<Map<dynamic, dynamic>>(
        'connectWireGuard',
        {
          'filePath': _selectedConf!.path,
          'splitMode': splitMode.wireValue,
          'selectedPackages': selectedPackages.toList()..sort(),
          'domainMode': domainMode.wireValue,
          'domainList': domainList,
          'useDomainRouting': useDomainRouting,
        },
      );

      if (!mounted) return;

      final connected = status?['connected'] == true;
      setState(() {
        _isConnected = connected;
      });
      if (connected) {
        _startStatsPolling();
      }

      final message = status?['message'] as String?;
      if (message != null) {
        _showMessage(_translatedRuntimeMessage(message));
      }
    } on PlatformException catch (e) {
      _showMessage(
        '${l10n.failedStartTunnel}: ${_translatedRuntimeMessage(e.message ?? e.code)}',
      );
    } catch (e) {
      _showMessage('${l10n.failedStartTunnel}: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  Future<void> _disconnectWireGuard() async {
    final l10n = AppLocalizations.of(context);
    _tunnelStatusRevision += 1;
    setState(() {
      _inlineMessageTimer?.cancel();
      _inlineMessageTimer = null;
      _inlineMessageText = null;
      _isConnecting = true;
    });

    try {
      final status = await _wireGuardChannel.invokeMethod<Map<dynamic, dynamic>>('disconnectWireGuard');
      if (!mounted) return;

      final connected = status?['connected'] == true;
      setState(() {
        _isConnected = connected;
      });
      if (!connected) {
        _stopStatsPolling();
      }
    } on PlatformException catch (e) {
      _showMessage(
        '${l10n.failedStopTunnel}: ${_translatedRuntimeMessage(e.message ?? e.code)}',
      );
    } catch (e) {
      _showMessage('${l10n.failedStopTunnel}: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  void _showMessage(String text) {
    if (!mounted) {
      return;
    }

    _inlineMessageTimer?.cancel();
    setState(() {
      _inlineMessageText = text;
    });
    _inlineMessageTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) {
        return;
      }

      _clearInlineMessage();
    });
  }

  void _clearInlineMessage() {
    _inlineMessageTimer?.cancel();
    _inlineMessageTimer = null;
    if (!mounted) {
      _inlineMessageText = null;
      return;
    }

    setState(() {
      _inlineMessageText = null;
    });
  }

  Widget _buildConfigInfoRow(BuildContext context, String label, String value) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(value),
        ],
      ),
    );
  }

  Widget _buildConfigSectionTitle(BuildContext context, String title) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Text(
        title,
        style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildVpnfyImage({
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      isDark ? 'vpnfy_black.png' : 'vpnfy_white.png',
      width: width,
      height: height,
      fit: fit,
    );
  }

  Future<void> _showConfigInfoDialog(File file) async {
    final l10n = AppLocalizations.of(context);
    if (!await file.exists()) {
      _showMessage(l10n.failedReadFile);
      return;
    }

    final parsedConfig = _selectedConf?.path == file.path && _parsedConf != null
        ? _parsedConf
        : await _readParsedConfig(file);
    if (parsedConfig == null || !mounted) {
      _showMessage(l10n.failedReadFile);
      return;
    }

    final interfaces = _stringSections(parsedConfig['interfaces']);
    final peers = _stringSections(parsedConfig['peers']);
    final primaryInterface = interfaces.isNotEmpty
        ? interfaces.first
        : const <String, String>{};

    final address = _firstNonEmptyValue(primaryInterface, const ['Address']);
    final dns = _firstNonEmptyValue(primaryInterface, const ['DNS']);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final materialL10n = MaterialLocalizations.of(dialogContext);
        final details = <Widget>[
          _buildConfigInfoRow(dialogContext, l10n.configNameLabel, _configName(file)),
          _buildConfigInfoRow(dialogContext, l10n.configPathLabel, file.path),
          _buildConfigInfoRow(
            dialogContext,
            l10n.configStatusLabel,
            parsedConfig['isValid'] == true
                ? l10n.configValidStatus
                : l10n.configInvalidStatus,
          ),
          _buildConfigInfoRow(
            dialogContext,
            l10n.configInterfacesCount,
            interfaces.length.toString(),
          ),
          _buildConfigInfoRow(
            dialogContext,
            l10n.configPeersCount,
            peers.length.toString(),
          ),
        ];

        if (primaryInterface.isNotEmpty) {
          details.add(
            _buildConfigSectionTitle(dialogContext, l10n.configInterfaceSection),
          );
          if (address != null) {
            details.add(_buildConfigInfoRow(dialogContext, 'Address', address));
          }
          if (dns != null) {
            details.add(_buildConfigInfoRow(dialogContext, 'DNS', dns));
          }
        }

        for (var index = 0; index < peers.length; index += 1) {
          final peer = peers[index];
          details.add(
            _buildConfigSectionTitle(
              dialogContext,
              '${l10n.configPeerSection} ${index + 1}',
            ),
          );

          final endpoint = _firstNonEmptyValue(peer, const ['Endpoint']);
          if (endpoint != null) {
            details.add(_buildConfigInfoRow(dialogContext, 'Endpoint', endpoint));
          }

          final allowedIps = _firstNonEmptyValue(peer, const ['AllowedIPs']);
          if (allowedIps != null) {
            details.add(
              _buildConfigInfoRow(dialogContext, 'AllowedIPs', allowedIps),
            );
          }

          final publicKey = _firstNonEmptyValue(peer, const ['PublicKey']);
          if (publicKey != null) {
            details.add(_buildConfigInfoRow(dialogContext, 'PublicKey', publicKey));
          }
        }

        return AlertDialog(
          title: Text(l10n.configInfoTitle),
          content: SizedBox(
            width: double.maxFinite,
            child: SelectionArea(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: details,
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(materialL10n.okButtonLabel),
            ),
          ],
        );
      },
    );
  }

  Future<void> _togglePinnedConfig(File file) async {
    final updatedPinnedPaths = Set<String>.from(_pinnedConfigPaths);
    if (updatedPinnedPaths.contains(file.path)) {
      updatedPinnedPaths.remove(file.path);
    } else {
      updatedPinnedPaths.add(file.path);
    }

    final updatedConfigs = _sortImportedConfigs(_importedConfigs, updatedPinnedPaths);

    setState(() {
      _pinnedConfigPaths = updatedPinnedPaths;
      _importedConfigs = updatedConfigs;
    });

    await _persistImportedConfigs(
      updatedConfigs,
      selectedConfig: _selectedConf,
      pinnedPaths: updatedPinnedPaths,
    );
  }

  Widget _buildImportedConfigsList() {
    final materialL10n = MaterialLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final itemBorderColor = isDark ? Colors.white : Colors.black;

    if (_isLoadingImportedConfigs) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_importedConfigs.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListView.separated(
      itemCount: _importedConfigs.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final file = _importedConfigs[index];
        final isSelected = _selectedConf?.path == file.path;
        final isPinned = _pinnedConfigPaths.contains(file.path);
        final endpointText = _configEndpointsByPath[file.path] ?? '-';

        return Dismissible(
          key: ValueKey(file.path),
          direction: DismissDirection.horizontal,
          background: Container(
            decoration: BoxDecoration(
              color: const Color.fromRGBO(255, 179, 0, 1),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: Colors.black,
                ),
                const SizedBox(width: 8),
                Text(
                  isPinned ? 'Открепить' : 'Закрепить',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          secondaryBackground: Container(
            decoration: BoxDecoration(
              color: const Color.fromRGBO(198, 40, 40, 1),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.delete, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  materialL10n.deleteButtonTooltip,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.startToEnd) {
              await _togglePinnedConfig(file);
              return false;
            }
            return true;
          },
          onDismissed: (_) => _removeImportedConfig(file),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.primary.withValues(alpha: 0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: itemBorderColor),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _selectImportedConfig(file),
                onLongPress: () => _showConfigInfoDialog(file),
                child: ListTile(
                  minTileHeight: 48,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  leading: Icon(
                    Icons.insert_drive_file_outlined,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  title: Text(
                    _configName(file),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium,
                  ),
                  subtitle: Text(
                    endpointText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isPinned) ...[
                        Icon(
                          Icons.push_pin,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Icon(
                        isSelected ? Icons.check_circle : Icons.chevron_right,
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasValidConf = _parsedConf?['isValid'] == true;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const disconnectButtonColor = Color.fromRGBO(180, 80, 80, 1);
    final showActiveTunnelUi = _isConnected || _isConnecting;
    final connectButtonBackgroundColor = showActiveTunnelUi
      ? disconnectButtonColor
      : (isDark ? Colors.white : Colors.black);
    final connectButtonForegroundColor = showActiveTunnelUi
      ? Colors.white
      : (isDark ? Colors.black : Colors.white);
    const actionButtonHeight = 56.0;
    const connectionAnimDuration = Duration(milliseconds: 500);
    const connectionAnimCurve = Curves.fastOutSlowIn;
    final isTunnelActive = _isConnected || _isConnecting;
    final compactConfigsList = isTunnelActive;
    final selectionWarningText = _selectionWarningText(l10n);
    final connectBlockedBySelection = selectionWarningText != null;
    final canConnect = _selectedConf != null && hasValidConf && !connectBlockedBySelection;
    final connectButtonOpacity = !_isConnected && !_isConnecting && connectBlockedBySelection
      ? 0.5
      : 1.0;
    final actionInfoText = _inlineMessageText ?? selectionWarningText;
    final isSelectionWarningText = actionInfoText == l10n.selectApps ||
      actionInfoText == l10n.selectSites ||
      actionInfoText == l10n.selectAppsAndSites;
    final actionInfoColor = isSelectionWarningText
      ? disconnectButtonColor
        : null;
    const actionButtonTextStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
    );
    final actionButtonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: _buildVpnfyImage(),
            ),
            const SizedBox(width: 10),
            Text(
              l10n.appTitle,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: l10n.splitTunneling,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SplitTunnelSettingsPage(),
                ),
              ).then((_) {
                _refreshSplitTunnelSelections();
                _refreshTunnelStatus();
              });
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          AnimatedSlide(
            duration: connectionAnimDuration,
            curve: connectionAnimCurve,
            offset: isTunnelActive ? const Offset(0, -0.34) : Offset.zero,
            child: AnimatedOpacity(
              duration: connectionAnimDuration,
              curve: connectionAnimCurve,
              opacity: isTunnelActive ? 1.0 : 0.30,
              child: Center(child: _buildVpnfyImage(width: 240)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final actionButtonsBlockHeight = (actionButtonHeight * 2) + 32.0;
                      final normalListHeight = constraints.maxHeight > actionButtonsBlockHeight
                          ? constraints.maxHeight - actionButtonsBlockHeight
                          : 0.0;
                      final targetListHeight =
                          normalListHeight * (compactConfigsList ? 0.60 : 1.0);
                      final targetTopOffset = normalListHeight - targetListHeight;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AnimatedContainer(
                            duration: connectionAnimDuration,
                            curve: connectionAnimCurve,
                            height: targetTopOffset,
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                height: actionButtonHeight,
                                child: _isConnected
                                    ? AnimatedSwitcher(
                                        duration: connectionAnimDuration,
                                        switchInCurve: connectionAnimCurve,
                                        switchOutCurve: connectionAnimCurve,
                                        transitionBuilder: (child, animation) =>
                                            FadeTransition(opacity: animation, child: child),
                                        child: Center(
                                          key: const ValueKey('stats-display'),
                                          child: Transform.translate(
                                            offset: const Offset(0, 6),
                                            child: Text(
                                              '${_formatUptime()} / ${_formatBytes(_rxBytes + _txBytes)}',
                                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                    : actionInfoText == null
                                    ? OutlinedButton(
                                        onPressed: _importConf,
                                        style: OutlinedButton.styleFrom(
                                          minimumSize: const Size.fromHeight(actionButtonHeight),
                                          padding: EdgeInsets.zero,
                                          textStyle: actionButtonTextStyle,
                                          shape: actionButtonShape,
                                        ),
                                        child: Text(l10n.importConfig),
                                      )
                                    : Center(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                          child: Text(
                                            actionInfoText,
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                              color: actionInfoColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: actionButtonHeight,
                                child: AnimatedOpacity(
                                  duration: connectionAnimDuration,
                                  curve: connectionAnimCurve,
                                  opacity: connectButtonOpacity,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(actionButtonHeight),
                                      padding: EdgeInsets.zero,
                                      backgroundColor: connectButtonBackgroundColor,
                                      foregroundColor: connectButtonForegroundColor,
                                      disabledBackgroundColor: connectBlockedBySelection
                                          ? connectButtonBackgroundColor
                                          : connectButtonBackgroundColor.withValues(alpha: 0.24),
                                      disabledForegroundColor: connectBlockedBySelection
                                          ? connectButtonForegroundColor
                                          : connectButtonForegroundColor.withValues(alpha: 0.45),
                                      elevation: 0,
                                      shape: actionButtonShape,
                                      textStyle: actionButtonTextStyle,
                                    ),
                                    onPressed: _isConnecting
                                        ? null
                                        : (_isConnected
                                            ? _disconnectWireGuard
                                            : (canConnect ? _connectWireGuard : null)),
                                    child: _isConnecting
                                        ? Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2.4,
                                                  valueColor: AlwaysStoppedAnimation<Color>(
                                                    connectButtonForegroundColor,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Text(
                                                _isConnected ? l10n.disconnect : l10n.connect,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          )
                                        : Text(
                                            _isConnected ? l10n.disconnect : l10n.connect,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                          ),
                          AnimatedContainer(
                            duration: connectionAnimDuration,
                            curve: connectionAnimCurve,
                            height: targetListHeight,
                            child: _buildImportedConfigsList(),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
