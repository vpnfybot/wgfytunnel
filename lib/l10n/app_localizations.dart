import 'package:flutter/material.dart';

enum AppLanguage { en, ru }

class AppLocalizations {
  final AppLanguage language;

  AppLocalizations(this.language);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  String get appTitle => _get('wgfytunnel');
  String get connect => _get('Подключиться');
  String get disconnect => _get('Отключится');
  String get importing => _get('Импорт...');
  String get selectConfFile => _get('Выберите файл конфигурации');
  String get configNotSelected => _get('Конфигурация не выбрана');
  String get configSelected => _get('Конфигурация выбрана');
  String get importConfig => _get('Импортировать');
  String get configHelpTooltip => _get('Где взять конфигурацию');
  String get configPurchaseIntro => _get('Вы можете приобрести конфигурацию в боте');
  String get configPurchaseLink => _get('t.me/vpnfybot');
  String get failedOpenLink => _get('Не удалось открыть ссылку');
  String get updateAvailableTitle => _get('Доступно обновление');
  String get updateAvailableMessage => _get('Доступна новая версия приложения. Установить сейчас?');
  String get updateNow => _get('Обновить');
  String get later => _get('Позже');
  String get importedConfigs => _get('Импортированные конфигурации');
  String get noImportedConfigs => _get('Конфигурации еще не импортированы');
  String get noFileSelected => _get('Файл не выбран');
  String get splitTunneling => _get('Раздельное туннелирование');
  String get apps => _get('Приложения');
  String get sites => _get('Сайты');
  String get tunnelMode => _get('Режим туннелирования');
  String get allSystemViaVpn => _get('Вся система через VPN');
  String get onlySelectedApps => _get('Только выбранные приложения');
  String get allExceptSelected => _get('Все приложения кроме выбранных');
  String get allSystemDescription =>
      _get('Через VPN будет идти трафик всей системы.');
  String get onlySelectedDescription =>
      _get('Через VPN будут идти только отмеченные приложения.');
  String get allExceptDescription =>
      _get('Через VPN будет идти трафик всей системы, кроме отмеченных приложений.');
  String get searchApps => _get('Поиск приложений');
  String get appsNotFound => _get('Приложения не найдены');
  String get allTrafficViaVpn => _get('Весь трафик идёт через VPN');
  String get domainMode => _get('Режим для сайтов');
  String get allSitesViaVpn => _get('Все сайты через VPN');
  String get onlySpecifiedDomains => _get('Только указанные сайты');
  String get allSitesExceptSpecified => _get('Все сайты кроме указанных');
  String get allSitesDescription =>
      _get('Весь трафик идет через VPN без доменных ограничений.');
  String get onlyDomainsDescription =>
      _get('Через VPN идут только перечисленные домены (остальной трафик — напрямую).');
  String get exceptDomainsDescription =>
      _get('Через VPN идет весь трафик, кроме перечисленных доменов.');
  String get selectApps => _get('Выберите приложения');
  String get selectSites => _get('Выберите сайты');
  String get selectAppsAndSites => _get('Выберите приложения и сайты');
    String get addedSites => _get('Добавленные сайты');
    String get excludedSites => _get('Исключенные сайты');
  String get addDomainHint => _get('example.com');
  String get domainsNotAdded => _get('Сайты не выбраны');
  String get enterCorrectDomain => _get('Введите корректный домен (например, example.com)');
  String get failedGetApps => _get('Не удалось получить список приложений');
  String get errorLoadingApps => _get('Ошибка загрузки приложений');
  String get fileSelectionCancelled => _get('Выбор файла отменен');
  String get failedGetFilePath => _get('Не удалось получить путь к файлу');
  String get failedReadFile => _get('Не удалось прочитать файл');
  String get configAlreadyImported => _get('Конфигурация уже импортирована');
  String get configInfoTitle => _get('Информация о конфигурации');
  String get configNameLabel => _get('Имя');
  String get configPathLabel => _get('Путь');
  String get configStatusLabel => _get('Статус');
  String get configValidStatus => _get('Валидная');
  String get configInvalidStatus => _get('Невалидная');
  String get configInterfacesCount => _get('Интерфейсов');
  String get configPeersCount => _get('Пиров');
  String get configInterfaceSection => _get('Интерфейс');
  String get configPeerSection => _get('Пир');
  String get invalidConfig => _get('Некорректная конфигурация WireGuard');
  String get failedParseConfig => _get('Не удалось разобрать конфигурацию');
  String get failedStartTunnel => _get('Не удалось запустить туннель');
  String get failedStopTunnel => _get('Не удалось остановить туннель');
  String get tunnelStarted => _get('Туннель запущен');
  String get tunnelStopped => _get('Туннель остановлен');
  String get languageLabel => _get('Язык');
  String get theme => _get('Тема');
  String get systemTheme => _get('Системная');
  String get lightTheme => _get('Светлая');
  String get darkTheme => _get('Темная');
  String get english => _get('English');
  String get russian => _get('Русский');
  String get scanQrCode => _get('Сканировать QR-код');
  String get reconnectToApplyChangedSettings => _get(
    'Чтобы применить измененные настройки, переподключите VPN.',
  );
  String get aboutTooltip => _get('О приложении и лицензиях');
  String get aboutTitle => _get('О приложении');
  String get aboutLicensesIntro => _get(
    'В этой сборке используются сторонние компоненты с открытыми лицензиями. Ниже перечислены основные встроенные и подключенные библиотеки, влияющие на работу VPN.',
  );
  String get aboutLicensesFooter => _get(
    'Полные тексты лицензий Flutter и подключенных Dart-пакетов можно открыть отдельной кнопкой.',
  );
  String get componentUsageLabel => _get('Использование');
  String get componentAuthorLabel => _get('Автор / правообладатель');
  String get componentLicenseLabel => _get('Лицензия');
  String get viewFullLicenses => _get('Все лицензии');
  String get aboutSingBoxUsage => _get(
    'Встроенный runtime для маршрутизации доменов и VPN-сценариев на базе sing-box.',
  );
  String get aboutLibcoreUsage => _get(
    'Локальная интеграция libcore/NEKOBOX для запуска встроенного сетевого ядра.',
  );
  String get aboutWireGuardUsage => _get(
    'Android-библиотека, через которую приложение поднимает WireGuard-туннель.',
  );

