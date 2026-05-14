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
}
