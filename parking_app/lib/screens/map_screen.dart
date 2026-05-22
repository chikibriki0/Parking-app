import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../model/parking_location.dart';
import '../providers/parking_provider.dart';
import '../services/cached_tile_provider.dart';
import '../services/routing_service.dart';
import '../theme/app_theme.dart';
import '../widgets/result_dialog.dart';
import 'parking_details_screen.dart';

/// MapScreen — карта Москвы с pin'ами всех наших парковок (зон).
/// Тап на pin выбирает парковку: меняется шапка и нижняя карточка.
/// Кнопка «Забронировать» открывает экран деталей выбранной зоны.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapController = MapController();
  final _searchController = TextEditingController();
  // null = ничего не выбрано, нижняя карточка скрыта.
  ParkingLocation? _selected;
  String _query = '';
  LatLng? _myLocation;
  bool _resolvingLocation = false;
  StreamSubscription<Position>? _positionSub;

  // Маршрут: список точек от _myLocation до _selected, посчитанный OSRM.
  List<LatLng> _routePoints = const [];
  RouteResult? _routeInfo;
  bool _routeLoading = false;

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
    _initLocation();
    // Страховка к WebSocket. WS — основной канал real-time. Поллинг
    // оставлен только для лёгких эндпоинтов (~50 байт): /stats и
    // /my/parking. /parking/map (большой JSON со 144 местами) не дёргаем,
    // потому что WS уже синхронизирует _zones в провайдере.
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final parking = context.read<ParkingProvider>();
      parking.loadStats();
      parking.loadMyParking();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _positionSub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Запрашивает разрешение и подписывается на координаты пользователя.
  /// Если пользователь отказал — карту это не ломает, просто не будет
  /// «синей точки».
  Future<void> _initLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      _fetchRoute(); // как только знаем «себя» — строим маршрут до выбранной

      // Подписка на обновления. distanceFilter 50м — синяя точка обновляется
      // не чаще раза на 50м движения, что бережёт батарею и убирает лишние
      // ребилды виджета карты.
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 50,
        ),
      ).listen((p) {
        if (!mounted) return;
        setState(() => _myLocation = LatLng(p.latitude, p.longitude));
      });
    } catch (_) {
      // молча — карта без точки тоже работает
    }
  }

  /// Кнопка «найти меня»: центрировать карту на текущем местоположении.
  Future<void> _centerOnMe() async {
    setState(() => _resolvingLocation = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final me = LatLng(pos.latitude, pos.longitude);
      _myLocation = me;
      _mapController.move(me, 16);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Не удалось определить местоположение'),
        ));
      }
    } finally {
      if (mounted) setState(() => _resolvingLocation = false);
    }
  }

  /// Парковки, отфильтрованные поисковым запросом (по названию или адресу).
  List<ParkingLocation> get _filteredParkings {
    if (_query.isEmpty) return kParkings;
    return kParkings.where((p) {
      return p.title.toLowerCase().contains(_query) ||
          p.address.toLowerCase().contains(_query);
    }).toList();
  }

  /// Возвращает количество свободных мест в указанной зоне (из провайдера).
  int _freeInZone(ParkingProvider parking, String zoneName) {
    int free = 0;
    for (final zone in parking.zones) {
      if ((zone['name'] as String? ?? '') == zoneName) {
        for (final spot in (zone['spots'] as List? ?? [])) {
          if ((spot as Map)['status'] == 'FREE') free++;
        }
      }
    }
    return free;
  }

  int _totalInZone(ParkingProvider parking, String zoneName) {
    for (final zone in parking.zones) {
      if ((zone['name'] as String? ?? '') == zoneName) {
        return (zone['spots'] as List? ?? []).length;
      }
    }
    return 0;
  }

  void _selectParking(ParkingLocation p) {
    setState(() {
      _selected = p;
      _routePoints = const [];
      _routeInfo = null;
    });
    _mapController.move(p.location, 15.5);
    _fetchRoute();
  }

  /// Снять выделение — нижняя карточка скрывается, маршрут стирается.
  void _clearSelection() {
    if (_selected == null) return;
    setState(() {
      _selected = null;
      _routePoints = const [];
      _routeInfo = null;
    });
  }

  /// Запрос реального маршрута через OSRM. Если не получилось — линии не будет.
  Future<void> _fetchRoute() async {
    final target = _selected;
    if (_myLocation == null || target == null) return;
    setState(() => _routeLoading = true);
    final result = await RoutingService.driveRoute(
      from: _myLocation!,
      to: target.location,
    );
    if (!mounted) return;
    setState(() {
      _routePoints = result?.points ?? const [];
      _routeInfo = result;
      _routeLoading = false;
    });
  }

  /// Возвращает zoneId, в которой у пользователя сейчас активная бронь
  /// (или null, если брони нет).
  int? _myZoneId(ParkingProvider parking) {
    final spotId = parking.mySpotId;
    if (spotId == null) return null;
    for (final zone in parking.zones) {
      final zoneId = zone['id'] as int? ?? 0;
      for (final spot in (zone['spots'] as List? ?? [])) {
        if ((spot as Map)['id'] == spotId) return zoneId;
      }
    }
    return null;
  }

  // Центр карты по умолчанию — район МЭИ (если ничего не выбрано).
  static const _defaultCenter = LatLng(55.754802, 37.708373);

  @override
  Widget build(BuildContext context) {
    final parking = context.watch<ParkingProvider>();
    final mineZoneId = _myZoneId(parking);
    final selectedFree = _selected == null
        ? 0
        : (_selected!.bookable
            ? _freeInZone(parking, _selected!.zoneName)
            : _selected!.displayFree);
    final selectedTotal = _selected == null
        ? 0
        : (_selected!.bookable
            ? _totalInZone(parking, _selected!.zoneName)
            : _selected!.displayTotal);

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selected?.location ?? _defaultCenter,
              initialZoom: 15,
              minZoom: 5,
              maxZoom: 19,
              // Тап в пустую область карты — снимаем выделение парковки.
              onTap: (_, __) => _clearSelection(),
            ),
            children: [
              // OpenStreetMap mapnik — доступен в РФ без VPN, в отличие от CartoDB.
              // Стиль чуть более «технический», но карта читаемая.
              TileLayer(
                // Если в --dart-define задан MAPTILER_KEY — берём красивые
                // тайлы MapTiler. Иначе откат на OpenStreetMap.
                urlTemplate: AppConfig.mapTileUrl,
                userAgentPackageName: 'ru.mpei.parking_app',
                maxNativeZoom: 19,
                // Скромный буфер — меньше памяти на старых телефонах.
                keepBuffer: 2,
                panBuffer: 1,
                tileProvider: CachedTileProvider(),
              ),
              // Линия маршрута: реальная (по дорогам) от OSRM.
              if (_routePoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 5,
                      color: AppTheme.primary,
                    ),
                  ],
                ),
              // Синяя точка «я» — рисуется через MarkerLayer для красивого пульсара.
              if (_myLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _myLocation!,
                      width: 28, height: 28,
                      child: const _UserLocationDot(),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  for (final p in _filteredParkings)
                    Marker(
                      point: p.location,
                      width: 88, height: 96,
                      alignment: Alignment.topCenter,
                      child: GestureDetector(
                        onTap: () => _selectParking(p),
                        child: _ParkingPin(
                          free: p.bookable
                              ? _freeInZone(parking, p.zoneName)
                              : p.displayFree,
                          total: p.bookable
                              ? _totalInZone(parking, p.zoneName)
                              : p.displayTotal,
                          selected: _selected != null &&
                              _selected!.title == p.title,
                          mine: p.bookable && mineZoneId == p.zoneId,
                        ),
                      ),
                    ),
                ],
              ),
              const RichAttributionWidget(
                showFlutterMapAttribution: false,
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),

          // Плавающая шапка поиска — карта проходит вокруг неё.
          // Без серой подложки, без бордера снизу — белая «капсула» с тенью.
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16, right: 16,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) {
                  if (_filteredParkings.isNotEmpty) {
                    _selectParking(_filteredParkings.first);
                  }
                },
                decoration: InputDecoration(
                  hintText: 'Поиск парковки или адреса',
                  hintStyle: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppTheme.textSecondary, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          color: AppTheme.textSecondary,
                          onPressed: () => _searchController.clear(),
                        ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),

          // Кнопка «найти меня» — справа, над нижней карточкой.
          Positioned(
            right: 16,
            bottom: 280, // над карточкой парковки
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _resolvingLocation ? null : _centerOnMe,
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: _resolvingLocation
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primary,
                          ),
                        )
                      : const Icon(
                          Icons.my_location_rounded,
                          color: AppTheme.primary,
                          size: 24,
                        ),
                ),
              ),
            ),
          ),

          // Нижняя карточка выбранной парковки — только если она выбрана.
          if (_selected != null)
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: _ParkingCard(
                    parking: _selected!,
                    free: selectedFree,
                    total: selectedTotal,
                    routeInfo: _routeInfo,
                    routeLoading: _routeLoading,
                    onClose: _clearSelection,
                    onBook: () async {
                      if (!_selected!.bookable) {
                        await showResultDialog(
                          context,
                          kind: ResultDialogKind.info,
                          title: 'Парковка скоро будет доступна',
                          message:
                              'Эта парковка отображается для демонстрации. '
                              'В ближайшее время мы подключим её к системе и '
                              'добавим возможность бронирования.',
                          primaryLabel: 'Понятно',
                        );
                        return;
                      }
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ParkingDetailsScreen(parking: _selected!),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Синяя пульсирующая точка «вы здесь».
class _UserLocationDot extends StatelessWidget {
  const _UserLocationDot();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Внешний полупрозрачный «пульсар»
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.20),
            shape: BoxShape.circle,
          ),
        ),
        // Белый ободок
        Container(
          width: 16, height: 16,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
        // Синяя сердцевина
        Container(
          width: 12, height: 12,
          decoration: const BoxDecoration(
            color: AppTheme.primary,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

class _ParkingPin extends StatelessWidget {
  final int free;
  final int total;
  final bool selected;
  final bool mine; // у пользователя бронь в этой зоне
  const _ParkingPin({
    required this.free,
    required this.total,
    required this.selected,
    this.mine = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasFree = free > 0;
    // Приоритет цвета: моя бронь > нет мест > есть места.
    final accent = mine
        ? AppTheme.success
        : (hasFree ? AppTheme.primary : AppTheme.danger);
    final scale = selected ? 1.12 : 1.0;
    return AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.28),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
              ),
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'P',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ],
          ),
          Transform.translate(
            offset: const Offset(0, -3),
            child: CustomPaint(
              size: const Size(14, 14),
              painter: _PinTailPainter(color: accent),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -2),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.withOpacity(0.4), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.10),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                '$free/$total',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 22, color: AppTheme.textPrimary),
        ),
      ),
    );
  }
}

