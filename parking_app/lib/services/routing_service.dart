import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' show LatLng;

/// RoutingService — строит автомобильный маршрут между двумя точками через
/// публичный OSRM (open-source routing engine, основанный на OpenStreetMap).
///
/// Бесплатный demo-эндпоинт OSM. Запросы кэшируются в памяти процесса —
/// при повторном тапе на тот же pin запрос не делается, маршрут берётся
/// из кэша мгновенно.
class RoutingService {
  static const _base = 'https://router.project-osrm.org';

  /// In-memory кэш. Ключ — округлённые координаты «откуда → куда», чтобы
  /// микро-сдвиги GPS (десяток метров) попадали в тот же бакет.
  static final Map<String, RouteResult> _cache = {};

  static String _keyFor(LatLng from, LatLng to) {
    // Округление до 4 знаков — это ~11 метров. Меньшие движения не влекут
    // повторного похода в сеть.
    String r(double v) => v.toStringAsFixed(4);
    return '${r(from.latitude)},${r(from.longitude)}->'
        '${r(to.latitude)},${r(to.longitude)}';
  }

  /// Запрос маршрута. Возвращает список точек маршрута (для Polyline)
  /// или null, если запрос не удался.
  static Future<RouteResult?> driveRoute({
    required LatLng from,
    required LatLng to,
  }) async {
    final key = _keyFor(from, to);
    final cached = _cache[key];
    if (cached != null) return cached;

    final url = Uri.parse(
      '$_base/route/v1/driving/'
      '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
      '?overview=full&geometries=geojson',
    );
    try {
      final resp = await http.get(url).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      if (json['code'] != 'Ok') return null;
      final routes = json['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;
      final route = routes.first as Map<String, dynamic>;
      final geom = route['geometry'] as Map<String, dynamic>;
      final coords = geom['coordinates'] as List;
      final points = coords
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
      final result = RouteResult(
        points: points,
        distanceMeters: (route['distance'] as num).toDouble(),
        durationSeconds: (route['duration'] as num).toDouble(),
      );
      _cache[key] = result;
      return result;
    } catch (_) {
      return null;
    }
  }
}

class RouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  const RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  /// Удобное форматирование для UI: «1,6 км · 5 мин».
  String get humanSummary {
    final km = distanceMeters / 1000;
    final mins = (durationSeconds / 60).round();
    final kmStr = km < 10 ? km.toStringAsFixed(1).replaceAll('.', ',') : km.toStringAsFixed(0);
    return '$kmStr км · $mins мин';
  }
}