  String translateRuntimeMessage(String text) {
    if (language == AppLanguage.ru || text.isEmpty) {
      return text;
    }

    switch (text) {
      case 'Разрешение на запуск VPN отклонено':
        return 'VPN permission was denied';
      case 'Нет конфигурации для подключения':
        return 'No configuration available to connect';
      case 'Подключение уже выполняется':
        return 'Connection is already in progress';
      case 'Для выбранного режима нужно отметить хотя бы одно приложение':
        return 'Select at least one app for the chosen mode';
      case 'Для доменного режима укажите хотя бы один домен':
        return 'Specify at least one domain for the selected site mode';
      case 'VPN подключен для всей системы':
        return 'VPN connected for the whole system';
      case 'VPN подключен только для выбранных приложений':
        return 'VPN connected only for selected apps';
      case 'VPN подключен для всей системы, кроме выбранных приложений':
        return 'VPN connected for the whole system except selected apps';
      case 'VPN подключен':
        return 'VPN connected';
      case 'Не удалось прочитать конфиг':
        return 'Failed to read the config';
      case 'Конфиг WireGuard невалиден':
        return 'WireGuard config is invalid';
      case 'Не удалось поднять WireGuard туннель':
        return 'Failed to bring up the WireGuard tunnel';
      case 'Не удалось получить список приложений':
        return 'Failed to get the app list';
      case 'VPN отключен':
        return 'VPN disconnected';
      case 'Не удалось отключить туннель':
        return 'Failed to disconnect the tunnel';
      case 'VPN sing-box подключен для всей системы':
        return 'VPN sing-box connected for the whole system';
      case 'VPN sing-box: только выбранные сайты через туннель':
        return 'VPN sing-box: only selected sites through the tunnel';
      case 'VPN sing-box: все сайты кроме выбранных через туннель':
        return 'VPN sing-box: all sites except selected through the tunnel';
      case 'Не удалось запустить sing-box':
        return 'Failed to start sing-box';
      case 'VPN sing-box отключен':
        return 'VPN sing-box disconnected';
      case 'Файл не найден':
        return 'File not found';
      case 'Не удалось определить IP для выбранных доменов. Проверьте DNS/сеть и попробуйте снова':
        return 'Failed to resolve IPs for the selected domains. Check DNS/network and try again';
      case 'В конфиге отсутствует секция [Interface]':
        return 'The config is missing the [Interface] section';
      case 'В конфиге отсутствует секция [Peer]':
        return 'The config is missing the [Peer] section';
      case 'Не удалось применить AllowedIPs для доменного режима':
        return 'Failed to apply AllowedIPs for the site mode';
      case 'Конфигурация sing-box не передана':
        return 'sing-box configuration was not provided';
      case 'Не удалось создать VPN интерфейс sing-box':
        return 'Failed to create the sing-box VPN interface';
      case 'sing-box остановлен':
        return 'sing-box stopped';
      case 'Истекло ожидание запуска sing-box':
        return 'Timed out while waiting for sing-box to start';
      case 'sing-box не был инициализирован':
        return 'sing-box was not initialized';
    }

    if (text.startsWith('VPN: только выбранные сайты через туннель (') && text.endsWith(')')) {
      final sites = text.substring(
        'VPN: только выбранные сайты через туннель ('.length,
        text.length - 1,
      );
      return 'VPN: only selected sites through the tunnel ($sites)';
    }

    if (text.startsWith('VPN: все сайты кроме выбранных через туннель (') && text.endsWith(')')) {
      final sites = text.substring(
        'VPN: все сайты кроме выбранных через туннель ('.length,
        text.length - 1,
      );
      return 'VPN: all sites except selected through the tunnel ($sites)';
    }

    if (text.startsWith('Embedded sing-box недоступен для ABI: ') &&
        text.endsWith('. В APK отсутствует совместимый libgojni.so.')) {
      final abiList = text.substring(
        'Embedded sing-box недоступен для ABI: '.length,
        text.length - '. В APK отсутствует совместимый libgojni.so.'.length,
      );
      return 'Embedded sing-box is unavailable for ABI: $abiList. The APK does not include a compatible libgojni.so.';
    }

    return text;
  }

