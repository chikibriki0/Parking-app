import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/ws_service.dart';

class ParkingProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _zones = [];
  final Map<int, String> _spotStatuses = {};
  int? _mySpotId;
  DateTime? _myStartTime;
  Map<String, dynamic>? _stats;
  List<dynamic> _history = [];
  bool _loading = false;

  final WsService _wsService = WsService();

  List<Map<String, dynamic>> get zones => _zones;
  Map<int, String> get spotStatuses => _spotStatuses;
  int? get mySpotId => _mySpotId;
  DateTime? get myStartTime => _myStartTime;
  Map<String, dynamic>? get stats => _stats;
  List<dynamic> get history => _history;
  bool get loading => _loading;

  void init() {
    _wsService.connect();
    _wsService.stream.listen((data) {
      final spotId = data['spot_id'] as int?;
      final type = data['type'];
      if (spotId != null) {
        _spotStatuses[spotId] = (type == 0) ? 'OCCUPIED' : 'FREE';

        if (type == 1 && spotId == _mySpotId) {
          final source = data['source'];
          if (source != 'USER') {
            _mySpotId = null;
            _myStartTime = null;
          }
        }
        notifyListeners();     // перерисовать карту немедленно
        _refreshStats();       // обновить статистику с сервера
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
    if (data != null) {
      _mySpotId = data['spot_id'] as int?;
      final startStr = data['start_time'] as String?;
      if (startStr != null) {
        _myStartTime = DateTime.tryParse(startStr);
      }
    } else {
      _mySpotId = null;
      _myStartTime = null;
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

  Future<bool> reserveSpot(int spotId) async {
    final ok = await ApiService.reserveSpot(spotId);
    if (ok) {
      _mySpotId = spotId;
      _myStartTime = DateTime.now();
      _spotStatuses[spotId] = 'OCCUPIED';
      await loadStats();
      await loadHistory();
      notifyListeners();
    }
    return ok;
  }

  Future<bool> releaseSpot(int spotId) async {
    final ok = await ApiService.releaseSpot(spotId);
    if (ok) {
      _mySpotId = null;
      _myStartTime = null;
      _spotStatuses[spotId] = 'FREE';
      await loadStats();
      await loadHistory();
      notifyListeners();
    }
    return ok;
  }

  String getSpotStatus(int spotId) {
    return _spotStatuses[spotId] ?? 'FREE';
  }

  @override
  void dispose() {
    _wsService.dispose();
    super.dispose();
  }
}