import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/parking_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/spot_widget.dart';
import '../widgets/stats_bar.dart';
import '../widgets/my_parking_card.dart';
import 'history_screen.dart';
import 'admin_screen.dart';
import 'login_screen.dart';

class ParkingMapScreen extends StatefulWidget {
  const ParkingMapScreen({super.key});

  @override
  State<ParkingMapScreen> createState() => _ParkingMapScreenState();
}

class _ParkingMapScreenState extends State<ParkingMapScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    final parking = context.read<ParkingProvider>();
    parking.init();
    // Периодическое обновление статистики
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        parking.loadStats();
        parking.loadMyParking();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleSpotTap(
      BuildContext context, int spotId, String zoneName, int spotNumber) async {
    final parking = context.read<ParkingProvider>();
    final status = parking.getSpotStatus(spotId);
    final mySpot = parking.mySpotId;

    // Нажали на своё место — освобождаем
    if (spotId == mySpot) {
      final confirmed = await _showConfirmDialog(
        context,
        'Освободить место?',
        'Место $spotNumber (Зона $zoneName) будет освобождено.',
        confirmLabel: 'Освободить',
        confirmColor: AppTheme.danger,
      );
      if (confirmed == true) {
        final ok = await parking.releaseSpot(spotId);
        if (mounted) {
          _showSnack(
              context, ok ? 'Место освобождено' : 'Ошибка', ok ? AppTheme.success : AppTheme.danger);
        }
      }
      return;
    }

    // Занятое чужое место
    if (status == 'OCCUPIED') {
      _showSnack(context, 'Это место уже занято', AppTheme.warning);
      return;
    }

    // Свободное место
    if (status == 'FREE') {
      if (mySpot != null) {
        // Уже есть место — предлагаем переключиться
        final confirmed = await _showConfirmDialog(
          context,
          'Сменить место?',
          'Ваше текущее место будет освобождено. Забронировать место $spotNumber (Зона $zoneName)?',
          confirmLabel: 'Сменить',
        );
        if (confirmed != true) return;
        await parking.releaseSpot(mySpot);
      }

      final ok = await parking.reserveSpot(spotId);
      if (mounted) {
        _showSnack(
          context,
          ok ? 'Место $spotNumber (Зона $zoneName) забронировано' : 'Ошибка бронирования',
          ok ? AppTheme.success : AppTheme.danger,
        );
      }
    }
  }

  Future<bool?> _showConfirmDialog(
    BuildContext context,
    String title,
    String content, {
    String confirmLabel = 'Подтвердить',
    Color confirmColor = AppTheme.primary,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        content: Text(content,
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: confirmColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  void _showSnack(BuildContext context, String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final parking = context.watch<ParkingProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.local_parking_rounded,
                color: AppTheme.primary, size: 28),
            SizedBox(width: 8),
            Text('Parking Service'),
          ],
        ),
        actions: [
          if (auth.isAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              tooltip: 'Админ-панель',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminScreen()),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'История',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Выйти',
            onPressed: () async {
              await auth.logout();
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: parking.loading && parking.zones.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppTheme.primary),
                  SizedBox(height: 16),
                  Text('Загружаем парковку...',
                      style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            )
          : RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: parking.loadAll,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Статистика
                  if (parking.stats != null)
                    StatsBar(stats: parking.stats!),
                  const SizedBox(height: 16),

                  // Моё место
                  if (parking.mySpotId != null)
                    MyParkingCard(
                      parking: parking,
                      onRelease: () => _handleSpotTap(
                        context,
                        parking.mySpotId!,
                        _getZoneName(parking, parking.mySpotId!),
                        _getSpotNumber(parking, parking.mySpotId!),
                      ),
                    ),

                  if (parking.mySpotId != null) const SizedBox(height: 16),

                  // Легенда
                  _buildLegend(),
                  const SizedBox(height: 16),

                  // Зоны
                  ...parking.zones.map((zone) => _buildZoneCard(
                        context,
                        zone,
                        parking,
                      )),
                ],
              ),
            ),
    );
  }

  String _getZoneName(ParkingProvider parking, int spotId) {
    for (final zone in parking.zones) {
      final spots = zone['spots'] as List? ?? [];
      for (final spot in spots) {
        if (spot['id'] == spotId) return zone['name'] as String? ?? '';
      }
    }
    return '';
  }

  int _getSpotNumber(ParkingProvider parking, int spotId) {
    for (final zone in parking.zones) {
      final spots = zone['spots'] as List? ?? [];
      for (final spot in spots) {
        if (spot['id'] == spotId) return spot['spot_number'] as int? ?? 0;
      }
    }
    return 0;
  }

  Widget _buildLegend() {
    return Row(
      children: [
        _legendItem(AppTheme.success, 'Свободно'),
        const SizedBox(width: 16),
        _legendItem(AppTheme.danger, 'Занято'),
        const SizedBox(width: 16),
        _legendItem(AppTheme.mySpot, 'Моё место'),
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 13, color: AppTheme.textSecondary)),
      ],
    );
  }

  Widget _buildZoneCard(
    BuildContext context,
    Map<String, dynamic> zone,
    ParkingProvider parking,
  ) {
    final zoneName = zone['name'] as String? ?? '';
    final spots = zone['spots'] as List? ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Зона $zoneName',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${spots.length} мест',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: spots.map<Widget>((spot) {
                final spotId = spot['id'] as int;
                final spotNumber = spot['spot_number'] as int;
                final status = parking.getSpotStatus(spotId);
                final isMySpot = parking.mySpotId == spotId;

                return SpotWidget(
                  spotNumber: spotNumber,
                  status: status,
                  isMySpot: isMySpot,
                  onTap: () => _handleSpotTap(
                      context, spotId, zoneName, spotNumber),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}