  String _get(String ruText) {
    if (language == AppLanguage.ru) return ruText;
    // English translations
    switch (ruText) {
      case 'wgfytunnel':
        return 'wgfytunnel';
      case 'Подключиться':
        return 'Connect';
      case 'Отключится':
        return 'Disconnect';
      case 'Импорт...':
        return 'Import...';
      case 'Выберите файл конфигурации':
        return 'Select configuration file';
      case 'Конфигурация не выбрана':
        return 'Configuration not selected';
      case 'Конфигурация выбрана':
        return 'Configuration selected';
      case 'Импортировать':
        return 'Import';
      case 'Где взять конфигурацию':
        return 'Where to get a configuration';
      case 'Вы можете приобрести конфигурацию в боте':
        return 'You can purchase a configuration in the bot';
      case 't.me/vpnfybot':
        return 't.me/vpnfybot';
      case 'Не удалось открыть ссылку':
        return 'Failed to open the link';
      case 'Доступно обновление':
        return 'Update available';
      case 'Доступна новая версия приложения. Установить сейчас?':
        return 'A new app version is available. Install it now?';
      case 'Обновить':
        return 'Update';
      case 'Позже':
        return 'Later';
      case 'Импортированные конфигурации':
        return 'Imported configurations';
      case 'Конфигурации еще не импортированы':
        return 'No imported configurations yet';
      case 'Файл не выбран':
        return 'No file selected';
      case 'Раздельное туннелирование':
        return 'Split Tunneling';
      case 'Приложения':
        return 'Apps';
      case 'Сайты':
        return 'Sites';
      case 'Режим туннелирования':
        return 'Tunneling Mode';
      case 'Вся система через VPN':
        return 'All system via VPN';
      case 'Только выбранные приложения':
        return 'Only selected apps';
      case 'Все приложения кроме выбранных':
        return 'All except selected';
      case 'Через VPN будет идти трафик всей системы.':
        return 'All system traffic will go through VPN.';
      case 'Через VPN будут идти только отмеченные приложения.':
        return 'Only selected apps will go through VPN.';
      case 'Через VPN будет идти трафик всей системы, кроме отмеченных приложений.':
        return 'All system traffic except selected apps will go through VPN.';
      case 'Поиск приложений':
        return 'Search apps';
      case 'Приложения не найдены':
        return 'No apps found';
      case 'Весь трафик идёт через VPN':
        return 'All traffic goes through VPN';
      case 'Режим для сайтов':
        return 'Site Mode';
      case 'Все сайты через VPN':
        return 'All sites via VPN';
      case 'Только указанные сайты':
        return 'Only specified sites';
      case 'Все сайты кроме указанных':
        return 'All sites except specified';
      case 'Весь трафик идет через VPN без доменных ограничений.':
        return 'All traffic goes through VPN without domain restrictions.';
      case 'Через VPN идут только перечисленные домены (остальной трафик — напрямую).':
        return 'Only listed domains go through VPN (other traffic goes directly).';
      case 'Через VPN идет весь трафик, кроме перечисленных доменов.':
        return 'All traffic goes through VPN except listed domains.';
      case 'Выберите приложения':
        return 'Select apps';
      case 'Выберите сайты':
        return 'Select sites';
      case 'Выберите приложения и сайты':
        return 'Select apps and sites';
      case 'Добавленные сайты':
        return 'Added sites';
      case 'Исключенные сайты':
        return 'Excluded sites';
      case 'example.com':
        return 'example.com';
      case 'Сайты не выбраны':
        return 'No sites selected';
      case 'Введите корректный домен (например, example.com)':
        return 'Enter a valid domain (e.g., example.com)';
      case 'Не удалось получить список приложений':
        return 'Failed to get app list';
      case 'Ошибка загрузки приложений':
        return 'Error loading apps';
      case 'Выбор файла отменен':
        return 'File selection cancelled';
      case 'Не удалось получить путь к файлу':
        return 'Failed to get file path';
      case 'Не удалось прочитать файл':
        return 'Failed to read file';
      case 'Конфигурация уже импортирована':
        return 'Configuration already imported';
      case 'Информация о конфигурации':
        return 'Configuration details';
      case 'Имя':
        return 'Name';
      case 'Путь':
        return 'Path';
      case 'Статус':
        return 'Status';
      case 'Валидная':
        return 'Valid';
      case 'Невалидная':
        return 'Invalid';
      case 'Интерфейсов':
        return 'Interfaces';
      case 'Пиров':
        return 'Peers';
      case 'Интерфейс':
        return 'Interface';
      case 'Пир':
        return 'Peer';
      case 'Некорректная конфигурация WireGuard':
        return 'Invalid WireGuard configuration';
      case 'Не удалось разобрать конфигурацию':
        return 'Failed to parse configuration';
      case 'Не удалось запустить туннель':
        return 'Failed to start tunnel';
      case 'Не удалось остановить туннель':
        return 'Failed to stop tunnel';
      case 'Туннель запущен':
        return 'Tunnel started';
      case 'Туннель остановлен':
        return 'Tunnel stopped';
      case 'Язык':
        return 'Language';
      case 'Тема':
        return 'Theme';
      case 'Системная':
        return 'System';
      case 'Светлая':
        return 'Light';
      case 'Темная':
        return 'Dark';
      case 'English':
        return 'English';
      case 'Русский':
        return 'Русский';
      case 'Сканировать QR-код':
        return 'Scan QR code';
      case 'Чтобы применить измененные настройки, переподключите VPN.':
        return 'Reconnect the VPN to apply the changed settings.';
      case 'О приложении и лицензиях':
        return 'About and licenses';
      case 'О приложении':
        return 'About';
      case 'В этой сборке используются сторонние компоненты с открытыми лицензиями. Ниже перечислены основные встроенные и подключенные библиотеки, влияющие на работу VPN.':
        return 'This build uses third-party open-source components. The main bundled and linked libraries that affect the VPN functionality are listed below.';
      case 'Полные тексты лицензий Flutter и подключенных Dart-пакетов можно открыть отдельной кнопкой.':
        return 'You can open the full license texts for Flutter and the bundled Dart packages with the separate button.';
      case 'Использование':
        return 'Usage';
      case 'Автор / правообладатель':
        return 'Author / rights holder';
      case 'Лицензия':
        return 'License';
      case 'Все лицензии':
        return 'All licenses';
      case 'Встроенный runtime для маршрутизации доменов и VPN-сценариев на базе sing-box.':
        return 'Embedded runtime used for domain routing and VPN scenarios based on sing-box.';
      case 'Локальная интеграция libcore/NEKOBOX для запуска встроенного сетевого ядра.':
        return 'Local libcore/NEKOBOX integration used to run the embedded networking core.';
      case 'Android-библиотека, через которую приложение поднимает WireGuard-туннель.':
        return 'Android library used by the app to bring up the WireGuard tunnel.';
      default:
        return ruText;
    }
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'ru'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    final lang = locale.languageCode == 'ru' ? AppLanguage.ru : AppLanguage.en;
    return AppLocalizations(lang);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
