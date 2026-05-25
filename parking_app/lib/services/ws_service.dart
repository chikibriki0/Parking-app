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
  bool _disposed = false;
  int _attempt = 0;

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
  }

  void _scheduleReconnect() {
    if (_disposed) return;
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
    _sub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _controller.close();
  }
}
