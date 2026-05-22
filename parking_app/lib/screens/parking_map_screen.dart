import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/parking_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/spot_widget.dart';
import '../widgets/stats_bar.dart';
import '../widgets/my_parking_card.dart';
import 'admin_screen.dart';

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
    // Провайдер уже инициализирован HomeScreen — здесь только таймер
    // периодической синхронизации как страховка для WebSocket.
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        parking.loadMap();
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
      final confirmed = await _confirm(
        context,
        title: 'Освободить место?',
        message: 'Место $spotNumber в зоне $zoneName будет освобождено. '
            'Эту парковку всегда можно начать заново.',
        actionLabel: 'Освободить',
        actionColor: AppTheme.danger,
        actionIcon: Icons.logout_rounded,
      );
      if (confirmed == true) {
        final result = await parking.releaseSpot(spotId);
        if (mounted) {
          final ok = result['success'] == true;
          _showSnack(
            context,
            ok ? 'Место освобождено' : (result['message'] as String? ?? 'Ошибка'),
            ok ? AppTheme.success : AppTheme.danger,
          );
        }
      }
      return;
    }

    // Занятое чужое место
    if (status == 'OCCUPIED') {
      _showOccupiedSheet(context, zoneName, spotNumber);
      return;
    }

    // Свободное место
    if (status == 'FREE') {
      if (mySpot != null) {
        // Уже есть место — предлагаем переключиться
        final confirmed = await _confirm(
          context,
          title: 'Сменить место?',
          message: 'Текущая бронь будет освобождена и забронировано '
              'место $spotNumber в зоне $zoneName.',
          actionLabel: 'Сменить место',
          actionIcon: Icons.swap_horiz_rounded,
        );
        if (confirmed != true) return;
        final releaseResult = await parking.releaseSpot(mySpot);
        if (releaseResult['success'] != true) {
          if (mounted) {
            _showSnack(
              context,
              releaseResult['message'] as String? ?? 'Не удалось освободить текущее место',
              AppTheme.danger,
            );
          }
          return;
        }
      }

      final result = await parking.reserveSpot(spotId);
      if (mounted) {
        final ok = result['success'] == true;
        _showSnack(
          context,
          ok
              ? 'Место $spotNumber (Зона $zoneName) забронировано'
              : (result['message'] as String? ?? 'Ошибка бронирования'),
          ok ? AppTheme.success : AppTheme.danger,
        );
      }
    }
  }

  // Универсальный диалог в widgets/confirm_dialog.dart — здесь просто прокси.
  Future<bool?> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String actionLabel,
    Color actionColor = AppTheme.primary,
    IconData? actionIcon,
  }) {
    return showConfirmDialog(
      context,
      title: title,
      message: message,
      actionLabel: actionLabel,
      actionColor: actionColor,
      actionIcon: actionIcon,
    );
  }

  void _showOccupiedSheet(BuildContext context, String zoneName, int spotNumber) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // «iOS handle»
            Center(
              child: Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppTheme.separator,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.do_not_disturb_on_rounded,
                      color: AppTheme.danger, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Место $spotNumber · Зона $zoneName',
                          style: Theme.of(ctx).textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text('Сейчас занято',
                          style: Theme.of(ctx).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 18, color: AppTheme.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Дождитесь, пока место освободится — статус обновится автоматически.',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Понятно'),
            ),
          ],
        ),
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
        title: const Text('Парковка'),
        actions: [
          if (auth.isAdmin)
            IconButton(
              icon: const Icon(Icons.shield_outlined),
              tooltip: 'Админ-панель',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminScreen()),
              ),
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Зона $zoneName',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                Text(
                  '${spots.length} мест',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 14),
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