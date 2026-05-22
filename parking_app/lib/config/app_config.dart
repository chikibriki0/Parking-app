/// AppConfig — все настраиваемые URL-ы и параметры окружения.
///
/// Передаются через `--dart-define` при сборке, например:
///   flutter build apk --dart-define=API_BASE_URL=https://parking.example.com --dart-define=WS_BASE_URL=wss://parking.example.com/ws
/// или для отладки:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080 --dart-define=WS_BASE_URL=ws://10.0.2.2:8080/ws
///
/// Дефолты подобраны под Android-эмулятор (10.0.2.2 → localhost хоста).
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );

  static const String wsUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'ws://10.0.2.2:8080/ws',
  );

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
