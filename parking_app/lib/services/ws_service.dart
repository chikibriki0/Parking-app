import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class WsService {
  static const String wsUrl = 'ws://localhost:8080/ws';

  WebSocketChannel? _channel;
  final StreamController<Map<String, dynamic>> _controller =
      StreamController.broadcast();

  Stream<Map<String, dynamic>> get stream => _controller.stream;

  void connect() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            _controller.add(data);
          } catch (_) {}
        },
        onError: (_) => _reconnect(),
        onDone: () => _reconnect(),
      );
    } catch (_) {
      Future.delayed(const Duration(seconds: 3), connect);
    }
  }

  void _reconnect() {
    Future.delayed(const Duration(seconds: 3), connect);
  }

  void dispose() {
    _channel?.sink.close();
    _controller.close();
  }
}