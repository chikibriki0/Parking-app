import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/ws_service.dart';

class ParkingProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _zones = [];
  final Map<int, String> _spotStatuses = {};
  int? _mySpotId;
  DateTime? _myStartTime;
  DateTime? _myExpiresAt;
  Map<String, dynamic>? _stats;
  List<dynamic> _history = [];
  bool _loading = false;
  bool _initialized = false;
  bool _isOnline = true;

  final WsService _wsService = WsService();

  List<Map<String, dynamic>> get zones => _zones;
  Map<int, String> get spotStatuses => _spotStatuses;
  int? get mySpotId => _mySpotId;
  DateTime? get myStartTime => _myStartTime;
  DateTime? get myExpiresAt => _myExpiresAt;
  Map<String, dynamic>? get stats => _stats;
  List<dynamic> get history => _history;
  bool get loading => _loading;

  /// true — WebSocket подключён к серверу. Используется в UI, чтобы
  /// показать баннер «Нет соединения с сервером», когда сеть пропала.
  /// Без этого баннера пользователь видит закэшированные данные и
  /// думает, что всё ок, пока не упрётся в ошибку при бронировании.
  bool get isOnline => _isOnline;

  void init() {
    if (_initialized) return;
    _initialized = true;
    // Когда WS-соединение восстанавливается после оффлайна — перетягиваем
    // карту/брони/историю заново. Без этого сценарий «открыли приложение
    // без сети → включили wifi» оставляет пины зон МЭИ на «0/0», пока
    // пользователь не перезапустит приложение.
    _wsService.onReconnected = () {
      if (!_isOnline) {
        _isOnline = true;
        notifyListeners();
      }
      loadAll();
    };
    _wsService.onDisconnected = () {
      if (_isOnline) {
        _isOnline = false;
        notifyListeners();
      }
    };
    _wsService.connect();
    _wsService.stream.listen((data) {
      final spotId = data['spot_id'] as int?;
      final type = data['type'];
      if (spotId != null) {
        final newStatus = (type == 0) ? 'OCCUPIED' : 'FREE';
        _spotStatuses[spotId] = newStatus;
        // Также синхронизируем вложенный status внутри _zones, иначе
        // экраны, отрисовывающиеся из zones (схема, сетка), застревают
        // на устаревших данных.
        for (final zone in _zones) {
          for (final spot in (zone['spots'] as List? ?? [])) {
            if ((spot as Map)['id'] == spotId) {
              spot['status'] = newStatus;
            }
          }
        }

        if (type == 1 && spotId == _mySpotId) {
          final source = data['source'];
          if (source != 'USER') {
            _mySpotId = null;
            _myStartTime = null;
            _myExpiresAt = null;
          }
        }
        notifyListeners();     // перерисовать схему/карту немедленно
        _refreshStats();       // обновить общую статистику с сервера
      }
    });
    loadAll();
  }

  // отдельный метод чтобы не блокировать поток
  Future<void> _refreshStats() async {
    final data = await ApiService.getStats();
    if (data != null) {
      _stats = data;
      notifyListeners();       // перерисовать статистику после ответа
    }
  }

  Future<void> loadAll() async {
    _loading = true;
    notifyListeners();

    await Future.wait([
      loadMap(),
      loadMyParking(),
      loadStats(),
      loadHistory(),
    ]);

    _loading = false;
    notifyListeners();
  }

  Future<void> loadMap() async {
    final data = await ApiService.getParkingMap();
    if (data != null && data['zones'] != null) {
      _zones = List<Map<String, dynamic>>.from(
        (data['zones'] as List).map((z) => Map<String, dynamic>.from(z)),
      );
      for (final zone in _zones) {
        final spots = zone['spots'] as List? ?? [];
        for (final spot in spots) {
          _spotStatuses[spot['id'] as int] = spot['status'] as String;
        }
      }
      notifyListeners();
    }
  }

  Future<void> loadMyParking() async {
    final data = await ApiService.getMyParking();
    if (data == null) return;

    if (data.isEmpty) {
      if (_mySpotId != null || _myStartTime != null || _myExpiresAt != null) {
        _mySpotId = null;
        _myStartTime = null;
        _myExpiresAt = null;
        notifyListeners();
      }
      return;
    }

    final newSpotId = data['spot_id'] as int?;
    final startStr = data['start_time'] as String?;
    final expiresStr = data['expires_at'] as String?;
    // Backend отдаёт время в UTC (ISO с 'Z'). .toLocal() переводит в
    // часовой пояс устройства, иначе на телефоне в МСК часы покажутся
    // со сдвигом -3.
    final newStart = startStr != null
        ? DateTime.tryParse(startStr)?.toLocal()
        : null;
    final newExpires = expiresStr != null
        ? DateTime.tryParse(expiresStr)?.toLocal()
        : null;

    if (newSpotId != _mySpotId ||
        newStart != _myStartTime ||
        newExpires != _myExpiresAt) {
      _mySpotId = newSpotId;
      _myStartTime = newStart;
      _myExpiresAt = newExpires;
      notifyListeners();
    }
  }

  Future<void> loadStats() async {
    final data = await ApiService.getStats();
    if (data != null) {
      _stats = data;
      notifyListeners();
    }
  }

  Future<void> loadHistory() async {
    _history = await ApiService.getMyHistory();
  }

  Future<Map<String, dynamic>> reserveSpot(int spotId, {Duration? duration}) async {
    final result = await ApiService.reserveSpot(spotId, duration: duration);
    if (result['success'] == true) {
      _mySpotId = spotId;
      _myStartTime = DateTime.now();
      final expiresStr = result['expires_at'] as String?;
      _myExpiresAt = expiresStr != null
          ? DateTime.tryParse(expiresStr)?.toLocal()
          : (duration != null ? _myStartTime!.add(duration) : null);
      _spotStatuses[spotId] = 'OCCUPIED';
      await loadStats();
      await loadHistory();
      notifyListeners();
    }
    return result;
  }

  Future<Map<String, dynamic>> extendParking({required Duration duration}) async {
    final spotId = _mySpotId;
    if (spotId == null) {
      return {'success': false, 'message': 'Нет активной парковки'};
    }
    final result =
        await ApiService.extendParking(spotId, duration: duration);
    if (result['success'] == true) {
      final newExpires = result['expires_at'] as String?;
      if (newExpires != null) {
        _myExpiresAt = DateTime.tryParse(newExpires)?.toLocal();
        notifyListeners();
      }
    }
    return result;
  }

  Future<Map<String, dynamic>> releaseSpot(int spotId) async {
    final result = await ApiService.releaseSpot(spotId);
    if (result['success'] == true) {
      _mySpotId = null;
      _myStartTime = null;
      _myExpiresAt = null;
      _spotStatuses[spotId] = 'FREE';
      await loadStats();
      await loadHistory();
      notifyListeners();
    }
    return result;
  }

  String getSpotStatus(int spotId) {
    return _spotStatuses[spotId] ?? 'FREE';
  }

  /// Полный сброс пользовательских данных. Вызывается при logout и при
  /// логине новым пользователем — иначе ChangeNotifier живёт всё время
  /// работы приложения и хранит историю/брони предыдущего юзера,
  /// которые новый видит у себя в профиле.
  void resetUserState() {
    _mySpotId = null;
    _myStartTime = null;
    _myExpiresAt = null;
    _history = [];
    _stats = null;
    _spotStatuses.clear();
    _zones = [];
    // _initialized оставляем как есть — WS-соединение пере-открывать не надо.
    notifyListeners();
  }

  @override
  void dispose() {
    _wsService.dispose();
    super.dispose();
  }
}