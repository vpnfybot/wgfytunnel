import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_update_service.dart';
import 'endpoint_country_service.dart';
import 'imported_configs_prefs.dart';
import 'l10n/app_localizations.dart';
import 'l10n/language_service.dart';
import 'qr_config_scanner_page.dart';
import 'split_tunnel_prefs.dart';
import 'split_tunnel_settings_page.dart';
import 'subscription_service.dart';
import 'theme_service.dart';
import 'wg_config_parser.dart';

const double _elementBorderRadius = 12.0;

enum SplitTunnelMode {
  all('all', 'Вся система через VPN', 'Через VPN будет идти трафик всей системы.'),
  include('include', 'Только выбранные приложения', 'Через VPN будут идти только отмеченные приложения.'),
  exclude('exclude', 'Все приложения кроме выбранных', 'Через VPN будет идти трафик всей системы, кроме отмеченных приложений.');

  const SplitTunnelMode(this.wireValue, this.label, this.description);

  final String wireValue;
  final String label;
  final String description;
}

class _ConfigEditorPage extends StatefulWidget {
  const _ConfigEditorPage({
    required this.file,
    required this.initialName,
    required this.globalValues,
    required this.interfaces,
    required this.peers,
    required this.editableInterfaceKeys,
    required this.editablePeerKeys,
    required this.configFieldControllerKeyBuilder,
    required this.isEditableField,
    required this.validateRename,
    required this.saveEditedFields,
    required this.renameConfig,
  });

  final File file;
  final String initialName;
  final Map<String, String> globalValues;
  final List<Map<String, String>> interfaces;
  final List<Map<String, String>> peers;
  final List<String> editableInterfaceKeys;
  final List<String> editablePeerKeys;
  final String Function(String sectionType, int sectionIndex, String fieldKey)
  configFieldControllerKeyBuilder;
  final bool Function(String sectionType, String key) isEditableField;
  final String? Function(String rawName) validateRename;
  final Future<String?> Function(Map<String, TextEditingController> controllers)
  saveEditedFields;
  final Future<String?> Function(String rawName) renameConfig;

  @override
  State<_ConfigEditorPage> createState() => _ConfigEditorPageState();
}

class _ConfigEditorPageState extends State<_ConfigEditorPage> {
  late final TextEditingController _nameController;
  final Map<String, TextEditingController> _editableFieldControllers =
      <String, TextEditingController>{};

