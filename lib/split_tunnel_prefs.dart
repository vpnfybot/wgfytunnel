import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';

class SplitTunnelPrefs {
  static const _keyMode = 'split_tunnel_mode';
  static const _keyPackages = 'split_tunnel_packages';
  static const _keyDomainMode = 'split_tunnel_domain_mode';
  static const _keyDomains = 'split_tunnel_domains';
  static final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  static Future<SharedPreferences> _instance() => _prefs;

  static Future<({
    SplitTunnelMode mode,
    Set<String> packages,
    SplitTunnelDomainMode domainMode,
    List<String> domains,
  })> loadSelections() async {
    final prefs = await _instance();
    final rawMode = prefs.getString(_keyMode);
    final rawDomainMode = prefs.getString(_keyDomainMode);

    return (
      mode: SplitTunnelMode.values.firstWhere(
        (mode) => mode.wireValue == rawMode,
        orElse: () => SplitTunnelMode.all,
      ),
      packages: prefs.getStringList(_keyPackages)?.toSet() ?? <String>{},
      domainMode: SplitTunnelDomainMode.values.firstWhere(
        (mode) => mode.wireValue == rawDomainMode,
        orElse: () => SplitTunnelDomainMode.all,
      ),
      domains: prefs.getStringList(_keyDomains) ?? <String>[],
    );
  }

  static Future<SplitTunnelMode> loadMode() async {
    final prefs = await _instance();
    final raw = prefs.getString(_keyMode);
    return SplitTunnelMode.values.firstWhere(
      (m) => m.wireValue == raw,
      orElse: () => SplitTunnelMode.all,
    );
  }

  static Future<void> saveMode(SplitTunnelMode mode) async {
    final prefs = await _instance();
    await prefs.setString(_keyMode, mode.wireValue);
  }

  static Future<Set<String>> loadPackages() async {
    final prefs = await _instance();
    return prefs.getStringList(_keyPackages)?.toSet() ?? <String>{};
  }

  static Future<void> savePackages(Set<String> packages) async {
    final prefs = await _instance();
    await prefs.setStringList(_keyPackages, packages.toList()..sort());
  }

  static Future<SplitTunnelDomainMode> loadDomainMode() async {
    final prefs = await _instance();
    final raw = prefs.getString(_keyDomainMode);
    return SplitTunnelDomainMode.values.firstWhere(
      (m) => m.wireValue == raw,
      orElse: () => SplitTunnelDomainMode.all,
    );
  }

  static Future<void> saveDomainMode(SplitTunnelDomainMode mode) async {
    final prefs = await _instance();
    await prefs.setString(_keyDomainMode, mode.wireValue);
  }

  static Future<List<String>> loadDomains() async {
    final prefs = await _instance();
    return prefs.getStringList(_keyDomains) ?? <String>[];
  }

  static Future<void> saveDomains(List<String> domains) async {
    final prefs = await _instance();
    await prefs.setStringList(_keyDomains, domains);
  }
}
