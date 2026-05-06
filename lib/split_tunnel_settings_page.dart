import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'l10n/app_localizations.dart';
import 'l10n/language_service.dart';
import 'main.dart';
import 'split_tunnel_prefs.dart';
import 'theme_mode_button.dart';

class SplitTunnelSettingsPage extends StatefulWidget {
  const SplitTunnelSettingsPage({
    super.key,
    required this.isVpnConnected,
  });

  final bool Function() isVpnConnected;

  @override
  State<SplitTunnelSettingsPage> createState() => _SplitTunnelSettingsPageState();
}

class _SplitTunnelSettingsPageState extends State<SplitTunnelSettingsPage> {
  static const MethodChannel _wireGuardChannel = MethodChannel('wgfytunnel/wireguard');
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  List<InstalledApp> _installedApps = const [];
  bool _hasRequestedApps = false;
  bool _isLoadingApps = false;
  bool _isLoadingPrefs = true;
  SplitTunnelMode _splitTunnelMode = SplitTunnelMode.all;
  Set<String> _selectedPackages = <String>{};
  String _appSearchQuery = '';
  SplitTunnelDomainMode _domainMode = SplitTunnelDomainMode.all;
  final List<String> _domainList = <String>[];
  final TextEditingController _domainInputController = TextEditingController();
  bool _showReconnectBanner = false;
  Timer? _reconnectBannerTimer;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _reconnectBannerTimer?.cancel();
    _domainInputController.dispose();
    super.dispose();
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
                    _showFullLicensesPage(
                      pageContext,
                      applicationName: l10n.appTitle,
                    );
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
                    Text(
                      l10n.aboutTitle,
                      style: textTheme.headlineSmall,
                    ),
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
                                author: 'Copyright (C) 2022 by nekohasekai <contact-sagernet@sekai.icu>',
                                license: 'GNU General Public License v3.0 or later (GPL-3.0-or-later)',
                              ),
                              _buildAboutComponentSection(
                                pageContext,
                                title: 'NEKOBOX libcore',
                                usage: l10n.aboutLibcoreUsage,
                                author: 'Copyright (C) 2021 by nekohasekai <contact-sagernet@sekai.icu>',
                                license: 'GNU General Public License v3.0 or later (GPL-3.0-or-later)',
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

  Future<void> _showFullLicensesPage(
    BuildContext context, {
    required String applicationName,
  }) {
    final theme = Theme.of(context);
    final hiddenTitleStyle =
        (theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge ?? const TextStyle())
            .copyWith(
              color: Colors.transparent,
              fontSize: 0,
            );
    final hiddenToolbarStyle =
        (theme.appBarTheme.toolbarTextStyle ?? theme.textTheme.titleMedium ?? const TextStyle())
            .copyWith(
              color: Colors.transparent,
              fontSize: 0,
            );

    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: theme.copyWith(
            appBarTheme: theme.appBarTheme.copyWith(
              titleTextStyle: hiddenTitleStyle,
              toolbarTextStyle: hiddenToolbarStyle,
            ),
          ),
          child: LicensePage(
            applicationName: applicationName,
          ),
        ),
      ),
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
    if (selections.mode != SplitTunnelMode.all) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _ensureInstalledAppsLoaded();
        }
      });
    }
  }

  void _ensureInstalledAppsLoaded() {
    if (_hasRequestedApps || _isLoadingApps) {
      return;
    }
    _hasRequestedApps = true;
    _loadInstalledApps();
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
      final rawApps = await _wireGuardChannel.invokeMethod<List<dynamic>>('getInstalledApps');
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
      );
    } catch (e) {
      _hasRequestedApps = false;
      _showMessage('${AppLocalizations.of(context).errorLoadingApps}: $e');
    } finally {
      if (mounted) setState(() => _isLoadingApps = false);
    }
  }

  void _showMessage(String text) {
    final messenger = _scaffoldMessengerKey.currentState;
    if (messenger == null) {
      return;
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
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
    _reconnectBannerTimer?.cancel();

    if (!_showReconnectBanner) {
      setState(() {
        _showReconnectBanner = true;
      });
    }

    _reconnectBannerTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) {
        return;
      }

      _hideReconnectBanner();
    });
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

  Widget _buildModeCard<T extends Enum>({
    required String title,
    required IconData icon,
    required List<T> values,
    required T selected,
    required ValueChanged<T> onSelected,
    String Function(T selected)? labelBuilder,
  }) {
    final selectedIndex = values.indexOf(selected);
    final selectedLabel = labelBuilder?.call(selected) ?? (selected as dynamic).label as String;

    T cycleMode(int delta) {
      final nextIndex = (selectedIndex + delta + values.length) % values.length;
      return values[nextIndex];
    }

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              selectedLabel,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onSelected(cycleMode(-1)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Icon(Icons.chevron_left),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${selectedIndex + 1}/${values.length}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onSelected(cycleMode(1)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Icon(Icons.chevron_right),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFadeSwitcher({
    required Widget child,
    Alignment alignment = Alignment.topCenter,
  }) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      layoutBuilder: (currentChild, previousChildren) {
        final children = <Widget>[...previousChildren];
        if (currentChild != null) {
          children.add(currentChild);
        }

        return Stack(
          alignment: alignment,
          children: children,
        );
      },
      child: child,
    );
  }

  List<InstalledApp> get _filteredApps {
    final query = _appSearchQuery.trim().toLowerCase();
    if (query.isEmpty) return _installedApps;
    return _installedApps.where((app) {
      return app.label.toLowerCase().contains(query) ||
          app.packageName.toLowerCase().contains(query);
    }).toList();
  }

  void _toggleSelectedPackage(String packageName, bool enabled) {
    setState(() {
      final updated = Set<String>.from(_selectedPackages);
      if (enabled) {
        updated.add(packageName);
      } else {
        updated.remove(packageName);
      }
      _selectedPackages = updated;
    });
    _savePrefs();
  }

  void _togglePackageSelection(String packageName) {
    _toggleSelectedPackage(packageName, !_selectedPackages.contains(packageName));
  }

  void _addDomain() {
    final l10n = AppLocalizations.of(context);
    final raw = _domainInputController.text.trim();
    if (raw.isEmpty) return;
    final domains = raw
        .split(RegExp(r'[,;\s]+'))
        .map((d) => d.trim().toLowerCase())
        .where((d) => d.isNotEmpty && d.contains('.'));
    if (domains.isEmpty) {
      _showMessage(l10n.enterCorrectDomain);
      return;
    }
    setState(() {
      for (final d in domains) {
        if (!_domainList.contains(d)) _domainList.add(d);
      }
      _domainInputController.clear();
    });
    _savePrefs();
  }

  void _removeDomain(String domain) {
    setState(() => _domainList.remove(domain));
    _savePrefs();
  }

  Widget _buildDomainRow(String domain) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? Colors.white : Colors.black;
    final foregroundColor = isDark ? Colors.black : Colors.white;
    final borderColor = isDark ? Colors.white : Colors.black;

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          title: Text(
            domain,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w600,
                ),
          ),
          trailing: IconButton(
            onPressed: () => _removeDomain(domain),
            icon: Icon(Icons.close, color: foregroundColor),
            tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
          ),
        ),
      ),
    );
  }

  Widget _buildReconnectBanner(
    AppLocalizations l10n, {
    required double topPadding,
    required double tabBarHeight,
  }) {
    final theme = Theme.of(context);
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
      child: Material(
        color: theme.colorScheme.primary,
        elevation: 10,
        child: SizedBox(
          height: topPadding + kToolbarHeight + tabBarHeight,
          child: Column(
            children: [
              SizedBox(height: topPadding),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final verticalOffset = constraints.maxHeight * 0.50;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Transform.translate(
                        offset: Offset(0, verticalOffset),
                        child: Align(
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: double.infinity,
                            child: Text(
                              l10n.reconnectToApplyChangedSettings,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: tabBarHeight),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final languageService = Provider.of<LanguageService>(context);
    final tabBar = TabBar(
      tabs: [
        Tab(icon: const Icon(Icons.apps), text: l10n.apps),
        Tab(icon: const Icon(Icons.language), text: l10n.sites),
      ],
    );
    final topPadding = MediaQuery.paddingOf(context).top;
    final tabBarHeight = tabBar.preferredSize.height;
    final reconnectBannerHeight = topPadding + kToolbarHeight + tabBarHeight;
    final showReconnectBanner = _showReconnectBanner && widget.isVpnConnected();

    if (_isLoadingPrefs) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ScaffoldMessenger(
            key: _scaffoldMessengerKey,
            child: Scaffold(
              appBar: AppBar(
                actions: [
                  TextButton.icon(
                    icon: const Icon(Icons.language, size: 18),
                    label: Text(
                      languageService.language == AppLanguage.ru ? 'RU' : 'EN',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => languageService.toggleLanguage(),
                  ),
                  const ThemeModeButton(),
                  IconButton(
                    onPressed: _showAboutDialog,
                    icon: const Icon(Icons.help_outline),
                    tooltip: l10n.aboutTooltip,
                  ),
                  SizedBox(width: MediaQuery.sizeOf(context).width * 0.06),
                ],
                bottom: tabBar,
              ),
              body: TabBarView(
                children: [
                  _buildAppsTab(),
                  _buildDomainsTab(),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: ClipRect(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final curvedAnimation = CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                    reverseCurve: Curves.easeInCubic,
                  );

                  return SizeTransition(
                    sizeFactor: curvedAnimation,
                    axisAlignment: -1,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, -1),
                        end: Offset.zero,
                      ).animate(curvedAnimation),
                      child: child,
                    ),
                  );
                },
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      ...previousChildren,
                      ...?currentChild == null ? null : [currentChild],
                    ],
                  );
                },
                child: showReconnectBanner
                    ? SizedBox(
                        key: const ValueKey('reconnect-banner-visible'),
                        height: reconnectBannerHeight,
                        child: _buildReconnectBanner(
                          l10n,
                          topPadding: topPadding,
                          tabBarHeight: tabBarHeight,
                        ),
                      )
                    : const SizedBox(
                        key: ValueKey('reconnect-banner-hidden'),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppsTab() {
    final l10n = AppLocalizations.of(context);
    final screenSize = MediaQuery.sizeOf(context);
    final horizontalInset = screenSize.width * 0.02;
    final searchFieldVerticalSpacing = screenSize.height * 0.02;
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalInset, 16, horizontalInset, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildModeCard<SplitTunnelMode>(
            title: l10n.tunnelMode,
            icon: Icons.tune,
            values: SplitTunnelMode.values,
            selected: _splitTunnelMode,
            labelBuilder: (mode) {
              if (mode == SplitTunnelMode.all) {
                return _localizedSplitTunnelModeLabel(l10n, mode);
              }
              return '${_localizedSplitTunnelModeLabel(l10n, mode)} (${_selectedPackages.length})';
            },
            onSelected: (mode) async {
              setState(() {
                _splitTunnelMode = mode;
                if (mode == SplitTunnelMode.all) {
                  _selectedPackages = <String>{};
                  _appSearchQuery = '';
                }
              });
              if (mode != SplitTunnelMode.all) {
                _ensureInstalledAppsLoaded();
              }
              await _savePrefs();
            },
          ),
          Expanded(
            child: _buildFadeSwitcher(
              alignment: Alignment.topCenter,
              child: _splitTunnelMode == SplitTunnelMode.all
                  ? Padding(
                      key: const ValueKey('apps-mode-all'),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.public, size: 48, color: Colors.grey),
                          const SizedBox(height: 12),
                          Text(
                            l10n.allTrafficViaVpn,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : Card(
                      key: const ValueKey('apps-mode-list'),
                      margin: EdgeInsets.zero,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: EdgeInsets.only(top: searchFieldVerticalSpacing),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextField(
                                  onChanged: (value) => setState(() => _appSearchQuery = value),
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(Icons.search),
                                    hintText: l10n.searchApps,
                                    border: const OutlineInputBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(12)),
                                    ),
                                  ),
                                ),
                                SizedBox(height: searchFieldVerticalSpacing),
                              ],
                            ),
                          ),
                          Expanded(
                            child: !_hasRequestedApps || _isLoadingApps
                                ? const Center(child: CircularProgressIndicator())
                                : _filteredApps.isEmpty
                                    ? Center(child: Text(l10n.appsNotFound))
                                    : ListView.builder(
                                        padding: EdgeInsets.zero,
                                        itemCount: _filteredApps.length,
                                        itemBuilder: (context, index) {
                                          final app = _filteredApps[index];
                                          final selected = _selectedPackages.contains(app.packageName);
                                          final isDark = Theme.of(context).brightness == Brightness.dark;
                                          final selectedBackgroundColor =
                                            isDark ? Colors.white : Colors.black;
                                          final unselectedBackgroundColor =
                                            isDark ? Colors.transparent : Colors.white;
                                          final unselectedBorderColor =
                                            isDark ? Colors.white : Colors.black;
                                          final textColor = selected
                                            ? (isDark ? Colors.black : Colors.white)
                                            : (isDark ? Colors.white : Colors.black);
                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 12),
                                            child: Material(
                                            color: selected
                                              ? selectedBackgroundColor
                                              : unselectedBackgroundColor,
                                              borderRadius: BorderRadius.circular(14),
                                              child: InkWell(
                                                borderRadius: BorderRadius.circular(14),
                                                onTap: () => _togglePackageSelection(app.packageName),
                                                child: AnimatedContainer(
                                                  duration: const Duration(milliseconds: 160),
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 10,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    borderRadius: BorderRadius.circular(14),
                                                    border: Border.all(
                                                      color: selected
                                                          ? selectedBackgroundColor
                                                          : unselectedBorderColor,
                                                    ),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        app.label,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .titleMedium
                                                            ?.copyWith(
                                                              color: textColor,
                                                              fontWeight: FontWeight.w600,
                                                            ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        app.packageName,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodyMedium
                                                            ?.copyWith(
                                                              color: textColor.withValues(alpha: 0.82),
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDomainsTab() {
    final l10n = AppLocalizations.of(context);
    final horizontalInset = MediaQuery.sizeOf(context).width * 0.02;
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalInset, 16, horizontalInset, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildModeCard<SplitTunnelDomainMode>(
            title: l10n.domainMode,
            icon: Icons.language,
            values: SplitTunnelDomainMode.values,
            selected: _domainMode,
            labelBuilder: (mode) => _localizedSplitTunnelDomainModeLabel(l10n, mode),
            onSelected: (mode) async {
              setState(() {
                _domainMode = mode;
                if (mode == SplitTunnelDomainMode.all) {
                  _domainInputController.clear();
                }
              });
              await _savePrefs();
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _buildFadeSwitcher(
              child: _domainMode == SplitTunnelDomainMode.all
                  ? Padding(
                      key: const ValueKey('domains-mode-all'),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.public, size: 48, color: Colors.grey),
                          const SizedBox(height: 12),
                          Text(
                            l10n.allTrafficViaVpn,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : Column(
                      key: const ValueKey('domains-mode-list'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _domainInputController,
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.add_link),
                                  hintText: l10n.addDomainHint,
                                  border: const OutlineInputBorder(
                                    borderRadius: BorderRadius.all(Radius.circular(12)),
                                  ),
                                ),
                                onSubmitted: (_) => _addDomain(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 56,
                              child: FilledButton.tonal(
                                onPressed: _addDomain,
                                child: const Icon(Icons.add),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_domainList.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              _domainMode == SplitTunnelDomainMode.exclude
                                  ? l10n.excludedSites
                                  : l10n.addedSites,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: ListView.separated(
                              itemCount: _domainList.length,
                              separatorBuilder: (context, index) => const SizedBox(height: 10),
                              itemBuilder: (context, index) => _buildDomainRow(_domainList[index]),
                            ),
                          ),
                        ] else ...[
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.link_off, size: 48, color: Colors.grey),
                                  const SizedBox(height: 12),
                                  Text(
                                    l10n.domainsNotAdded,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