class _PinTailPainter extends CustomPainter {
  final Color color;
  _PinTailPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ParkingCard extends StatelessWidget {
  final ParkingLocation parking;
  final int free;
  final int total;
  final RouteResult? routeInfo;
  final bool routeLoading;
  final VoidCallback onBook;
  final VoidCallback onClose;

  const _ParkingCard({
    required this.parking,
    required this.free,
    required this.total,
    required this.routeInfo,
    required this.routeLoading,
    required this.onBook,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final hasFree = free > 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.local_parking_rounded,
                    color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(parking.title,
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(parking.address,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              // Крестик «закрыть карточку»
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20,
                    color: AppTheme.textSecondary),
                onPressed: onClose,
                tooltip: 'Закрыть',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                hasFree ? Icons.directions_car_rounded : Icons.do_not_disturb_on_rounded,
                color: hasFree ? AppTheme.success : AppTheme.danger,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                hasFree ? '$free свободно' : 'Нет мест',
                style: TextStyle(
                  color: hasFree ? AppTheme.success : AppTheme.danger,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 6),
              Text('из $total',
                  style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              if (routeLoading)
                const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.primary,
                  ),
                )
              else if (routeInfo != null) ...[
                const Icon(Icons.navigation_rounded,
                    size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(
                  routeInfo!.humanSummary,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 50,
            child: FilledButton(
              style: parking.bookable
                  ? null
                  : FilledButton.styleFrom(
                      backgroundColor: AppTheme.background,
                      foregroundColor: AppTheme.primary,
                    ),
              onPressed:
                  parking.bookable ? (hasFree ? onBook : null) : onBook,
              child: Text(parking.bookable
                  ? 'Забронировать'
                  : 'Подробнее'),
            ),
          ),
        ],
      ),
    );
  }
}
