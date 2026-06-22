import 'package:flutter/material.dart';

import 'app_log_service.dart';
import 'l10n/app_localizations.dart';

class AppLogsPage extends StatefulWidget {
  const AppLogsPage({super.key});

  @override
  State<AppLogsPage> createState() => _AppLogsPageState();
}

class _AppLogsPageState extends State<AppLogsPage> {
  late Future<String> _logsFuture = AppLogService.readLogs();

  void _refreshLogs() {
    setState(() {
      _logsFuture = AppLogService.readLogs();
    });
  }

  Future<void> _clearLogs() async {
    await AppLogService.clearLogs();
    if (!mounted) {
      return;
    }
    _refreshLogs();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.logsLabel),
        actions: [
          IconButton(
            onPressed: _refreshLogs,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: l10n.clearLogsLabel,
            onPressed: _clearLogs,
            icon: const Icon(Icons.delete_sweep_rounded),
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: _logsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.failedLoadLogsLabel,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final logs = (snapshot.data ?? '').trim();
          if (logs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.noLogsLabel, textAlign: TextAlign.center),
              ),
            );
          }

          return SelectionArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(
                logs,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.45,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
