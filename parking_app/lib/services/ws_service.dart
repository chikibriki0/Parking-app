import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/app_config.dart';

/// WsService — обёртка над web_socket_channel с авто-переподключением и
/// видимыми логами в debugPrint. Логи помогают понять при сборке APK,
/// почему «не приходят обновления в реальном времени»: если URL неверный,
/// в logcat будет видно `[WS] connect error → reconnect in 3s`.
class WsService {
  /// URL берётся из AppConfig (выводится из API_BASE_URL).
  String get wsUrl => AppConfig.wsUrl;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  Timer? _connectedTimer;
  bool _disposed = false;
  bool _wasDisconnected = true; // true до первого подтверждённого коннекта
  int _attempt = 0;

  /// Callback, который дёргается при переходе «не было сети → есть».
  /// Используется ParkingProvider для перезагрузки карты, иначе после
  /// возвращения сети пины зон МЭИ остаются «0/0» до перезапуска
  /// приложения (HTTP-loadAll сделал запрос ещё в оффлайне и провалился,
  /// а триггера повторить нет).
  VoidCallback? onReconnected;

  final StreamController<Map<String, dynamic>> _controller =
      StreamController.broadcast();

  Stream<Map<String, dynamic>> get stream => _controller.stream;

  void connect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _attempt++;
    final url = wsUrl;
    debugPrint('[WS] connecting → $url (attempt $_attempt)');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
    } catch (e) {
      debugPrint('[WS] connect threw: $e — retry in 3s');
      _scheduleReconnect();
      return;
    }

    _sub = _channel!.stream.listen(
      (message) {
        // Любое полученное сообщение = подтверждённый коннект. Если до
        // этого мы были в оффлайне — дёргаем onReconnected для перезагрузки.
        _markConnected();
        try {
          final data = jsonDecode(message);
          if (data is Map<String, dynamic>) {
            _controller.add(data);
          }
        } catch (e) {
          debugPrint('[WS] decode error: $e');
        }
      },
      onError: (e) {
        debugPrint('[WS] stream error: $e → reconnect in 3s');
        _scheduleReconnect();
      },
      onDone: () {
        debugPrint('[WS] stream closed (code=${_channel?.closeCode}) → reconnect in 3s');
        _scheduleReconnect();
      },
      cancelOnError: true,
    );

    // Первое успешное событие = окончательное подтверждение коннекта.
    // До этого момента WebSocketChannel.connect ещё может вернуть ошибку.
    debugPrint('[WS] subscribed, awaiting messages…');
    _attempt = 0;

    // Страховка: если в течение 2 секунд не пришло ни ошибки, ни сообщения,
    // тоже считаем коннект подтверждённым. Иначе при тихой WS-сессии
    // (например, симуляция отключена) onReconnected никогда не сработает,
    // и карта так и останется пустой после возврата сети.
    _connectedTimer?.cancel();
    _connectedTimer = Timer(const Duration(seconds: 2), _markConnected);
  }

  void _markConnected() {
    _connectedTimer?.cancel();
    if (!_wasDisconnected) return;
    _wasDisconnected = false;
    debugPrint('[WS] connection confirmed → triggering data reload');
    final cb = onReconnected;
    if (cb != null) cb();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    // Помечаем «снова не подключены», чтобы следующий успешный коннект
    // снова дёрнул onReconnected.
    _wasDisconnected = true;
    _connectedTimer?.cancel();
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), connect);
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _connectedTimer?.cancel();
    _sub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _controller.close();
  }
}
