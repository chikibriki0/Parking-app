/// AppConfig — все настраиваемые URL-ы и параметры окружения.
///
/// Передаются через `--dart-define` при сборке, например:
///   flutter build apk --release \
///     --dart-define=API_BASE_URL=http://79.137.195.136:8080 \
///     --dart-define=MAPTILER_KEY=xxx
/// или для отладки:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
///
/// WebSocket-URL автоматически выводится из API_BASE_URL — отдельно
/// передавать его НЕ нужно. http → ws, https → wss, путь /ws.
///
/// Дефолты подобраны под Android-эмулятор (10.0.2.2 → localhost хоста).
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );

  /// WebSocket-URL, выведенный из apiBaseUrl. Меняем только схему
  /// (http/https → ws/wss) и добавляем путь /ws — host и порт остаются
  /// теми же, что у API. Это исключает класс ошибок «забыл передать
  /// WS_BASE_URL при сборке APK», когда HTTP работает, а WS уходит
  /// в эмуляторный 10.0.2.2 и молча отваливается.
  static String get wsUrl {
    final api = apiBaseUrl;
    final String wsScheme;
    if (api.startsWith('https://')) {
      wsScheme = 'wss://';
    } else if (api.startsWith('http://')) {
      wsScheme = 'ws://';
    } else {
      // Конфиг без схемы — фолбэк на ws://.
      wsScheme = 'ws://';
    }
    // Срезаем «http(s)://» и любой завершающий «/».
    final hostPort = api
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'/$'), '');
    return '$wsScheme$hostPort/ws';
  }

  /// API-ключ MapTiler. Получить можно на https://cloud.maptiler.com
  /// (бесплатно ~100 000 запросов/месяц). Пустая строка — fallback на OSM.
  static const String mapTilerKey = String.fromEnvironment(
    'MAPTILER_KEY',
    defaultValue: '',
  );

  /// Стиль карты MapTiler: streets-v2 / streets-v2-light / basic-v2 / bright /
  /// dataviz-light и т.д. Список — https://docs.maptiler.com/cloud/maps/
  static const String mapTilerStyle = String.fromEnvironment(
    'MAPTILER_STYLE',
    defaultValue: 'streets-v2',
  );

  /// URL-шаблон для TileLayer. Если ключ MapTiler задан — используем его,
  /// иначе откат на OpenStreetMap.
  static String get mapTileUrl {
    if (mapTilerKey.isNotEmpty) {
      return 'https://api.maptiler.com/maps/$mapTilerStyle/256/{z}/{x}/{y}.png'
          '?key=$mapTilerKey';
    }
    return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  /// Текст для виджета атрибуции — MapTiler требует упоминание провайдера.
  static String get mapAttribution => mapTilerKey.isNotEmpty
      ? '© MapTiler · © OpenStreetMap'
      : '© OpenStreetMap';
}
