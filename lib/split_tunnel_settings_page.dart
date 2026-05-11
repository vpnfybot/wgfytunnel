import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'l10n/app_localizations.dart';
import 'l10n/language_service.dart';
import 'main.dart';
import 'split_tunnel_prefs.dart';
import 'subscription_service.dart';
import 'theme_service.dart';

class SplitTunnelSettingsPage extends StatefulWidget {
  const SplitTunnelSettingsPage({super.key, required this.isVpnConnected});

  final bool Function() isVpnConnected;

  @override
  State<SplitTunnelSettingsPage> createState() =>
      _SplitTunnelSettingsPageState();
}

class _SplitTunnelSettingsPageState extends State<SplitTunnelSettingsPage> {
  static const double _settingsBlockRadius = 12.0;
  static const double _pickerListSpacing = 4.0;
  static const double _inputRowHeight = 56.0;
  static const Color _darkThemeOptionColor = Color(0xFF141414);
  static const MethodChannel _wireGuardChannel = MethodChannel(
    'wgfytunnel/wireguard',
  );
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  List<InstalledApp> _installedApps = const [];
  bool _hasRequestedApps = false;
  bool _isLoadingApps = false;
  bool _isLoadingPrefs = true;
  SplitTunnelMode _splitTunnelMode = SplitTunnelMode.all;
  Set<String> _selectedPackages = <String>{};
  String _appSearchQuery = '';
  final TextEditingController _appSearchController = TextEditingController();
  SplitTunnelDomainMode _domainMode = SplitTunnelDomainMode.all;
  final List<String> _domainList = <String>[];
  final TextEditingController _domainInputController = TextEditingController();
  String _appVersion = '0.0.0';
  bool? _notificationsEnabled;
  bool _isUpdatingNotificationsPermission = false;
  bool _showReconnectBanner = false;
  Timer? _reconnectBannerTimer;
  Timer? _floatingNoticeTimer;
  String? _floatingNoticeText;
  bool _floatingNoticeIsError = false;
  IconData? _floatingNoticeIcon;
  Completer<void>? _appsLoadCompleter;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _loadPrefs();
    _loadNotificationsPermissionStatus();
  }

  @override
  void dispose() {
    _reconnectBannerTimer?.cancel();
    _clearFloatingNotice();
    _appSearchController.dispose();
    _domainInputController.dispose();
    super.dispose();
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final version = _sanitizeAppVersion(packageInfo.version);
      if (!mounted) return;
      setState(() {
        _appVersion = version;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _appVersion = '0.0.0';
      });
    }
  }

  String _sanitizeAppVersion(String version) {
    final match = RegExp(r'\d+\.\d+\.\d+').firstMatch(version);
    return match?.group(0) ?? '0.0.0';
  }

  Future<void> _loadNotificationsPermissionStatus() async {
    final enabled = await SubscriptionService.areNotificationsEnabled();
    if (!mounted) {
      return;
    }

    setState(() {
      _notificationsEnabled = enabled;
    });
  }

  Future<void> _handleNotificationsPermissionAction() async {
    if (_isUpdatingNotificationsPermission) {
      return;
    }

    if (defaultTargetPlatform != TargetPlatform.android) {
      await _loadNotificationsPermissionStatus();
      return;
    }

    setState(() {
      _isUpdatingNotificationsPermission = true;
    });

    try {
      final currentStatus =
          _notificationsEnabled ??
          await SubscriptionService.areNotificationsEnabled();
      if (currentStatus == false) {
        await SubscriptionService.requestNotificationPermission();
      }
      await _loadNotificationsPermissionStatus();
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingNotificationsPermission = false;
        });
      }
    }
  }

  Future<void> _showAboutDialog() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (pageContext) {
          final l10n = AppLocalizations.of(pageContext);
          final textTheme = Theme.of(pageContext).textTheme;

          return Scaffold(
            appBar: AppBar(
              leading: BackButton(
                onPressed: () => Navigator.of(pageContext).pop(),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _showFullLicensesPage(pageContext);
                  },
                  child: Text(l10n.viewFullLicenses),
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.aboutTitle, style: textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SelectionArea(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.aboutLicensesIntro),
                            const SizedBox(height: 16),
                            _buildAboutComponentSection(
                              pageContext,
                              title: 'sing-box',
                              usage: l10n.aboutSingBoxUsage,
                              author:
                                  'Copyright (C) 2022 by nekohasekai <contact-sagernet@sekai.icu>',
                              license:
                                  'GNU General Public License v3.0 or later (GPL-3.0-or-later)',
                            ),
                            _buildAboutComponentSection(
                              pageContext,
                              title: 'NEKOBOX libcore',
                              usage: l10n.aboutLibcoreUsage,
                              author:
                                  'Copyright (C) 2021 by nekohasekai <contact-sagernet@sekai.icu>',
                              license:
                                  'GNU General Public License v3.0 or later (GPL-3.0-or-later)',
                            ),
                            _buildAboutComponentSection(
                              pageContext,
                              title: 'WireGuard Tunnel Library',
                              usage: l10n.aboutWireGuardUsage,
                              author: 'WireGuard (team@wireguard.com)',
                              license: 'Apache License 2.0',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.aboutLicensesFooter,
                              style: textTheme.bodySmall,
                            ),
                          ],
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
    );
  }

  Future<void> _showFullLicensesPage(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const _FullLicensesPage()),
    );
  }

  Widget _buildAboutComponentSection(
    BuildContext context, {
    required String title,
    required String usage,
    required String author,
    required String license,
  }) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text('${l10n.componentUsageLabel}: $usage'),
          const SizedBox(height: 4),
          Text('${l10n.componentAuthorLabel}: $author'),
          const SizedBox(height: 4),
          Text('${l10n.componentLicenseLabel}: $license'),
        ],
      ),
    );
  }

  Future<void> _loadPrefs() async {
    final selections = await SplitTunnelPrefs.loadSelections();
    if (!mounted) return;
    setState(() {
      _splitTunnelMode = selections.mode;
      _selectedPackages = selections.packages;
      _domainMode = selections.domainMode;
      _domainList
        ..clear()
        ..addAll(selections.domains);
      _isLoadingPrefs = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _ensureInstalledAppsLoaded();
      }
    });
  }

  Future<void> _ensureInstalledAppsLoaded() async {
    if (_hasRequestedApps || _isLoadingApps) {
      await _appsLoadCompleter?.future;
      return;
    }
    _hasRequestedApps = true;
    _appsLoadCompleter = Completer<void>();
    await _loadInstalledApps();
  }

  Future<void> _savePrefs() async {
    await SplitTunnelPrefs.saveMode(_splitTunnelMode);
    await SplitTunnelPrefs.savePackages(_selectedPackages);
    await SplitTunnelPrefs.saveDomainMode(_domainMode);
    await SplitTunnelPrefs.saveDomains(List<String>.from(_domainList));

    if (!mounted || !widget.isVpnConnected()) {
      return;
    }

    _showReconnectBannerTemporarily();
  }

  Future<void> _loadInstalledApps() async {
    setState(() => _isLoadingApps = true);
    try {
      final rawApps = await _wireGuardChannel.invokeMethod<List<dynamic>>(
        'getInstalledApps',
      );
      if (!mounted) return;
      final apps = (rawApps ?? const <dynamic>[])
          .whereType<Map<dynamic, dynamic>>()
          .map(InstalledApp.fromMap)
          .where((app) => app.packageName.isNotEmpty)
          .toList();
      setState(() => _installedApps = apps);
    } on PlatformException catch (e) {
      _hasRequestedApps = false;
      final l10n = AppLocalizations.of(context);
      _showMessage(
        '${l10n.failedGetApps}: ${l10n.translateRuntimeMessage(e.message ?? e.code)}',
        isError: true,
      );
    } catch (e) {
      _hasRequestedApps = false;
      _showMessage(
        '${AppLocalizations.of(context).errorLoadingApps}: $e',
        isError: true,
      );
    } finally {
      final completer = _appsLoadCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
      _appsLoadCompleter = null;
      if (mounted) setState(() => _isLoadingApps = false);
    }
  }

  void _showMessage(String text, {bool isError = false, IconData? icon}) {
    if (!mounted) {
      return;
    }

    _floatingNoticeTimer?.cancel();
    setState(() {
      _floatingNoticeText = text;
      _floatingNoticeIsError = isError;
      _floatingNoticeIcon = icon;
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
      _floatingNoticeIcon = null;
      return;
    }

    setState(() {
      _floatingNoticeText = null;
      _floatingNoticeIsError = false;
      _floatingNoticeIcon = null;
    });
  }

  Widget _buildAppBarNoticeOverlay() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isVisible = _floatingNoticeText != null;
    final backgroundColor = isDark ? Colors.white : Colors.black;
    final foregroundColor = isDark ? Colors.black : Colors.white;
    return IgnorePointer(
      ignoring: !isVisible,
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          reverseDuration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curvedAnimation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -1),
                  end: Offset.zero,
                ).animate(curvedAnimation),
                child: child,
              ),
            );
          },
          child: !isVisible
              ? const SizedBox.shrink(key: ValueKey<String>('hidden-settings-notice-overlay'))
              : SizedBox.expand(
                  key: ValueKey<String>(
                    'visible-settings-notice-overlay-${_floatingNoticeText!}-$_floatingNoticeIsError-$_floatingNoticeIcon',
                  ),
                  child: Dismissible(
                    key: ValueKey<String>(
                      'dismissible-settings-notice-${_floatingNoticeText!}-$_floatingNoticeIsError-$_floatingNoticeIcon',
                    ),
                    direction: DismissDirection.up,
                    resizeDuration: null,
                    movementDuration: const Duration(milliseconds: 220),
                    onDismissed: (_) => _clearFloatingNotice(),
                    child: Material(
                      color: backgroundColor,
                      child: SafeArea(
                        bottom: false,
                        child: SizedBox(
                          height: kToolbarHeight,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    child: Text(
                                      _floatingNoticeText ?? '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: foregroundColor,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
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

  void _hideReconnectBanner() {
    _reconnectBannerTimer?.cancel();
    _reconnectBannerTimer = null;

    if (!_showReconnectBanner) {
      return;
    }

    setState(() {
      _showReconnectBanner = false;
    });
  }

  void _showReconnectBannerTemporarily() {
    if (!mounted) {
      return;
    }

    _showMessage(
      AppLocalizations.of(context).reconnectToApplyChangedSettings,
      icon: Icons.sync_problem_rounded,
    );
  }

  String _localizedSplitTunnelModeLabel(
    AppLocalizations l10n,
    SplitTunnelMode mode,
  ) {
    switch (mode) {
      case SplitTunnelMode.all:
        return l10n.allSystemViaVpn;
      case SplitTunnelMode.include:
        return l10n.onlySelectedApps;
      case SplitTunnelMode.exclude:
        return l10n.allExceptSelected;
    }
  }

  String _localizedSplitTunnelDomainModeLabel(
    AppLocalizations l10n,
    SplitTunnelDomainMode mode,
  ) {
    switch (mode) {
      case SplitTunnelDomainMode.all:
        return l10n.allSitesViaVpn;
      case SplitTunnelDomainMode.include:
        return l10n.onlySpecifiedDomains;
      case SplitTunnelDomainMode.exclude:
        return l10n.allSitesExceptSpecified;
    }
  }

  String _localizedSplitTunnelModeDescription(
    AppLocalizations l10n,
    SplitTunnelMode mode,
  ) {
    switch (mode) {
      case SplitTunnelMode.all:
        return l10n.allSystemDescription;
      case SplitTunnelMode.include:
        return l10n.onlySelectedDescription;
      case SplitTunnelMode.exclude:
        return l10n.allExceptDescription;
    }
  }

  String _localizedSplitTunnelDomainModeDescription(
    AppLocalizations l10n,
    SplitTunnelDomainMode mode,
  ) {
    switch (mode) {
      case SplitTunnelDomainMode.all:
        return l10n.allSitesDescription;
      case SplitTunnelDomainMode.include:
        return l10n.onlyDomainsDescription;
      case SplitTunnelDomainMode.exclude:
        return l10n.exceptDomainsDescription;
    }
  }

  String _themePreferenceLabel(
    AppLocalizations l10n,
    AppThemePreference preference,
  ) {
    switch (preference) {
      case AppThemePreference.light:
        return l10n.lightTheme;
      case AppThemePreference.dark:
        return l10n.darkTheme;
    }
  }

  String _languageLabel(AppLocalizations l10n, AppLanguage language) {
    switch (language) {
      case AppLanguage.en:
        return l10n.english;
      case AppLanguage.ru:
        return l10n.russian;
    }
  }

  String _splitTunnelModeSummary(AppLocalizations l10n) {
    final label = _localizedSplitTunnelModeLabel(l10n, _splitTunnelMode);
    if (_splitTunnelMode == SplitTunnelMode.all) {
      return label;
    }
    return '$label (${_selectedPackages.length})';
  }

  String _domainModeSummary(AppLocalizations l10n) {
    final label = _localizedSplitTunnelDomainModeLabel(l10n, _domainMode);
    if (_domainMode == SplitTunnelDomainMode.all) {
      return label;
    }
    return '$label (${_domainList.length})';
  }

  Future<T?> _showSelectionSheet<T>({
    required String title,
    required T selected,
    required List<T> values,
    required String Function(T value) titleBuilder,
    String Function(T value)? subtitleBuilder,
    IconData Function(T value)? iconBuilder,
    bool useSwitchIndicator = false,
    bool invertSelectionColors = false,
    Color? selectedOptionBackgroundColor,
    Color Function(T value)? optionBackgroundColorBuilder,
    double optionScale = 1.0,
    Duration? delayedCloseDuration,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        var currentSelection = selected;
        var closeRequestId = 0;

        return StatefulBuilder(
          builder: (context, modalSetState) {
            void handleSelection(T value) {
              if (value == currentSelection) {
                return;
              }

              if (delayedCloseDuration == null) {
                Navigator.of(sheetContext).pop(value);
                return;
              }

              final requestId = ++closeRequestId;
              modalSetState(() {
                currentSelection = value;
              });

              Future<void>.delayed(delayedCloseDuration).then((_) {
                if (!sheetContext.mounted || requestId != closeRequestId) {
                  return;
                }
                Navigator.of(sheetContext).pop(currentSelection);
              });
            }

            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (var index = 0; index < values.length; index++) ...[
                        _buildSheetOption<T>(
                          value: values[index],
                          selected: currentSelection,
                          title: titleBuilder(values[index]),
                          subtitle: subtitleBuilder?.call(values[index]),
                          icon: iconBuilder?.call(values[index]),
                          useSwitchIndicator: useSwitchIndicator,
                          invertSelectionColors: invertSelectionColors,
                          selectedOptionBackgroundColor:
                              selectedOptionBackgroundColor,
                          optionBackgroundColor: optionBackgroundColorBuilder?.call(
                            values[index],
                          ),
                          sizeScale: optionScale,
                          onTap: () => handleSelection(values[index]),
                        ),
                        if (index != values.length - 1) const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showLanguageSheet() async {
    final l10n = AppLocalizations.of(context);
    final languageService = context.read<LanguageService>();
    final selection = await _showSelectionSheet<AppLanguage>(
      title: l10n.languageLabel,
      selected: languageService.language,
      values: AppLanguage.values,
      titleBuilder: (language) => _languageLabel(l10n, language),
      iconBuilder: (language) => language == AppLanguage.ru
          ? Icons.language_rounded
          : Icons.translate_rounded,
      optionScale: 0.94,
    );

    if (!mounted || selection == null) {
      return;
    }

    await languageService.setLanguage(selection);
  }

  Future<void> _showThemeSheet() async {
    final l10n = AppLocalizations.of(context);
    final themeService = context.read<ThemeService>();
    final selection = await _showSelectionSheet<AppThemePreference>(
      title: l10n.theme,
      selected: themeService.preference,
      values: AppThemePreference.values,
      titleBuilder: (preference) => _themePreferenceLabel(l10n, preference),
      iconBuilder: (preference) => preference.icon,
      optionBackgroundColorBuilder: (preference) {
        switch (preference) {
          case AppThemePreference.light:
            return Colors.white;
          case AppThemePreference.dark:
            return _darkThemeOptionColor;
        }
      },
    );

    if (!mounted || selection == null) {
      return;
    }

    await themeService.setPreference(selection);
  }

  Future<void> _showSplitTunnelModeSheet() async {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selection = await _showSelectionSheet<SplitTunnelMode>(
      title: l10n.tunnelMode,
      selected: _splitTunnelMode,
      values: SplitTunnelMode.values,
      titleBuilder: (mode) => _localizedSplitTunnelModeLabel(l10n, mode),
      subtitleBuilder: (mode) =>
          _localizedSplitTunnelModeDescription(l10n, mode),
      useSwitchIndicator: true,
      selectedOptionBackgroundColor: isDark ? Colors.white : null,
    );

    if (!mounted || selection == null || selection == _splitTunnelMode) {
      return;
    }

    setState(() {
      _splitTunnelMode = selection;
      if (selection == SplitTunnelMode.all) {
        _selectedPackages = <String>{};
        _appSearchQuery = '';
        _appSearchController.clear();
      }
    });

    if (selection != SplitTunnelMode.all) {
      _ensureInstalledAppsLoaded();
    }

    await _savePrefs();
  }

  Future<void> _showDomainModeSheet() async {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selection = await _showSelectionSheet<SplitTunnelDomainMode>(
      title: l10n.domainMode,
      selected: _domainMode,
      values: SplitTunnelDomainMode.values,
      titleBuilder: (mode) => _localizedSplitTunnelDomainModeLabel(l10n, mode),
      subtitleBuilder: (mode) =>
          _localizedSplitTunnelDomainModeDescription(l10n, mode),
      useSwitchIndicator: true,
      selectedOptionBackgroundColor: isDark ? Colors.white : null,
    );

    if (!mounted || selection == null || selection == _domainMode) {
      return;
    }

    setState(() {
      _domainMode = selection;
      if (selection == SplitTunnelDomainMode.all) {
        _domainInputController.clear();
      }
    });

    await _savePrefs();
  }

  Widget _buildSheetOption<T>({
    required T value,
    required T selected,
    required String title,
    String? subtitle,
    IconData? icon,
    bool useSwitchIndicator = false,
    bool invertSelectionColors = false,
    Color? selectedOptionBackgroundColor,
    Color? optionBackgroundColor,
    bool? forceLightSwitchOutline,
    double sizeScale = 1.0,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSelected = value == selected;
    final borderRadius = _settingsBlockRadius;
    final resolvedOptionBackgroundColor = optionBackgroundColor ??
        (isSelected ? selectedOptionBackgroundColor : null);
    final hasCustomSurfaceColor = resolvedOptionBackgroundColor != null;
    final backgroundColor = resolvedOptionBackgroundColor ??
      (invertSelectionColors
          ? (isSelected ? Colors.white : Colors.black)
          : (isSelected
              ? Colors.black
              : (isDark ? const Color(0xFF141414) : Colors.white)));
    final isLightSurface =
      ThemeData.estimateBrightnessForColor(backgroundColor) ==
      Brightness.light;
    final showLightSurfaceShadow =
      hasCustomSurfaceColor && isLightSurface && !isDark;
    final matchesDarkSectionBorder =
      hasCustomSurfaceColor && !isLightSurface && isDark;
    final sectionBorderColor = theme.dividerColor.withValues(
      alpha: isDark ? 0.14 : 0.08,
    );
    final foregroundColor = isLightSurface
      ? Colors.black
      : Colors.white;
    final borderColor = matchesDarkSectionBorder
      ? sectionBorderColor
      : hasCustomSurfaceColor
          ? (isSelected
              ? foregroundColor
              : foregroundColor.withValues(alpha: isLightSurface ? 0.20 : 0.14))
      : (invertSelectionColors
          ? Colors.black
          : (isSelected
              ? Colors.black
              : theme.dividerColor.withValues(alpha: isDark ? 0.28 : 0.14)));
    final titleColor = hasCustomSurfaceColor || invertSelectionColors
      ? foregroundColor
      : (isSelected ? Colors.white : theme.colorScheme.onSurface);
    final subtitleColor = hasCustomSurfaceColor || invertSelectionColors
      ? foregroundColor.withValues(alpha: isLightSurface ? 0.68 : 0.76)
      : (isSelected
          ? Colors.white.withValues(alpha: 0.76)
          : theme.colorScheme.onSurface.withValues(alpha: 0.62));
    final iconBadgeBackgroundColor = hasCustomSurfaceColor || invertSelectionColors
      ? (isLightSurface
          ? Colors.black
          : Colors.white.withValues(alpha: 0.14))
      : null;
    final iconBadgeColor = hasCustomSurfaceColor || invertSelectionColors
      ? Colors.white
      : null;
    final indicatorActiveColor = hasCustomSurfaceColor || invertSelectionColors
      ? (isLightSurface ? Colors.black : Colors.white)
      : null;
    final indicatorBorderColor = hasCustomSurfaceColor || invertSelectionColors
      ? foregroundColor.withValues(alpha: 0.36)
      : null;
    final indicatorCheckColor = hasCustomSurfaceColor || invertSelectionColors
      ? (isLightSurface ? Colors.white : Colors.black)
      : null;
    final boxShadow = showLightSurfaceShadow
      ? const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.20),
            blurRadius: 8,
            spreadRadius: 0,
            offset: Offset(0, 2),
          ),
        ]
      : null;
    final titleStyle =
        (theme.textTheme.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(
          color: titleColor,
          fontWeight: FontWeight.w700,
          fontSize: (theme.textTheme.titleMedium?.fontSize ?? 16) * sizeScale,
        );
    final subtitleStyle =
        (theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14)).copyWith(
          color: subtitleColor,
          fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) * sizeScale,
        );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.all(16 * sizeScale),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(borderRadius),
            border: showLightSurfaceShadow ? null : Border.all(color: borderColor),
            boxShadow: boxShadow,
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                _buildIconBadge(
                  icon: icon,
                  accent: isSelected && !invertSelectionColors && !hasCustomSurfaceColor,
                  backgroundColor: iconBadgeBackgroundColor,
                  iconColor: iconBadgeColor,
                  sizeScale: sizeScale,
                ),
                SizedBox(width: 14 * sizeScale),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: titleStyle),
                    if (subtitle != null) ...[
                      SizedBox(height: 2 * sizeScale),
                      Text(subtitle, style: subtitleStyle),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 12 * sizeScale),
              useSwitchIndicator
                  ? _buildSelectionSwitch(
                      selected: isSelected,
                      accent: isSelected,
                      forceLightOutline:
                          forceLightSwitchOutline ??
                          (hasCustomSurfaceColor && isSelected && isLightSurface),
                      onChanged: (enabled) {
                        if (enabled) {
                          onTap();
                        }
                      },
                    )
                  : _buildSelectionIndicator(
                      selected: isSelected,
                      accent: isSelected && !invertSelectionColors && !hasCustomSurfaceColor,
                      activeColor: indicatorActiveColor,
                      inactiveBorderColor: indicatorBorderColor,
                      checkColor: indicatorCheckColor,
                      sizeScale: sizeScale,
                    ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildIconBadge({
    required IconData icon,
    bool accent = false,
    Color? backgroundColor,
    Color? iconColor,
    double sizeScale = 1.0,
  }) {
    final resolvedBackgroundColor =
        backgroundColor ??
        (accent ? Colors.white.withValues(alpha: 0.12) : Colors.black);
    final resolvedIconColor = iconColor ?? Colors.white;

    return Container(
      width: 44 * sizeScale,
      height: 44 * sizeScale,
      decoration: BoxDecoration(
        color: resolvedBackgroundColor,
        borderRadius: BorderRadius.circular(_settingsBlockRadius),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: resolvedIconColor, size: 22 * sizeScale),
    );
  }
  Widget _buildSelectionIndicator({
    required bool selected,
    bool accent = false,
    Color? activeColor,
    Color? inactiveBorderColor,
    Color? checkColor,
    double sizeScale = 1.0,
  }) {
    final resolvedActiveColor = activeColor ?? (accent ? Colors.white : Colors.black);
    final borderColor = inactiveBorderColor ??
        (accent
            ? Colors.white.withValues(alpha: selected ? 1 : 0.36)
            : Theme.of(context).dividerColor.withValues(alpha: 0.24));
    final backgroundColor = !selected
        ? Colors.transparent
        : resolvedActiveColor;
    final resolvedCheckColor = checkColor ?? (accent ? Colors.black : Colors.white);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 30 * sizeScale,
      height: 30 * sizeScale,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor,
        border: Border.all(
          color: selected ? resolvedActiveColor : borderColor,
          width: 2 * sizeScale,
        ),
      ),
      child: selected
          ? Icon(
              Icons.check_rounded,
              size: 18 * sizeScale,
              color: resolvedCheckColor,
            )
          : null,
    );
  }
  Widget _buildSelectionSwitch({
    required bool selected,
    bool accent = false,
    bool forceLightOutline = false,
    required ValueChanged<bool> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final outlineColor = forceLightOutline
        ? Colors.black
        : null;
    final outlineWidth = forceLightOutline
        ? 1.5
        : null;

    return Switch(
      value: selected,
      onChanged: (enabled) {
        if (enabled != selected) {
          onChanged(enabled);
        }
      },
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      activeThumbColor: accent ? Colors.black : Colors.white,
      activeTrackColor: accent ? Colors.white : Colors.black,
      inactiveThumbColor: Colors.white,
      inactiveTrackColor: isDark
          ? Colors.white.withValues(alpha: 0.22)
          : Colors.black.withValues(alpha: 0.18),
        trackOutlineColor: outlineColor == null
          ? null
          : WidgetStatePropertyAll<Color>(outlineColor),
        trackOutlineWidth: outlineWidth == null
          ? null
          : WidgetStatePropertyAll<double>(outlineWidth),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool accent = false,
    bool showChevron = true,
    Color? iconBadgeBackgroundColor,
    Color? iconBadgeColor,
  }) {
    final theme = Theme.of(context);
    final titleColor = accent ? Colors.white : theme.colorScheme.onSurface;
    final subtitleColor = accent
        ? Colors.white.withValues(alpha: 0.78)
        : theme.colorScheme.onSurface.withValues(alpha: 0.58);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_settingsBlockRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              _buildIconBadge(
                icon: icon,
                accent: accent,
                backgroundColor: iconBadgeBackgroundColor,
                iconColor: iconBadgeColor,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: titleColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: subtitleColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showChevron) ...[
                const SizedBox(width: 12),
                Icon(
                  Icons.chevron_right_rounded,
                  color: accent ? Colors.white : theme.colorScheme.onSurface,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        children: [
          Icon(
            icon,
            size: 40,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.64),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAppTile(InstalledApp app, {VoidCallback? onToggle}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selected = _selectedPackages.contains(app.packageName);
    final handleToggle =
        onToggle ?? () => _togglePackageSelection(app.packageName);
    final tileColor = isDark ? const Color(0xFF141414) : Colors.white;
    final borderRadius = BorderRadius.circular(_settingsBlockRadius);
    final borderColor = theme.dividerColor.withValues(alpha: 0.14);

    return Container(
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: borderRadius,
        border: isDark ? Border.all(color: borderColor) : null,
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
        color: Colors.transparent,
        borderRadius: borderRadius,
        child: InkWell(
          onTap: handleToggle,
          borderRadius: borderRadius,
          child: Container(
          constraints: const BoxConstraints(minHeight: _inputRowHeight),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      app.packageName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.62,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _buildSelectionSwitch(
                selected: selected,
                accent: selected,
                forceLightOutline: true,
                onChanged: (enabled) {
                  if (enabled != selected) {
                    handleToggle();
                  }
                },
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildDomainTile(String domain) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tileColor = isDark ? const Color(0xFF141414) : Colors.white;
    final borderRadius = BorderRadius.circular(_settingsBlockRadius);

    return Container(
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: borderRadius,
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
        color: Colors.transparent,
        borderRadius: borderRadius,
        child: Container(
          constraints: const BoxConstraints(minHeight: _inputRowHeight),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(_settingsBlockRadius),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.language_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  domain,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _togglePackageSelection(String packageName) {
    setState(() {
      if (_selectedPackages.contains(packageName)) {
        _selectedPackages.remove(packageName);
      } else {
        _selectedPackages.add(packageName);
      }
    });
    unawaited(_savePrefs());
  }

  Future<void> _showAppsPickerSheet() async {
    final l10n = AppLocalizations.of(context);
    await _ensureInstalledAppsLoaded();
    if (!mounted) {
      return;
    }

    if (_appSearchController.text != _appSearchQuery) {
      _appSearchController.value = TextEditingValue(
        text: _appSearchQuery,
        selection: TextSelection.collapsed(offset: _appSearchQuery.length),
      );
    }

    const reorderDelay = Duration(milliseconds: 220);
    final orderedSelectedPackages = Set<String>.from(_selectedPackages);
    final reorderTimers = <String, Timer>{};
    var sheetIsActive = true;

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) {
          final theme = Theme.of(sheetContext);
          final isDark = theme.brightness == Brightness.dark;
          final fieldBackgroundColor = isDark ? Colors.white : Colors.black;
          final fieldForegroundColor = isDark ? Colors.black : Colors.white;
          final fieldHintColor = fieldForegroundColor.withValues(alpha: 0.62);
          final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;

          return StatefulBuilder(
            builder: (context, modalSetState) {
              void handleAppToggle(String packageName) {
                final shouldBeSelected = !_selectedPackages.contains(packageName);
                _togglePackageSelection(packageName);
                modalSetState(() {});

                reorderTimers.remove(packageName)?.cancel();
                reorderTimers[packageName] = Timer(reorderDelay, () {
                  reorderTimers.remove(packageName);
                  if (shouldBeSelected) {
                    orderedSelectedPackages.add(packageName);
                  } else {
                    orderedSelectedPackages.remove(packageName);
                  }
                  if (sheetIsActive) {
                    modalSetState(() {});
                  }
                });
              }

              final query = _appSearchController.text.trim().toLowerCase();
              final filteredApps = _installedApps.where((app) {
                final label = app.label.toLowerCase();
                final packageName = app.packageName.toLowerCase();
                return query.isEmpty ||
                    label.contains(query) ||
                    packageName.contains(query);
              }).toList();
              final orderedApps = [
                ...filteredApps.where(
                  (app) => orderedSelectedPackages.contains(app.packageName),
                ),
                ...filteredApps.where(
                  (app) => !orderedSelectedPackages.contains(app.packageName),
                ),
              ];

              return SafeArea(
                child: FractionallySizedBox(
                  heightFactor: 0.82,
                  child: Padding(
                    padding: EdgeInsets.only(top: 8, bottom: bottomInset + 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                l10n.selectApps,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _appSearchController,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: fieldForegroundColor,
                                  fontWeight: FontWeight.w600,
                                ),
                                cursorColor: fieldForegroundColor,
                                onChanged: (value) {
                                  _appSearchQuery = value;
                                  modalSetState(() {});
                                },
                                decoration: InputDecoration(
                                  hintText: l10n.searchApps,
                                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                                    color: fieldHintColor,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.search_rounded,
                                    color: fieldForegroundColor,
                                  ),
                                  filled: true,
                                  fillColor: fieldBackgroundColor,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(_settingsBlockRadius),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(_settingsBlockRadius),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(_settingsBlockRadius),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 0),
                        Expanded(
                          child: orderedApps.isEmpty
                              ? Center(
                                  child: _buildEmptyState(
                                    icon: Icons.apps_rounded,
                                    title: l10n.appsNotFound,
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                                  itemCount: orderedApps.length,
                                  separatorBuilder: (context, index) =>
                                      const SizedBox(height: _pickerListSpacing),
                                  itemBuilder: (context, index) {
                                    final app = orderedApps[index];
                                    return _buildAppTile(
                                      app,
                                      onToggle: () => handleAppToggle(app.packageName),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      sheetIsActive = false;
      for (final timer in reorderTimers.values) {
        timer.cancel();
      }
      reorderTimers.clear();
    }
  }

  Future<void> _showDomainsPickerSheet() async {
    final l10n = AppLocalizations.of(context);
    final title = _domainMode == SplitTunnelDomainMode.exclude
        ? l10n.excludedSites
        : l10n.addedSites;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final isDark = theme.brightness == Brightness.dark;
        final fieldBackgroundColor = isDark ? Colors.white : Colors.black;
        final fieldForegroundColor = isDark ? Colors.black : Colors.white;
        final fieldHintColor = fieldForegroundColor.withValues(alpha: 0.62);
        final addButtonBackgroundColor = isDark ? Colors.white : Colors.black;
        final addButtonForegroundColor = isDark ? Colors.black : Colors.white;
        final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;

        return StatefulBuilder(
          builder: (context, modalSetState) {
            void addDomains() {
              final raw = _domainInputController.text.trim();
              if (raw.isEmpty) {
                return;
              }

              final domains = raw
                  .split(RegExp(r'[,;\s]+'))
                  .map((domain) => domain.trim().toLowerCase())
                  .where(
                    (domain) => domain.isNotEmpty && domain.contains('.'),
                  )
                  .toList();
              if (domains.isEmpty) {
                _showMessage(l10n.enterCorrectDomain, isError: true);
                return;
              }

              setState(() {
                for (final domain in domains) {
                  if (!_domainList.contains(domain)) {
                    _domainList.add(domain);
                  }
                }
                _domainInputController.clear();
              });
              modalSetState(() {});
              unawaited(_savePrefs());
            }

            void removeDomain(String domain) {
              setState(() {
                _domainList.remove(domain);
              });
              modalSetState(() {});
              unawaited(_savePrefs());
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(top: 8, bottom: bottomInset + 20),
                child: SizedBox(
                  height: MediaQuery.sizeOf(sheetContext).height * 0.78,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              title,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: _inputRowHeight - 2,
                                    child: TextField(
                                      controller: _domainInputController,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: fieldForegroundColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      cursorColor: fieldForegroundColor,
                                      textInputAction: TextInputAction.done,
                                      onSubmitted: (_) => addDomains(),
                                      decoration: InputDecoration(
                                        hintText: l10n.addDomainHint,
                                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                                          color: fieldHintColor,
                                        ),
                                        prefixIcon: Icon(
                                          Icons.language_rounded,
                                          color: fieldForegroundColor,
                                        ),
                                        filled: true,
                                        fillColor: fieldBackgroundColor,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(_settingsBlockRadius),
                                          borderSide: BorderSide.none,
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(_settingsBlockRadius),
                                          borderSide: BorderSide.none,
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(_settingsBlockRadius),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Transform.translate(
                                  offset: const Offset(0, -1),
                                  child: SizedBox(
                                    width: _inputRowHeight - 2,
                                    height: _inputRowHeight - 2,
                                    child: Material(
                                      color: addButtonBackgroundColor,
                                      borderRadius: BorderRadius.circular(
                                        _settingsBlockRadius,
                                      ),
                                      child: InkWell(
                                        onTap: addDomains,
                                        borderRadius: BorderRadius.circular(
                                          _settingsBlockRadius,
                                        ),
                                        child: Center(
                                          child: Icon(
                                            Icons.add_rounded,
                                            color: addButtonForegroundColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 0),
                      Expanded(
                        child: _domainList.isEmpty
                            ? Center(
                                child: _buildEmptyState(
                                  icon: Icons.language_rounded,
                                  title: l10n.domainsNotAdded,
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                                itemCount: _domainList.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: _pickerListSpacing),
                                itemBuilder: (context, index) {
                                  final domain = _domainList[index];
                                  return Dismissible(
                                    key: ValueKey(domain),
                                    direction: DismissDirection.endToStart,
                                    onDismissed: (_) => removeDomain(domain),
                                    background: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.transparent,
                                        borderRadius: BorderRadius.circular(
                                          _settingsBlockRadius,
                                        ),
                                      ),
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                      ),
                                      child: Text(
                                        l10n.deleteAction,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              color: const Color(0xFFB45050),
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                    child: _buildDomainTile(domain),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildReconnectBanner(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) {
        if ((details.primaryDelta ?? 0) < -8) {
          _hideReconnectBanner();
        }
      },
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) < -250) {
          _hideReconnectBanner();
        }
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(_settingsBlockRadius),
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
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.onPrimary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(_settingsBlockRadius),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.sync_problem_rounded,
                color: theme.colorScheme.onPrimary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                l10n.reconnectToApplyChangedSettings,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              onPressed: _hideReconnectBanner,
              icon: Icon(
                Icons.close_rounded,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required List<Widget> children,
    Color? color,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor =
        color ?? (isDark ? const Color(0xFF141414) : Colors.white);

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(_settingsBlockRadius),
        border: Border.all(
          color: color != null
              ? Colors.transparent
              : theme.dividerColor.withValues(alpha: isDark ? 0.14 : 0.08),
        ),
        boxShadow: isDark || color != null
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _buildSectionDivider({bool accent = false, double indent = 8}) {
    return Divider(
      height: 1,
      indent: indent,
      endIndent: 8,
      color: accent
          ? Colors.white.withValues(alpha: 0.14)
          : Theme.of(context).dividerColor.withValues(alpha: 0.12),
    );
  }

  Widget _buildPickerLauncherCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);

    return _buildSectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              _buildIconBadge(icon: icon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.62,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_settingsBlockRadius),
                ),
              ),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(buttonLabel),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppsSection() {
    final l10n = AppLocalizations.of(context);
    return _buildPickerLauncherCard(
      icon: Icons.apps_rounded,
      title: l10n.selectApps,
      buttonLabel: l10n.selectApps,
      onPressed: _showAppsPickerSheet,
    );
  }

  Widget _buildDomainsSection() {
    final l10n = AppLocalizations.of(context);
    final title = _domainMode == SplitTunnelDomainMode.exclude
        ? l10n.excludedSites
        : l10n.addedSites;

    return _buildPickerLauncherCard(
      icon: Icons.language_rounded,
      title: title,
      buttonLabel: l10n.selectSites,
      onPressed: _showDomainsPickerSheet,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final languageService = Provider.of<LanguageService>(context);
    final themeService = Provider.of<ThemeService>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final showAppsSection = _splitTunnelMode != SplitTunnelMode.all;
    final showDomainsSection = _domainMode != SplitTunnelDomainMode.all;
    final showReconnectBanner = _showReconnectBanner && widget.isVpnConnected();
    final notificationsActionTooltip = defaultTargetPlatform != TargetPlatform.android
      ? '${l10n.notificationsLabel}: ${l10n.notificationsPermissionUnavailable}'
      : _notificationsEnabled == true
      ? '${l10n.notificationsLabel}: ${l10n.notificationsPermissionAllowed}'
      : _notificationsEnabled == false
      ? '${l10n.notificationsLabel}: ${l10n.notificationsPermissionDenied}'
      : '${l10n.notificationsLabel}: ${l10n.notificationsPermissionChecking}';
    final notificationsActionIcon = _notificationsEnabled == false
      ? Icons.notifications_off_outlined
      : _notificationsEnabled == true
      ? Icons.notifications_active_outlined
      : Icons.notifications_none_outlined;
    final notificationsActionColor = _notificationsEnabled == false
      ? theme.colorScheme.error
      : null;
    final showAppBarNotice = _floatingNoticeText != null;

    if (_isLoadingPrefs) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !showAppBarNotice,
          title: showAppBarNotice ? null : Text(l10n.settingsTitle),
          actions: showAppBarNotice
              ? const []
              : [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Tooltip(
                      message: notificationsActionTooltip,
                      child: IconButton(
                        onPressed: _isUpdatingNotificationsPermission
                            ? null
                            : _handleNotificationsPermissionAction,
                        icon: _isUpdatingNotificationsPermission
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                notificationsActionIcon,
                                color: notificationsActionColor,
                              ),
                      ),
                    ),
                  ),
                ],
          flexibleSpace: _buildAppBarNoticeOverlay(),
        ),
        body: SafeArea(
          top: false,
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: showReconnectBanner
                        ? Padding(
                            key: const ValueKey('reconnect-banner-visible'),
                            padding: const EdgeInsets.only(bottom: 24),
                            child: _buildReconnectBanner(l10n),
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('reconnect-banner-hidden'),
                          ),
                  ),
                  _buildSectionTitle(l10n.generalSection),
                  const SizedBox(height: 12),
                  _buildSectionCard(
                    children: [
                      _buildSettingsTile(
                        icon: Icons.language_rounded,
                        title: l10n.languageLabel,
                        subtitle: _languageLabel(
                          l10n,
                          languageService.language,
                        ),
                        onTap: _showLanguageSheet,
                      ),
                      _buildSectionDivider(),
                      _buildSettingsTile(
                        icon: themeService.preference.icon,
                        title: l10n.theme,
                        subtitle: _themePreferenceLabel(
                          l10n,
                          themeService.preference,
                        ),
                        onTap: _showThemeSheet,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSectionTitle('VPN'),
                  const SizedBox(height: 12),
                  _buildSectionCard(
                    color: isDark ? null : Colors.black,
                    children: [
                      _buildSettingsTile(
                        icon: Icons.filter_alt_outlined,
                        title: l10n.tunnelMode,
                        subtitle: _splitTunnelModeSummary(l10n),
                        onTap: _showSplitTunnelModeSheet,
                        accent: true,
                        iconBadgeBackgroundColor: isDark
                            ? Colors.black
                            : Colors.white,
                        iconBadgeColor: isDark ? Colors.white : Colors.black,
                      ),
                      _buildSectionDivider(accent: true),
                      _buildSettingsTile(
                        icon: Icons.language_rounded,
                        title: l10n.domainMode,
                        subtitle: _domainModeSummary(l10n),
                        onTap: _showDomainModeSheet,
                        accent: true,
                        iconBadgeBackgroundColor: isDark
                            ? Colors.black
                            : Colors.white,
                        iconBadgeColor: isDark ? Colors.white : Colors.black,
                      ),
                    ],
                  ),
                  if (showAppsSection) ...[
                    const SizedBox(height: 16),
                    _buildSectionTitle(l10n.apps),
                    const SizedBox(height: 12),
                    _buildAppsSection(),
                  ],
                  if (showDomainsSection) ...[
                    const SizedBox(height: 16),
                    _buildSectionTitle(l10n.sites),
                    const SizedBox(height: 12),
                    _buildDomainsSection(),
                  ],
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    children: [
                      _buildSettingsTile(
                        icon: Icons.article_outlined,
                        title: l10n.licensesLabel,
                        subtitle: l10n.aboutTitle,
                        onTap: _showAboutDialog,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      _appVersion,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.5),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LicensePackageGroup {
  const _LicensePackageGroup({
    required this.packageName,
    required this.entries,
  });

  final String packageName;
  final List<LicenseEntry> entries;
}

class _FullLicensesPage extends StatefulWidget {
  const _FullLicensesPage();

  @override
  State<_FullLicensesPage> createState() => _FullLicensesPageState();
}

class _FullLicensesPageState extends State<_FullLicensesPage> {
  late final Future<List<_LicensePackageGroup>> _licenseGroupsFuture =
      _loadLicenseGroups();

  Future<List<_LicensePackageGroup>> _loadLicenseGroups() async {
    final groupedEntries = <String, List<LicenseEntry>>{};

    await for (final entry in LicenseRegistry.licenses) {
      for (final packageName in entry.packages) {
        groupedEntries
            .putIfAbsent(packageName, () => <LicenseEntry>[])
            .add(entry);
      }
    }

    final groups =
        groupedEntries.entries
            .map(
              (entry) => _LicensePackageGroup(
                packageName: entry.key,
                entries: List<LicenseEntry>.unmodifiable(entry.value),
              ),
            )
            .toList(growable: false)
          ..sort(
            (left, right) => left.packageName.toLowerCase().compareTo(
              right.packageName.toLowerCase(),
            ),
          );

    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final materialL10n = MaterialLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(),
      body: FutureBuilder<List<_LicensePackageGroup>>(
        future: _licenseGroupsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  snapshot.error.toString(),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final licenseGroups = snapshot.data ?? const <_LicensePackageGroup>[];
          if (licenseGroups.isEmpty) {
            return const SizedBox.shrink();
          }

          return ListView.separated(
            itemCount: licenseGroups.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final group = licenseGroups[index];
              return ListTile(
                title: Text(group.packageName),
                subtitle: Text(
                  materialL10n.licensesPackageDetailText(group.entries.length),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => _PackageLicensesPage(group: group),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _PackageLicensesPage extends StatelessWidget {
  const _PackageLicensesPage({required this.group});

  final _LicensePackageGroup group;

  @override
  Widget build(BuildContext context) {
    final licenseWidgets = <Widget>[];

    for (
      var entryIndex = 0;
      entryIndex < group.entries.length;
      entryIndex += 1
    ) {
      final entry = group.entries[entryIndex];
      final paragraphs = entry.paragraphs.toList(growable: false);

      if (entryIndex > 0) {
        licenseWidgets.add(
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Divider(),
          ),
        );
      }

      for (final paragraph in paragraphs) {
        if (paragraph.indent == LicenseParagraph.centeredIndent) {
          licenseWidgets.add(
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                paragraph.text,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          );
          continue;
        }

        licenseWidgets.add(
          Padding(
            padding: EdgeInsetsDirectional.only(
              top: 8,
              start: 16.0 * paragraph.indent,
            ),
            child: Text(paragraph.text),
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(group.packageName)),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: licenseWidgets,
        ),
      ),
    );
  }
}
