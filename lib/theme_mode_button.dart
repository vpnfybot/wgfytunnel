import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'l10n/app_localizations.dart';
import 'theme_service.dart';

class ThemeModeButton extends StatelessWidget {
  const ThemeModeButton({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        final currentPreference = themeService.preference;
        return IconButton(
          tooltip: '${l10n.theme}: ${_labelFor(l10n, currentPreference)}',
          icon: Icon(currentPreference.icon),
          onPressed: () => themeService.setPreference(currentPreference.next),
        );
      },
    );
  }

  String _labelFor(AppLocalizations l10n, AppThemePreference preference) {
    switch (preference) {
      case AppThemePreference.light:
        return l10n.lightTheme;
      case AppThemePreference.dark:
        return l10n.darkTheme;
    }
  }
}