  bool _isSaving = false;
  String? _renameErrorText;
  String? _saveErrorText;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _nameController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _nameController.text.length,
    );

    for (var index = 0; index < widget.interfaces.length; index += 1) {
      final values = widget.interfaces[index];
      for (final fieldKey in widget.editableInterfaceKeys) {
        _ensureEditableFieldController(
          'interface',
          index,
          fieldKey,
          values[fieldKey] ?? '',
        );
      }
    }

    for (var index = 0; index < widget.peers.length; index += 1) {
      final values = widget.peers[index];
      for (final fieldKey in widget.editablePeerKeys) {
        _ensureEditableFieldController(
          'peer',
          index,
          fieldKey,
          values[fieldKey] ?? '',
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final controller in _editableFieldControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _ensureEditableFieldController(
    String sectionType,
    int sectionIndex,
    String fieldKey,
    String initialValue,
  ) {
    final controllerKey = widget.configFieldControllerKeyBuilder(
      sectionType,
      sectionIndex,
      fieldKey,
    );
    return _editableFieldControllers.putIfAbsent(
      controllerKey,
      () => TextEditingController(text: initialValue),
    );
  }

  List<String> _editableFieldKeys(String sectionType) {
    if (sectionType == 'interface') {
      return widget.editableInterfaceKeys;
    }
    if (sectionType == 'peer') {
      return widget.editablePeerKeys;
    }
    return const <String>[];
  }

  void _clearSaveError() {
    if (_saveErrorText == null) {
      return;
    }

    setState(() {
      _saveErrorText = null;
    });
  }

  Future<void> _handleSave() async {
    if (_isSaving) {
      return;
    }

    final validationError = widget.validateRename(_nameController.text);
    if (validationError != null) {
      setState(() {
        _renameErrorText = validationError;
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _renameErrorText = null;
      _saveErrorText = null;
    });

    final saveError = await widget.saveEditedFields(_editableFieldControllers);
    if (!mounted) {
      return;
    }

    if (saveError != null) {
      setState(() {
        _isSaving = false;
        _saveErrorText = saveError;
      });
      return;
    }

    final renameError = await widget.renameConfig(_nameController.text);
    if (!mounted) {
      return;
    }

    if (renameError != null) {
      setState(() {
        _isSaving = false;
        _renameErrorText = renameError;
      });
      return;
    }

    Navigator.of(context).pop();
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
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

  Widget _buildEditableRow(
    BuildContext context,
    String label,
    TextEditingController controller, {
    String? errorText,
    ValueChanged<String>? onSubmitted,
  }) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            enabled: !_isSaving,
            onChanged: (_) {
              if (_renameErrorText != null) {
                setState(() {
                  _renameErrorText = null;
                });
              }
              _clearSaveError();
            },
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              isDense: true,
              errorText: errorText,
              contentPadding: const EdgeInsets.all(4),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final details = <Widget>[];

    String? previousSectionType;
    void appendSectionRows(
      Map<String, String> values, {
      required String sectionType,
      required int sectionIndex,
    }) {
      if (values.isEmpty) {
        return;
      }

      if (details.isNotEmpty &&
          !(previousSectionType == 'interface' && sectionType == 'peer')) {
        details.add(
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Divider(height: 1),
          ),
        );
      }

      final renderedEditableKeys = <String>{};
      for (final entry in values.entries) {
        if (widget.isEditableField(sectionType, entry.key)) {
          renderedEditableKeys.add(entry.key);
          details.add(
            _buildEditableRow(
              context,
              entry.key,
              _ensureEditableFieldController(
                sectionType,
                sectionIndex,
                entry.key,
                entry.value,
              ),
            ),
          );
          continue;
        }

        details.add(_buildInfoRow(context, entry.key, entry.value));
      }

      for (final fieldKey in _editableFieldKeys(sectionType)) {
        if (renderedEditableKeys.contains(fieldKey)) {
          continue;
        }

        details.add(
          _buildEditableRow(
            context,
            fieldKey,
            _ensureEditableFieldController(sectionType, sectionIndex, fieldKey, ''),
          ),
        );
      }

      previousSectionType = sectionType;
    }

    appendSectionRows(widget.globalValues, sectionType: 'global', sectionIndex: 0);
    for (var index = 0; index < widget.interfaces.length; index += 1) {
      appendSectionRows(
        widget.interfaces[index],
        sectionType: 'interface',
        sectionIndex: index,
      );
    }
    for (var index = 0; index < widget.peers.length; index += 1) {
      appendSectionRows(
        widget.peers[index],
        sectionType: 'peer',
        sectionIndex: index,
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        ),
        title: const SizedBox.shrink(),
        actions: [
          IconButton(
            onPressed: _isSaving ? null : _handleSave,
            tooltip: l10n.save,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildEditableRow(
                context,
                l10n.configNameLabel,
                _nameController,
                errorText: _renameErrorText,
                onSubmitted: (_) => _handleSave(),
              ),
              ...details,
              if (_saveErrorText != null) ...[
                const SizedBox(height: 8),
                Text(
                  _saveErrorText!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum SplitTunnelDomainMode {
  all('all', 'Все домены через VPN', 'Весь трафик идет через VPN без доменных ограничений.'),
  include('include', 'Только указанные домены', 'Через VPN идут только перечисленные домены (остальной трафик — напрямую).'),
  exclude('exclude', 'Все домены кроме указанных', 'Через VPN идет весь трафик, кроме перечисленных доменов.');

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
  if (Platform.isAndroid) {
    try {
      await SubscriptionService.initializeAndroidAutomation();
    } catch (_) {}
  }
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_elementBorderRadius),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_elementBorderRadius),
        ),
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
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_elementBorderRadius),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_elementBorderRadius),
        ),
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
  static const String _playStoreAppId = 'com.wgfytunnel';
  static const MethodChannel _wireGuardChannel = MethodChannel('wgfytunnel/wireguard');
  static const double _mainActionButtonHeight = 56.0;

  List<File> _importedConfigs = const [];
  Set<String> _pinnedConfigPaths = <String>{};
  Map<String, String> _configEndpointsByPath = const <String, String>{};
  Map<String, String> _configActiveUntilByPath = const <String, String>{};
  Map<String, EndpointCountryInfo> _configCountriesByPath =
      const <String, EndpointCountryInfo>{};
  File? _selectedConf;
  Map<String, dynamic>? _parsedConf;
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _isLoadingImportedConfigs = true;
  String? _inlineMessageText;
  Timer? _inlineMessageTimer;
  Timer? _floatingNoticeTimer;
  String? _floatingNoticeText;
  bool _floatingNoticeIsError = false;
  int _rxBytes = 0;
  int _txBytes = 0;
  Timer? _statsTimer;
  DateTime? _connectionStartTime;
  static const String _connectionStartTimeKey = 'connectionStartTime';
  Timer? _uptimeTimer;
  int _tunnelStatusRevision = 0;
  SplitTunnelMode _splitTunnelMode = SplitTunnelMode.all;
  SplitTunnelDomainMode _splitTunnelDomainMode = SplitTunnelDomainMode.all;
  int _selectedAppsCount = 0;
  int _selectedDomainsCount = 0;
  bool _hasCheckedForAppUpdate = false;
  final Map<String, EndpointCountryInfo?> _countryInfoByLookupKey =
      <String, EndpointCountryInfo?>{};
  Set<String> _countryLookupsInFlight = <String>{};
  Timer? _subscriptionsRefreshTimer;
  final ScrollController _configsListScrollController = ScrollController();
  bool _wasConfigListReorderedForActiveTunnel = false;
  bool _isSendingSelectedConfigUpdate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restoreStoredSubscriptionState());
    _restoreImportedConfigs();
    _startSubscriptionsRefreshTimer();
    _refreshSplitTunnelSelections();
    _refreshTunnelStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkForAppUpdateOnLaunch());
      unawaited(_requestSubscriptionNotificationPermission());
      unawaited(_refreshSubscriptions(force: true));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clearInlineMessage();
    _floatingNoticeTimer?.cancel();
    _statsTimer?.cancel();
    _uptimeTimer?.cancel();
    _subscriptionsRefreshTimer?.cancel();
    _configsListScrollController.dispose();
    super.dispose();
  }

  Future<void> _restoreStoredSubscriptionState() async {
    final activeUntilByPath =
        await SubscriptionService.loadStoredActiveUntilByPath();
    if (!mounted) {
      return;
    }

    setState(() {
      _configActiveUntilByPath = activeUntilByPath;
    });
  }

  void _startSubscriptionsRefreshTimer() {
    _subscriptionsRefreshTimer?.cancel();
    _subscriptionsRefreshTimer = Timer.periodic(
      SubscriptionService.refreshInterval,
      (_) {
        unawaited(_refreshSubscriptions(force: true));
      },
    );
  }

  Future<void> _requestSubscriptionNotificationPermission() async {
    if (!Platform.isAndroid) {
      return;
    }

    await SubscriptionService.requestNotificationPermission();
  }

  Future<void> _refreshSubscriptions({bool force = false}) async {
    final shouldRefresh =
        force || await SubscriptionService.shouldRefreshSubscriptions();
    if (shouldRefresh) {
      final activeUntilByPath = await SubscriptionService.refreshAllSubscriptions();
      if (!mounted) {
        return;
      }

      setState(() {
        _configActiveUntilByPath = activeUntilByPath;
      });
    }

    if (Platform.isAndroid) {
      await SubscriptionService.notifyExpiredSubscriptionsIfNeeded();
    }
  }

  void _syncConfigListScrollForActiveTunnel(bool isReorderedForActiveTunnel) {
    if (_wasConfigListReorderedForActiveTunnel == isReorderedForActiveTunnel) {
      return;
    }

    _wasConfigListReorderedForActiveTunnel = isReorderedForActiveTunnel;
    if (!isReorderedForActiveTunnel) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_configsListScrollController.hasClients) {
        return;
      }

      _configsListScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      _refreshSplitTunnelSelections();
      await _refreshTunnelStatusAndRestoreTime();
      await _refreshSubscriptions();
    }
  }

  Future<void> _refreshTunnelStatusAndRestoreTime() async {
    final refreshRevision = _tunnelStatusRevision;
    try {
      final status = await _wireGuardChannel.invokeMethod<Map<dynamic, dynamic>>('getWireGuardStatus');
      if (!mounted || refreshRevision != _tunnelStatusRevision) return;
      final connected = status?['connected'] == true;
      setState(() {
        _isConnected = connected;
      });
      if (connected) {
        // Попробуем восстановить время подключения
        final prefs = await SharedPreferences.getInstance();
        final millis = prefs.getInt(_connectionStartTimeKey);
        if (millis != null) {
          _connectionStartTime = DateTime.fromMillisecondsSinceEpoch(millis);
        }
        _startStatsPolling(restoreTime: true);
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

  Future<void> _checkForAppUpdateOnLaunch() async {
    if (_hasCheckedForAppUpdate || !Platform.isAndroid || !mounted) {
      return;
    }

    _hasCheckedForAppUpdate = true;
    final pendingUpdate = await AppUpdateService.checkForUpdate();
    if (!mounted || pendingUpdate == null) {
      return;
    }

    final shouldInstall = await _showAppUpdateDialog();
    if (!mounted || !shouldInstall) {
      return;
    }

    final updateStarted = await AppUpdateService.startUpdate(pendingUpdate);
    if (updateStarted || !mounted) {
      return;
    }

    final storeOpened = await _openPlayStorePage();
    if (!mounted || storeOpened) {
      return;
    }

    _showMessage(AppLocalizations.of(context).failedOpenLink);
  }

  Future<bool> _showAppUpdateDialog() async {
    final l10n = AppLocalizations.of(context);
    final shouldInstall = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final verticalOffset = MediaQuery.sizeOf(dialogContext).height * 0.12;
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return Transform.translate(
          offset: Offset(0, -verticalOffset),
          child: Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 8),
            backgroundColor: colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_elementBorderRadius),
              side: Theme.of(dialogContext).brightness == Brightness.dark
                  ? const BorderSide(color: Colors.white, width: 1)
                  : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.updateAvailableTitle,
                      style: Theme.of(dialogContext).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    Text(l10n.updateAvailableMessage),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(false),
                          child: Text(l10n.later),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => Navigator.of(dialogContext).pop(true),
                          child: Text(l10n.updateNow),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    return shouldInstall ?? false;
  }

  Future<bool> _openPlayStorePage() async {
    final uris = <Uri>[
      Uri.parse('market://details?id=$_playStoreAppId'),
      Uri.parse('https://play.google.com/store/apps/details?id=$_playStoreAppId'),
    ];

    for (final uri in uris) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (_) {
        continue;
      }
    }

    return false;
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

  bool _isQrManagedConfigFile(File file) {
    final normalizedName = _configName(file).toLowerCase();
    return normalizedName.startsWith('qr_config_') &&
        normalizedName.endsWith('.conf');
  }

  String _displayConfigName(File file, {String? endpointText}) {
    if (_isQrManagedConfigFile(file)) {
      final normalizedEndpoint = endpointText?.trim();
      if (normalizedEndpoint != null &&
          normalizedEndpoint.isNotEmpty &&
          normalizedEndpoint != '-') {
        return normalizedEndpoint;
      }
    }

    return _configName(file);
  }

  String _configEditableName(File file) {
    final fileName = _configName(file);
    if (!fileName.toLowerCase().endsWith('.conf')) {
      return fileName;
    }

    return fileName.substring(0, fileName.length - '.conf'.length);
  }

  String _targetConfigFileName(String rawName) {
    final trimmedName = rawName.trim();
    if (trimmedName.toLowerCase().endsWith('.conf')) {
      return trimmedName;
    }

    return '$trimmedName.conf';
  }

  String? _validateConfigRename(
    File file,
    String rawName,
    AppLocalizations l10n,
  ) {
    final trimmedName = rawName.trim();
    if (trimmedName.isEmpty) {
      return l10n.configRenameEmpty;
    }

    if (RegExp(r'[<>:"/\\|?*\x00-\x1F]').hasMatch(trimmedName)) {
      return l10n.configRenameInvalid;
    }

    final targetFileName = _targetConfigFileName(trimmedName);
    if (_configName(file) == targetFileName) {
      return null;
    }

    final targetPath =
        '${file.parent.path}${Platform.pathSeparator}$targetFileName';
    final normalizedTargetPath = targetPath.toLowerCase();
    final nameAlreadyUsed = _importedConfigs.any(
      (config) =>
          config.path.toLowerCase() == normalizedTargetPath &&
          config.path != file.path,
    );
    if (nameAlreadyUsed) {
      return l10n.configRenameExists;
    }

    return null;
  }

  Future<({File? file, String? error})> _renameImportedConfig(
    File file,
    String rawName,
  ) async {
    final l10n = AppLocalizations.of(context);
    final validationError = _validateConfigRename(file, rawName, l10n);
    if (validationError != null) {
      return (file: null, error: validationError);
    }

    final targetFileName = _targetConfigFileName(rawName);
    if (_configName(file) == targetFileName) {
      return (file: file, error: null);
    }

    final renamedFile = File(
      '${file.parent.path}${Platform.pathSeparator}$targetFileName',
    );

    if (await renamedFile.exists()) {
      return (file: null, error: l10n.configRenameExists);
    }

    File actualRenamedFile;
    try {
      actualRenamedFile = await file.rename(renamedFile.path);
    } catch (_) {
      return (file: null, error: l10n.configRenameFailed);
    }

    final updatedConfigs = _importedConfigs
        .map((config) => config.path == file.path ? actualRenamedFile : config)
        .toList(growable: false);

    final updatedPinnedPaths = Set<String>.from(_pinnedConfigPaths);
    if (updatedPinnedPaths.remove(file.path)) {
      updatedPinnedPaths.add(actualRenamedFile.path);
    }

    final updatedEndpointsByPath = Map<String, String>.from(_configEndpointsByPath);
    final endpointText = updatedEndpointsByPath.remove(file.path);
    if (endpointText != null) {
      updatedEndpointsByPath[actualRenamedFile.path] = endpointText;
    }

    final updatedActiveUntilByPath = Map<String, String>.from(
      _configActiveUntilByPath,
    );
    final activeUntilText = updatedActiveUntilByPath.remove(file.path);
    if (activeUntilText != null) {
      updatedActiveUntilByPath[actualRenamedFile.path] = activeUntilText;
    }

    final updatedCountriesByPath =
        Map<String, EndpointCountryInfo>.from(_configCountriesByPath);
    final countryInfo = updatedCountriesByPath.remove(file.path);
    if (countryInfo != null) {
      updatedCountriesByPath[actualRenamedFile.path] = countryInfo;
    }

    final updatedSelectedConfig =
        _selectedConf?.path == file.path ? actualRenamedFile : _selectedConf;

    if (mounted) {
      setState(() {
        _importedConfigs = updatedConfigs;
        _pinnedConfigPaths = updatedPinnedPaths;
        _configEndpointsByPath = updatedEndpointsByPath;
        _configActiveUntilByPath = updatedActiveUntilByPath;
        _configCountriesByPath = updatedCountriesByPath;
        _selectedConf = updatedSelectedConfig;
      });
    }

    await _persistImportedConfigs(
      updatedConfigs,
      selectedConfig: updatedSelectedConfig,
      pinnedPaths: updatedPinnedPaths,
    );
    await SubscriptionService.renameConfigPathState(
      file.path,
      actualRenamedFile.path,
    );

    return (file: actualRenamedFile, error: null);
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

  List<String> _editableConfigFieldKeys(String sectionType) {
    switch (sectionType) {
      case 'interface':
        return const ['DNS'];
      case 'peer':
        return const ['AllowedIPs', 'PersistentKeepalive'];
      default:
        return const <String>[];
    }
  }

  bool _isEditableConfigField(String sectionType, String key) {
    return _editableConfigFieldKeys(sectionType).contains(key);
  }

  String _configFieldControllerKey(
    String sectionType,
    int sectionIndex,
    String fieldKey,
  ) {
    return '$sectionType:$sectionIndex:$fieldKey';
  }

  String _updatedConfigContent(
    String content,
    Map<String, String> editedFieldValues,
  ) {
    final lines = content.split(RegExp(r'\r?\n'));
    final updatedLines = <String>[];
    String? currentSectionType;
    var interfaceIndex = -1;
    var peerIndex = -1;
    var seenEditableKeys = <String>{};

    void appendMissingEditableFields() {
      if (currentSectionType == null) {
        return;
      }

      final sectionIndex = currentSectionType == 'interface'
          ? interfaceIndex
          : peerIndex;
      for (final fieldKey in _editableConfigFieldKeys(currentSectionType)) {
        if (seenEditableKeys.contains(fieldKey)) {
          continue;
        }

        final controllerKey = _configFieldControllerKey(
          currentSectionType,
          sectionIndex,
          fieldKey,
        );
        final value = editedFieldValues[controllerKey]?.trim() ?? '';
        if (value.isEmpty) {
          continue;
        }

        updatedLines.add('$fieldKey = $value');
      }

      seenEditableKeys = <String>{};
    }

    for (final rawLine in lines) {
      final trimmedLine = rawLine.trim();
      if (trimmedLine.startsWith('[') && trimmedLine.endsWith(']')) {
        appendMissingEditableFields();

        final sectionName = trimmedLine
            .substring(1, trimmedLine.length - 1)
            .trim()
            .toLowerCase();
        if (sectionName == 'interface') {
          currentSectionType = 'interface';
          interfaceIndex += 1;
        } else if (sectionName == 'peer') {
          currentSectionType = 'peer';
          peerIndex += 1;
        } else {
          currentSectionType = null;
        }

        seenEditableKeys = <String>{};
        updatedLines.add(rawLine);
        continue;
      }

      if (currentSectionType != null) {
        final separatorIndex = rawLine.indexOf('=');
        if (separatorIndex > 0) {
          final key = rawLine.substring(0, separatorIndex).trim();
          if (_isEditableConfigField(currentSectionType, key)) {
            seenEditableKeys.add(key);
            final sectionIndex = currentSectionType == 'interface'
                ? interfaceIndex
                : peerIndex;
            final controllerKey = _configFieldControllerKey(
              currentSectionType,
              sectionIndex,
              key,
            );
            final value = editedFieldValues[controllerKey]?.trim() ?? '';
            if (value.isNotEmpty) {
              updatedLines.add('$key = $value');
            }
            continue;
          }
        }
      }

      updatedLines.add(rawLine);
    }

    appendMissingEditableFields();
    return '${updatedLines.join('\n').trimRight()}\n';
  }

  Future<String?> _saveEditedConfigFields(
    File file,
    Map<String, TextEditingController> controllers,
  ) async {
    final l10n = AppLocalizations.of(context);
    final content = await _readConfigContent(file);
    if (content == null) {
      return l10n.failedReadFile;
    }

    final editedFieldValues = <String, String>{
      for (final entry in controllers.entries) entry.key: entry.value.text,
    };
    final updatedContent = _updatedConfigContent(content, editedFieldValues);

    try {
      await file.writeAsString(updatedContent, flush: true);
    } catch (_) {
      return l10n.configSaveFailed;
    }

    final updatedParsedConfig = _parseConfigContent(updatedContent);
    if (updatedParsedConfig == null) {
      return l10n.configSaveFailed;
    }

    final updatedEndpointsByPath = <String, String>{
      ..._configEndpointsByPath,
      file.path: _configEndpointText(updatedParsedConfig),
    };

    if (mounted) {
      setState(() {
        _configEndpointsByPath = updatedEndpointsByPath;
        if (_selectedConf?.path == file.path) {
          _parsedConf = updatedParsedConfig;
        }
      });
    }

    unawaited(
      _queueCountryLookupsForConfigs(
        [file],
        endpointsByPath: updatedEndpointsByPath,
      ),
    );

    return null;
  }

  EndpointCountryInfo? _configCountryInfo(String endpointText, String filePath) {
    final lookupKey = EndpointCountryService.lookupKeyForEndpoint(endpointText);
    if (lookupKey == null) {
      return null;
    }

    final countryInfo = _configCountriesByPath[filePath];
    if (countryInfo != null) {
      return countryInfo;
    }

    return _countryInfoByLookupKey[lookupKey];
  }

  bool _isConfigCountryLookupInFlight(String endpointText) {
    final lookupKey = EndpointCountryService.lookupKeyForEndpoint(endpointText);
    if (lookupKey == null) {
      return false;
    }

    return _countryLookupsInFlight.contains(lookupKey);
  }

  Future<void> _queueCountryLookupsForConfigs(
    Iterable<File> configs, {
    Map<String, String>? endpointsByPath,
  }) async {
    for (final file in configs) {
      unawaited(
        _resolveCountryForConfig(
          file,
          endpointsByPath: endpointsByPath,
        ),
      );
    }
  }

  Future<void> _resolveCountryForConfig(
    File file, {
    Map<String, String>? endpointsByPath,
  }) async {
    final endpointText = endpointsByPath?[file.path] ?? _configEndpointsByPath[file.path];
    if (endpointText == null || endpointText.trim().isEmpty || endpointText == '-') {
      if (!mounted) {
        return;
      }

      setState(() {
        final updatedCountriesByPath =
            Map<String, EndpointCountryInfo>.from(_configCountriesByPath)
              ..remove(file.path);
        _configCountriesByPath = updatedCountriesByPath;
      });
      return;
    }

    final lookupKey = EndpointCountryService.lookupKeyForEndpoint(endpointText);
    if (lookupKey == null) {
      if (!mounted) {
        return;
      }

      setState(() {
        final updatedCountriesByPath =
            Map<String, EndpointCountryInfo>.from(_configCountriesByPath)
              ..remove(file.path);
        _configCountriesByPath = updatedCountriesByPath;
      });
      return;
    }

    if (_countryInfoByLookupKey.containsKey(lookupKey)) {
      if (!mounted) {
        return;
      }

      setState(() {
        _configCountriesByPath = _updatedCountriesByPathForLookupKey(
          lookupKey,
          _countryInfoByLookupKey[lookupKey],
          endpointsByPath: endpointsByPath,
        );
      });
      return;
    }

    if (_countryLookupsInFlight.contains(lookupKey)) {
      return;
    }

    if (mounted) {
      setState(() {
        _countryLookupsInFlight = Set<String>.from(_countryLookupsInFlight)
          ..add(lookupKey);
      });
    }

    final countryInfo = await EndpointCountryService.lookupCountryForEndpoint(
      endpointText,
    );
    _countryInfoByLookupKey[lookupKey] = countryInfo;

    if (!mounted) {
      return;
    }

    setState(() {
      _countryLookupsInFlight = Set<String>.from(_countryLookupsInFlight)
        ..remove(lookupKey);
      _configCountriesByPath = _updatedCountriesByPathForLookupKey(
        lookupKey,
        countryInfo,
        endpointsByPath: endpointsByPath,
      );
    });
  }

  Map<String, EndpointCountryInfo> _updatedCountriesByPathForLookupKey(
    String lookupKey,
    EndpointCountryInfo? countryInfo, {
    Map<String, String>? endpointsByPath,
  }) {
    final updatedCountriesByPath =
        Map<String, EndpointCountryInfo>.from(_configCountriesByPath);
    final activeEndpointsByPath = endpointsByPath ?? _configEndpointsByPath;

    for (final entry in activeEndpointsByPath.entries) {
      final entryLookupKey = EndpointCountryService.lookupKeyForEndpoint(entry.value);
      if (entryLookupKey != lookupKey) {
        continue;
      }

      if (countryInfo == null) {
        updatedCountriesByPath.remove(entry.key);
      } else {
        updatedCountriesByPath[entry.key] = countryInfo;
      }
    }

    return updatedCountriesByPath;
  }

  Widget _buildConfigCountryBadge({
    required String filePath,
    required String endpointText,
    required bool isSelected,
    required ColorScheme colorScheme,
    bool forceWhiteIcon = false,
  }) {
    final countryInfo = _configCountryInfo(endpointText, filePath);
    final isLookupInFlight = _isConfigCountryLookupInFlight(endpointText);
    final selectedForegroundColor = colorScheme.brightness == Brightness.dark
        ? Colors.white
        : Colors.black;
    final foregroundColor = forceWhiteIcon
      ? Colors.white
      : (isSelected
        ? selectedForegroundColor
        : colorScheme.onSurfaceVariant);

    if (isLookupInFlight) {
      return SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
            ),
          ),
        ),
      );
    }

    if (countryInfo == null) {
      return SizedBox(
        width: 44,
        height: 44,
        child: Icon(
          Icons.public_outlined,
          color: foregroundColor,
        ),
      );
    }

    return Tooltip(
      message: countryInfo.countryName,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Text(
            countryInfo.flagEmoji,
            style: const TextStyle(fontSize: 24, height: 1),
          ),
        ),
      ),
    );
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

    unawaited(
      _queueCountryLookupsForConfigs(
        orderedConfigs,
        endpointsByPath: endpointsByPath,
      ),
    );
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
    unawaited(_queueCountryLookupsForConfigs([file]));
    await ImportedConfigsPrefs.saveSelectedPath(file.path);
  }

  Future<void> _sendSelectedConfigUpdate(File file) async {
    if (_isSendingSelectedConfigUpdate) {
      return;
    }

    final l10n = AppLocalizations.of(context);
    final configName = _configName(file);

    if (mounted) {
      setState(() {
        _isSendingSelectedConfigUpdate = true;
      });
    }

    try {
      final result = await SubscriptionService.updateSubscriptionForPath(
        file.path,
      );
      if (result.error != null) {
        _showFloatingNotice(
          l10n.configUpdateErrorMessage(configName),
          isError: true,
        );
        return;
      }

      final activeUntilByPath =
          await SubscriptionService.loadStoredActiveUntilByPath();
      if (mounted) {
        setState(() {
          _configActiveUntilByPath = activeUntilByPath;
        });
      }

      if (Platform.isAndroid) {
        await SubscriptionService.notifyExpiredSubscriptionsIfNeeded();
      }
      _showFloatingNotice(l10n.configUpdatedMessage(configName));
    } catch (_) {
      _showFloatingNotice(
        l10n.configUpdateErrorMessage(configName),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSendingSelectedConfigUpdate = false;
        });
      }
    }
  }

  void _removeImportedConfig(File file) {
    final updatedPinnedPaths = Set<String>.from(_pinnedConfigPaths)
      ..remove(file.path);
    final updatedConfigs = _importedConfigs
        .where((config) => config.path != file.path)
        .toList(growable: false);
    final updatedEndpointsByPath = Map<String, String>.from(_configEndpointsByPath)
      ..remove(file.path);
    final updatedActiveUntilByPath = Map<String, String>.from(_configActiveUntilByPath)
      ..remove(file.path);
    final updatedCountriesByPath =
        Map<String, EndpointCountryInfo>.from(_configCountriesByPath)
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
      _configActiveUntilByPath = updatedActiveUntilByPath;
      _configCountriesByPath = updatedCountriesByPath;
      _selectedConf = nextSelectedConfig;
      _parsedConf = nextParsedConfig;
    });

    _syncRemovedConfig(
      updatedConfigs,
      nextSelectedConfig,
      removedSelectedConfig,
      updatedPinnedPaths,
    );
    unawaited(SubscriptionService.removeConfigPathState(file.path));
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

  void _startStatsPolling({bool restoreTime = false}) async {
    _statsTimer?.cancel();
    _uptimeTimer?.cancel();
    if (!restoreTime || _connectionStartTime == null) {
      _connectionStartTime = DateTime.now();
      // Сохраняем время подключения
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_connectionStartTimeKey, _connectionStartTime!.millisecondsSinceEpoch);
    }
    _fetchStats();
    _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
        _fetchStats();
      }
    });
  }

  void _stopStatsPolling() async {
    _statsTimer?.cancel();
    _statsTimer = null;
    _uptimeTimer?.cancel();
    _uptimeTimer = null;
    _connectionStartTime = null;
    // Удаляем сохранённое время подключения
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_connectionStartTimeKey);
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

  Future<File> _createManagedConfigFile(String filePrefix) async {
    final appDirectory = await getApplicationDocumentsDirectory();
    final configsDirectory = Directory(
      '${appDirectory.path}${Platform.pathSeparator}imported_configs',
    );

    if (!await configsDirectory.exists()) {
      await configsDirectory.create(recursive: true);
    }

    return File(
      '${configsDirectory.path}${Platform.pathSeparator}'
      '${filePrefix}_${DateTime.now().millisecondsSinceEpoch}.conf',
    );
  }

  Future<void> _importConfigFile(
    File file, {
    String? contentOverride,
  }) async {
    final l10n = AppLocalizations.of(context);

    try {
      final content = (contentOverride ?? await _readConfigContent(file))?.trim();
      if (content == null || content.isEmpty) {
        _showMessage(l10n.failedReadFile);
        return;
      }

      final parsed = _parseConfigContent(content);
      if (parsed == null) {
        _showMessage(l10n.failedParseConfig);
        return;
      }

      if (parsed['isValid'] != true) {
        _showMessage(l10n.invalidConfig);
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

      if (contentOverride != null) {
        await file.writeAsString(content, flush: true);
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
      unawaited(
        _queueCountryLookupsForConfigs(
          [file],
          endpointsByPath: updatedEndpointsByPath,
        ),
      );
      await _persistImportedConfigs(updatedConfigs, selectedConfig: file);
    } catch (e) {
      _showMessage('Error importing file: $e');
    }
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

      await _importConfigFile(file);
    } catch (e) {
      _showMessage('Error importing file: $e');
    }
  }

  Future<void> _scanQrConfig() async {
    final scannedConfig = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => const QrConfigScannerPage(),
      ),
    );
    if (!mounted || scannedConfig == null || scannedConfig.trim().isEmpty) {
      return;
    }

    final managedFile = await _createManagedConfigFile('qr_config');
    await _importConfigFile(
      managedFile,
      contentOverride: scannedConfig,
    );
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

  void _showFloatingNotice(String text, {bool isError = false}) {
    if (!mounted) {
      return;
    }

    _floatingNoticeTimer?.cancel();
    setState(() {
      _floatingNoticeText = text;
      _floatingNoticeIsError = isError;
    });
    _floatingNoticeTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) {
        return;
      }
      _clearFloatingNotice();
    });
  }

  void _clearFloatingNotice() {
    _floatingNoticeTimer?.cancel();
    _floatingNoticeTimer = null;
    if (!mounted) {
      _floatingNoticeText = null;
      _floatingNoticeIsError = false;
      return;
    }

    setState(() {
      _floatingNoticeText = null;
      _floatingNoticeIsError = false;
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

  Widget _buildFloatingNoticeOverlay() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isVisible = _floatingNoticeText != null;
    final backgroundColor = isDark ? Colors.white : Colors.black;
    final foregroundColor = isDark ? Colors.black : Colors.white;
    final shadowColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.20)
        : const Color.fromRGBO(0, 0, 0, 0.20);
    final iconColor = _floatingNoticeIsError
        ? const Color(0xFFFF5A5F)
        : foregroundColor;

    return Positioned(
      top: 0,
      left: 16,
      right: 16,
      child: IgnorePointer(
        ignoring: !isVisible,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          transitionBuilder: (child, animation) {
            final curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: curvedAnimation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.12),
                  end: Offset.zero,
                ).animate(curvedAnimation),
                child: child,
              ),
            );
          },
          child: !isVisible
              ? const SizedBox.shrink(key: ValueKey<String>('hidden-notice'))
              : Center(
                  key: ValueKey<String>(
                    'visible-notice-${_floatingNoticeText!}-$_floatingNoticeIsError',
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Dismissible(
                      key: ValueKey<String>(
                        'dismiss-notice-${_floatingNoticeText!}-$_floatingNoticeIsError',
                      ),
                      direction: DismissDirection.horizontal,
                      onDismissed: (_) => _clearFloatingNotice(),
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          decoration: BoxDecoration(
                            color: backgroundColor,
                            borderRadius: const BorderRadius.all(
                              Radius.circular(_elementBorderRadius),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: shadowColor,
                                blurRadius: 8,
                                spreadRadius: 0,
                                offset: Offset.zero,
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                            child: Row(
                              children: [
                                Icon(
                                  _floatingNoticeIsError
                                      ? Icons.error_outline_rounded
                                      : Icons.check_circle_outline_rounded,
                                  color: iconColor,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _floatingNoticeText ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: foregroundColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: _clearFloatingNotice,
                                  icon: Icon(
                                    Icons.close_rounded,
                                    color: foregroundColor,
                                  ),
                                  splashRadius: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
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
    final globalValues = _stringMap(parsedConfig['global']);

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _ConfigEditorPage(
          file: file,
          initialName: _configEditableName(file),
          globalValues: globalValues,
          interfaces: interfaces,
          peers: peers,
          editableInterfaceKeys: _editableConfigFieldKeys('interface'),
          editablePeerKeys: _editableConfigFieldKeys('peer'),
          configFieldControllerKeyBuilder: _configFieldControllerKey,
          isEditableField: _isEditableConfigField,
          validateRename: (rawName) => _validateConfigRename(file, rawName, l10n),
          saveEditedFields: (controllers) => _saveEditedConfigFields(file, controllers),
          renameConfig: (rawName) async {
            final renameResult = await _renameImportedConfig(file, rawName);
            return renameResult.error;
          },
        ),
      ),
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

  Widget _buildImportedConfigsList({required double viewportHeight}) {
    final l10n = AppLocalizations.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_isLoadingImportedConfigs) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_importedConfigs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            l10n.importOrScanWireGuardConfig,
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    final hasSelectedConfigInList =
        _selectedConf != null &&
        _importedConfigs.any((config) => config.path == _selectedConf!.path);
    final isReorderedForActiveTunnel =
        (_isConnected || _isConnecting) && hasSelectedConfigInList;
    final selectedOriginalIndex = hasSelectedConfigInList
        ? _importedConfigs.indexWhere(
            (config) => config.path == _selectedConf!.path,
          )
        : -1;
    final displayedConfigs = isReorderedForActiveTunnel
        ? <File>[
            _selectedConf!,
            ..._importedConfigs.where(
              (config) => config.path != _selectedConf!.path,
            ),
          ]
        : _importedConfigs;
    _syncConfigListScrollForActiveTunnel(isReorderedForActiveTunnel);

    const configItemSpacing = 4.0;
    const listTopPadding = 12.0;
    const listBottomPadding = 8.0;
    const configDateSpacing = 6.0;
    const configDateHeight = 18.0;
    double configDateExtraHeightForPath(String path) {
      final activeUntilText = _configActiveUntilByPath[path];
      return activeUntilText == null || activeUntilText.trim().isEmpty
          ? 0.0
          : configDateSpacing + configDateHeight;
    }

    double configItemExtentForPath(String path) {
      return _mainActionButtonHeight +
          configItemSpacing +
          configDateExtraHeightForPath(path);
    }

    final totalDateExtraHeight = displayedConfigs.fold<double>(
      0.0,
      (sum, file) => sum + configDateExtraHeightForPath(file.path),
    );
    final totalContentHeight =
        (displayedConfigs.length * _mainActionButtonHeight) +
        ((displayedConfigs.isNotEmpty ? displayedConfigs.length - 1 : 0) *
            configItemSpacing) +
        totalDateExtraHeight +
        listTopPadding +
        listBottomPadding;
    final shouldShowBottomShadow = totalContentHeight > viewportHeight;
    final selectedConfigMoveExtent = hasSelectedConfigInList
        ? configItemExtentForPath(_selectedConf!.path)
        : 0.0;

    return Stack(
      children: [
        ListView.separated(
          controller: _configsListScrollController,
          padding: const EdgeInsets.fromLTRB(
            16,
            listTopPadding,
            16,
            listBottomPadding,
          ),
          itemCount: displayedConfigs.length,
          separatorBuilder: (context, index) => const SizedBox(height: 4),
          itemBuilder: (context, index) {
            final file = displayedConfigs[index];
            final isSelected = _selectedConf?.path == file.path;
            final isPinned = _pinnedConfigPaths.contains(file.path);
            final isInactiveWhileConnected =
              (_isConnected || _isConnecting) && !isSelected;
            final endpointText = _configEndpointsByPath[file.path] ?? '-';
            final activeUntilText = _configActiveUntilByPath[file.path];
            final showActiveUntil =
                activeUntilText != null &&
                activeUntilText.trim().isNotEmpty;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final itemForegroundColor =
              isDark ? Colors.white : colorScheme.onSurface;
            final endpointColor =
              isDark ? Colors.white : colorScheme.onSurfaceVariant;
            final itemContentOpacity =
              isDark && isInactiveWhileConnected ? 0.5 : 1.0;
            final cardBackgroundColor = isDark
              ? Colors.transparent
              : (isInactiveWhileConnected
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.white);
            final cardBorder = isDark
              ? Border.all(color: const Color(0xFF141414), width: 2)
              : null;
            final countryBadge = _buildConfigCountryBadge(
              filePath: file.path,
              endpointText: endpointText,
              isSelected: isSelected,
              colorScheme: colorScheme,
              forceWhiteIcon: isDark,
            );
            final dismissibleBorderRadius = BorderRadius.circular(
              _elementBorderRadius,
            );
            final dismissDirection = isInactiveWhileConnected
                ? DismissDirection.none
                : (_isConnected
                      ? DismissDirection.startToEnd
                      : DismissDirection.horizontal);
            final originalIndex = _importedConfigs.indexWhere(
              (config) => config.path == file.path,
            );
            final moveOffset = !isReorderedForActiveTunnel ||
                    selectedOriginalIndex <= 0
                ? 0.0
                : isSelected
                ? _importedConfigs
                  .take(selectedOriginalIndex)
                  .fold<double>(
                    0.0,
                    (sum, config) =>
                      sum + configItemExtentForPath(config.path),
                  )
                    : (originalIndex >= 0 &&
                          originalIndex < selectedOriginalIndex
                  ? -selectedConfigMoveExtent
                      : 0.0);

            return TweenAnimationBuilder<double>(
              key: ValueKey(
                '${file.path}-${isReorderedForActiveTunnel ? 'reordered' : 'normal'}',
              ),
              tween: Tween<double>(begin: moveOffset, end: 0),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              builder: (context, offset, child) => Transform.translate(
                offset: Offset(0, offset),
                child: child,
              ),
              child: Dismissible(
                key: ValueKey(file.path),
                direction: dismissDirection,
                background: Container(
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: dismissibleBorderRadius,
                  ),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                        color: const Color.fromRGBO(255, 179, 0, 1),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isPinned ? l10n.unpinConfig : l10n.pinConfig,
                        style: const TextStyle(
                          color: Color.fromRGBO(255, 179, 0, 1),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                secondaryBackground: Container(
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: dismissibleBorderRadius,
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.delete,
                        color: Color.fromRGBO(198, 40, 40, 1),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        materialL10n.deleteButtonTooltip,
                        style: const TextStyle(
                          color: Color.fromRGBO(198, 40, 40, 1),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: cardBackgroundColor,
                        borderRadius: dismissibleBorderRadius,
                        border: cardBorder,
                        boxShadow: isDark
                            ? null
                            : const [
                                BoxShadow(
                                  color: Color.fromRGBO(0, 0, 0, 0.20),
                                  blurRadius: 8,
                                  spreadRadius: 0,
                                  offset: Offset(0, 2),
                                ),
                              ],
                      ),
                      child: Material(
                        color: cardBackgroundColor,
                        borderRadius: dismissibleBorderRadius,
                        clipBehavior: Clip.antiAlias,
                        child: Ink(
                          decoration: BoxDecoration(
                            color: cardBackgroundColor,
                            borderRadius: dismissibleBorderRadius,
                          ),
                          child: InkWell(
                            borderRadius: dismissibleBorderRadius,
                            onTap: isInactiveWhileConnected
                                ? null
                                : () => _selectImportedConfig(file),
                            onLongPress: isInactiveWhileConnected
                                ? null
                                : () => _showConfigInfoDialog(file),
                            child: SizedBox(
                              height: _mainActionButtonHeight,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Opacity(
                                  opacity: itemContentOpacity,
                                  child: Row(
                                    children: [
                                      countryBadge,
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _displayConfigName(
                                                file,
                                                endpointText: endpointText,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: textTheme.titleMedium?.copyWith(
                                                color: itemForegroundColor,
                                              ),
                                            ),
                                            Text(
                                              endpointText,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: textTheme.bodyMedium?.copyWith(
                                                color: endpointColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Row(
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
                                          if (isSelected) ...[
                                            SizedBox(
                                              height: 32,
                                              width: 32,
                                              child: FilledButton(
                                                onPressed: _isSendingSelectedConfigUpdate
                                                    ? null
                                                    : () => _sendSelectedConfigUpdate(file),
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: isDark
                                                      ? Colors.white.withValues(alpha: 0.12)
                                                      : Colors.black,
                                                  foregroundColor: Colors.white,
                                                  minimumSize: Size.zero,
                                                  padding: EdgeInsets.zero,
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                  visualDensity: VisualDensity.compact,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(
                                                      _elementBorderRadius,
                                                    ),
                                                  ),
                                                ),
                                                child: _isSendingSelectedConfigUpdate
                                                    ? const SizedBox(
                                                        width: 14,
                                                        height: 14,
                                                        child: CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.white,
                                                        ),
                                                      )
                                                    : const Icon(
                                                        Icons.refresh,
                                                        size: 18,
                                                        color: Colors.white,
                                                      ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                          ],
                                          if (isSelected)
                                            Icon(
                                              Icons.check_circle,
                                              color: isDark ? Colors.white : Colors.black,
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (showActiveUntil)
                      Padding(
                        padding: const EdgeInsets.only(top: configDateSpacing),
                        child: Align(
                          alignment: Alignment.center,
                          child: Text(
                            '${l10n.activeUntilLabel} $activeUntilText',
                            textAlign: TextAlign.center,
                            style: textTheme.bodySmall?.copyWith(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.78)
                                  : colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        if (shouldShowBottomShadow)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: SizedBox(
                height: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        const Color.fromRGBO(0, 0, 0, 0.20),
                        const Color.fromRGBO(0, 0, 0, 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasValidConf = _parsedConf?['isValid'] == true;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const darkButtonBackgroundColor = Color(0xFF141414);
    const disconnectButtonColor = Color.fromRGBO(180, 80, 80, 1);
    final showActiveTunnelUi = _isConnected || _isConnecting;
    final connectButtonBackgroundColor = showActiveTunnelUi
      ? disconnectButtonColor
      : (isDark ? darkButtonBackgroundColor : Colors.black);
    final connectButtonForegroundColor = showActiveTunnelUi
      ? Colors.white
      : (isDark ? Colors.white : Colors.white);
    const connectionAnimDuration = Duration(milliseconds: 500);
    const connectionAnimCurve = Curves.fastOutSlowIn;
    const defaultConfigsListHeightFactor = 1.0;
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
      borderRadius: BorderRadius.circular(_elementBorderRadius),
    );
    final secondaryActionDecoration = BoxDecoration(
      color: isDark ? Colors.transparent : Colors.white,
      borderRadius: const BorderRadius.all(
        Radius.circular(_elementBorderRadius),
      ),
      boxShadow: isDark
          ? null
          : const [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.20),
                blurRadius: 8,
                spreadRadius: 0,
                offset: Offset(0, 2),
              ),
            ],
    );
    final secondaryActionBackgroundColor =
        isDark ? Colors.transparent : Colors.white;
    final secondaryActionForegroundColor =
        isDark ? Colors.white : Colors.black87;
    final secondaryActionBorderSide = isDark
      ? BorderSide(color: darkButtonBackgroundColor, width: 2)
        : BorderSide.none;
    final connectActionDecoration = BoxDecoration(
      borderRadius: const BorderRadius.all(
        Radius.circular(_elementBorderRadius),
      ),
      boxShadow: secondaryActionDecoration.boxShadow,
    );
    final systemUiOverlayStyle = (isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark)
        .copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.black,
          systemNavigationBarDividerColor: Colors.black,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarContrastEnforced: false,
        );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemUiOverlayStyle,
      child: Scaffold(
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
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Tooltip(
              message: l10n.splitTunneling,
              child: SizedBox.square(
                dimension: 36,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: isDark ? darkButtonBackgroundColor : Colors.white,
                    borderRadius: const BorderRadius.all(
                      Radius.circular(_elementBorderRadius),
                    ),
                    boxShadow: isDark
                        ? null
                        : const [
                            BoxShadow(
                              color: Color.fromRGBO(0, 0, 0, 0.20),
                              blurRadius: 8,
                              spreadRadius: 0,
                              offset: Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Material(
                    color: isDark ? darkButtonBackgroundColor : Colors.white,
                    borderRadius: const BorderRadius.all(
                      Radius.circular(_elementBorderRadius),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => SplitTunnelSettingsPage(
                              isVpnConnected: () => _isConnected,
                            ),
                          ),
                        ).then((_) {
                          _refreshSplitTunnelSelections();
                          _refreshTunnelStatus();
                        });
                      },
                      child: Center(
                        child: Icon(
                          Icons.tune,
                          size: 24,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 16),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.asset(
                      'map.png',
                      fit: BoxFit.fitWidth,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: _buildVpnfyImage(width: 220),
                    ),
                  ],
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final actionButtonsBlockHeight = (_mainActionButtonHeight * 2) + 32.0;
                      final availableListHeight = constraints.maxHeight > actionButtonsBlockHeight
                          ? constraints.maxHeight - actionButtonsBlockHeight
                          : 0.0;
                      final targetListHeight =
                          availableListHeight * defaultConfigsListHeightFactor;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  height: _mainActionButtonHeight,
                                  child: actionInfoText == null || showActiveTunnelUi
                                      ? AnimatedOpacity(
                                          duration: connectionAnimDuration,
                                          curve: connectionAnimCurve,
                                          opacity: showActiveTunnelUi ? 0.5 : 1.0,
                                          child: IgnorePointer(
                                            ignoring: showActiveTunnelUi,
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: DecoratedBox(
                                                    decoration: secondaryActionDecoration,
                                                    child: Tooltip(
                                                      message: l10n.selectConfFile,
                                                      child: OutlinedButton(
                                                        onPressed: _importConf,
                                                        style: OutlinedButton.styleFrom(
                                                          backgroundColor: secondaryActionBackgroundColor,
                                                          foregroundColor: secondaryActionForegroundColor,
                                                          minimumSize: const Size.fromHeight(_mainActionButtonHeight),
                                                          padding: EdgeInsets.zero,
                                                          textStyle: actionButtonTextStyle,
                                                          shape: actionButtonShape,
                                                          side: secondaryActionBorderSide,
                                                          elevation: 0,
                                                        ),
                                                        child: const Icon(Icons.insert_drive_file_outlined, size: 28),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: DecoratedBox(
                                                    decoration: secondaryActionDecoration,
                                                    child: Tooltip(
                                                      message: l10n.scanQrCode,
                                                      child: OutlinedButton(
                                                        onPressed: _scanQrConfig,
                                                        style: OutlinedButton.styleFrom(
                                                          backgroundColor: secondaryActionBackgroundColor,
                                                          foregroundColor: secondaryActionForegroundColor,
                                                          minimumSize: const Size.fromHeight(_mainActionButtonHeight),
                                                          padding: EdgeInsets.zero,
                                                          textStyle: actionButtonTextStyle,
                                                          shape: actionButtonShape,
                                                          side: secondaryActionBorderSide,
                                                          elevation: 0,
                                                        ),
                                                        child: const Icon(Icons.qr_code_scanner, size: 28),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
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
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: _mainActionButtonHeight,
                                  child: DecoratedBox(
                                    decoration: connectActionDecoration,
                                    child: AnimatedOpacity(
                                      duration: connectionAnimDuration,
                                      curve: connectionAnimCurve,
                                      opacity: connectButtonOpacity,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          minimumSize: const Size.fromHeight(_mainActionButtonHeight),
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
                                        child: Text(
                                          _isConnected
                                              ? '${_formatUptime()} / ${_formatBytes(_rxBytes + _txBytes)}'
                                              : l10n.connect,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 0),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: targetListHeight,
                            child: ClipRect(
                              child: Transform.translate(
                                offset: const Offset(0, -4),
                                child: _buildImportedConfigsList(
                                  viewportHeight: targetListHeight,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
            _buildFloatingNoticeOverlay(),
          ],
        ),
      ),
    ));
  }
}
