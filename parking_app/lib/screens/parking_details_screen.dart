import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../model/parking_location.dart';
import '../providers/parking_provider.dart';
import '../services/favorites_service.dart';
import '../services/navigation_service.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/countdown_text.dart';
import '../widgets/extension_picker.dart';
import '../widgets/parking_scheme_view.dart';
import '../widgets/result_dialog.dart';
import 'booking_screen.dart';
import 'parking_scheme_screen.dart';

/// ParkingDetailsScreen — экран одной парковки (одной зоны).
/// Показывает фото, инфу и сетку из 5 мест выбранной зоны.
class ParkingDetailsScreen extends StatefulWidget {
  final ParkingLocation parking;
  const ParkingDetailsScreen({super.key, required this.parking});

  @override
  State<ParkingDetailsScreen> createState() => _ParkingDetailsScreenState();
}

class _ParkingDetailsScreenState extends State<ParkingDetailsScreen> {
  Timer? _refreshTimer;
  Timer? _tickTimer;
  int? _selectedSpotId;
  int? _warnedSpotId; // чтобы не показывать «истекает» каждую секунду

  @override
  void initState() {
    super.initState();
    final parking = context.read<ParkingProvider>();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        parking.loadMap();
        parking.loadStats();
        parking.loadMyParking();
      }
    });
    // Тикер только для проверки «время скоро истечёт». Каждые 10 секунд —
    // этого хватает (предупреждение всё равно показывается за 20+ секунд
    // до конца). Сам обратный отсчёт в action bar обновляется отдельным
    // виджетом CountdownText (он ребилдит только себя).
    _tickTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      _maybeWarnExpiring();
    });
  }

  void _maybeWarnExpiring() {
    final parking = context.read<ParkingProvider>();
    final spotId = parking.mySpotId;
    final expires = parking.myExpiresAt;
    final start = parking.myStartTime;
    if (spotId == null || expires == null || start == null) return;
    if (_warnedSpotId == spotId) return;

    final left = expires.difference(DateTime.now());
    final total = expires.difference(start);
    // Окно «истекает скоро»: 1/5 от длительности, но в диапазоне 20с..15мин.
    var warnSeconds = total.inSeconds ~/ 5;
    if (warnSeconds < 20) warnSeconds = 20;
    if (warnSeconds > 15 * 60) warnSeconds = 15 * 60;
    final warnAt = Duration(seconds: warnSeconds);
    if (left <= warnAt && left > Duration.zero) {
      _warnedSpotId = spotId;
      _showExpiringSoon(left);
    }
  }

  Future<void> _showExpiringSoon(Duration left) async {
    final minutesLeft = left.inMinutes;
    final humanLeft = minutesLeft >= 1
        ? '$minutesLeft мин'
        : '${left.inSeconds} сек';
    await showResultDialog(
      context,
      kind: ResultDialogKind.warning,
      title: 'Время парковки истекает',
      message: 'Через $humanLeft ваша бронь будет автоматически завершена. '
          'Подумайте об освобождении места или продлите визит.',
      primaryLabel: 'Хорошо',
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tickTimer?.cancel();
    super.dispose();
  }

  /// Места только этой зоны, отсортированные по spot_number.
  List<Map<String, dynamic>> _zoneSpots(ParkingProvider parking) {
    for (final zone in parking.zones) {
      if ((zone['name'] as String? ?? '') == widget.parking.zoneName) {
        final list = ((zone['spots'] as List?) ?? [])
            .map((s) => Map<String, dynamic>.from(s as Map))
            .toList();
        list.sort((a, b) =>
            (a['spot_number'] as int).compareTo(b['spot_number'] as int));
        return list;
      }
    }
    return [];
  }

  void _goToBooking() {
    final parking = context.read<ParkingProvider>();
    final spotId = _selectedSpotId;
    if (spotId == null) return;
    final spotNumber = _zoneSpots(parking).firstWhere(
        (s) => s['id'] == spotId,
        orElse: () => {'spot_number': spotId})['spot_number'] as int;

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BookingScreen(
        parking: widget.parking,
        spotId: spotId,
        spotNumber: spotNumber,
      ),
    ));
  }

  Future<void> _extendMine() async {
    final parking = context.read<ParkingProvider>();
    final option = await showExtensionPicker(
      context,
      currentExpires: parking.myExpiresAt,
    );
    if (option == null || !mounted) return;

    final result = await parking.extendParking(duration: option.duration);
    if (!mounted) return;

    if (result['success'] == true) {
      _warnedSpotId = null; // сбросить «истекает» — теперь не истекает
      final newExpires = parking.myExpiresAt;
      final endStr = newExpires != null
          ? '${newExpires.hour.toString().padLeft(2, '0')}:${newExpires.minute.toString().padLeft(2, '0')}'
          : '—';
      await showResultDialog(
        context,
        kind: ResultDialogKind.success,
        title: 'Парковка продлена',
        message: 'Бронь продлена ${option.label.toLowerCase()}. Новое окончание: $endStr.',
        primaryLabel: 'Хорошо',
      );
    } else {
      await showResultDialog(
        context,
        kind: ResultDialogKind.error,
        title: 'Не удалось продлить',
        message: (result['message'] as String?) ?? 'Попробуйте ещё раз.',
        primaryLabel: 'Понятно',
      );
    }
  }

  Future<void> _releaseMine() async {
    final parking = context.read<ParkingProvider>();
    final spotId = parking.mySpotId;
    if (spotId == null) return;

    final spotNumber = _zoneSpots(parking).firstWhere(
        (s) => s['id'] == spotId,
        orElse: () => {'spot_number': spotId})['spot_number'] as int;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Освободить место?',
      message: 'Место №$spotNumber будет освобождено. '
          'Эту парковку всегда можно начать заново.',
      actionLabel: 'Освободить',
      actionColor: AppTheme.danger,
      actionIcon: Icons.logout_rounded,
    );
    if (confirmed != true || !mounted) return;

    final result = await parking.releaseSpot(spotId);
    if (!mounted) return;

    if (result['success'] == true) {
      await showResultDialog(
        context,
        kind: ResultDialogKind.success,
        title: 'Место освобождено',
        message: 'Вы успешно завершили парковку. Спасибо, что пользуетесь сервисом!',
        primaryLabel: 'На главную',
      );
    } else {
      await showResultDialog(
        context,
        kind: ResultDialogKind.error,
        title: 'Не удалось освободить',
        message: (result['message'] as String?) ?? 'Попробуйте ещё раз.',
        primaryLabel: 'Понятно',
      );
    }
  }

  String _formatTime(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  void _snack(String text, Color color) {
    // Поднимаем снэкбар выше action bar (action bar ~90px),
    // и оставляем плавающее поведение в стиле iOS-toast.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      backgroundColor: color,
      duration: const Duration(seconds: 2),
      content: Text(
        text,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final parking = context.watch<ParkingProvider>();
    final spots = _zoneSpots(parking);
    final free = spots.where((s) => s['status'] == 'FREE').length;
    final total = spots.length;
    final mySpotId = parking.mySpotId;
    final mySpotInThisZone =
        mySpotId != null && spots.any((s) => s['id'] == mySpotId);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.parking.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Consumer<FavoritesService>(
            builder: (_, favs, __) {
              final isFav = favs.contains(widget.parking.title);
              return IconButton(
                icon: Icon(isFav ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                    color: isFav ? AppTheme.primary : null),
                tooltip: isFav ? 'Убрать из избранного' : 'В избранное',
                onPressed: () => favs.toggle(widget.parking.title),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.navigation_rounded),
            tooltip: 'Маршрут до парковки',
            onPressed: () => NavigationService.openRoute(
              context: context,
              lat: widget.parking.location.latitude,
              lon: widget.parking.location.longitude,
              label: widget.parking.title,
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _photoHeader(free: free, total: total),
                  const SizedBox(height: 16),
                  _detailsCard(),
                  const SizedBox(height: 24),
                  _schemePreview(spots, mySpotId),
                  const SizedBox(height: 14),
                  const ParkingSchemeLegend(),
                ],
              ),
            ),
            _actionBar(mySpotInThisZone ? mySpotId : null, spots),
          ],
        ),
      ),
    );
  }

  Widget _photoHeader({required int free, required int total}) {
    // Палитра подбирается по zoneId, чтобы у каждой парковки был свой цвет.
    final palettes = [
      [AppTheme.primary, AppTheme.primaryDark],
      [const Color(0xFF34C759), const Color(0xFF1F8F3F)],
      [const Color(0xFFFF9F0A), const Color(0xFFD17600)],
      [const Color(0xFFAF52DE), const Color(0xFF6B2D8F)],
      [const Color(0xFFFF3B30), const Color(0xFFB42820)],
    ];
    final p = palettes[widget.parking.zoneId.abs() % palettes.length];

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 200,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Градиентный «баннер» — встроенная графика, без HTTP-запросов.
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [p[0], p[1]],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            // Декоративные круги для глубины.
            Positioned(
              right: -30, top: -30,
              child: Container(
                width: 160, height: 160,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              left: -40, bottom: -40,
              child: Container(
                width: 140, height: 140,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // Большая буква P по центру
            const Center(
              child: Icon(Icons.local_parking_rounded,
                  size: 110, color: Colors.white24),
            ),
            // Лёгкое затемнение снизу — чтобы бейджи читались.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black26],
                ),
              ),
            ),
            Positioned(
              left: 12, bottom: 12,
              child: Row(
                children: [
                  _floatingBadge(
                    icon: Icons.check_circle_rounded,
                    iconColor: AppTheme.success,
                    text: '$free свободно',
                  ),
                  const SizedBox(width: 8),
                  _floatingBadge(
                    icon: null,
                    iconColor: AppTheme.textPrimary,
                    text: 'Всего $total мест',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _floatingBadge(
      {IconData? icon, required Color iconColor, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  /// Интерактивная схема парковки. Тап на свободное место — выбор;
  /// кнопка «Развернуть» открывает полноэкранную версию.
  Widget _schemePreview(List<Map<String, dynamic>> spots, int? mySpotId) {
    final parking = context.read<ParkingProvider>();
    final schemeSpots = spots.map((s) {
      final id = s['id'] as int;
      // Берём актуальный статус из _spotStatuses (он обновляется WS),
      // а не из закэшированных zones.
      final liveStatus = parking.getSpotStatus(id);
      return SchemeSpot(
        spotId: id,
        number: s['spot_number'] as int,
        status: liveStatus,
        // Синим красим либо реальную свою бронь, либо предварительный
        // выбор (но не оба сразу — приоритет у реальной брони).
        isMine: id == mySpotId || (mySpotId == null && id == _selectedSpotId),
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Схема парковки',
                style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ParkingSchemeScreen(
                    parking: widget.parking,
                    spots: schemeSpots,
                  ),
                ),
              ),
              child: const Text('Развернуть'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ParkingSchemeView(
          spots: schemeSpots,
          onTap: (s) {
            // 1) Занятое чужое место — всегда тихий игнор.
            if (s.status == 'OCCUPIED' && s.spotId != mySpotId) {
              return;
            }
            // 2) Свободное место, но у меня уже есть активная бронь —
            // подсказываем, что надо освободить старую.
            if (mySpotId != null && s.spotId != mySpotId) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                backgroundColor: AppTheme.warning,
                duration: const Duration(seconds: 2),
                content: const Text(
                  'Сначала освободите текущее место',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ));
              return;
            }
            // 3) Свободное + брони нет — выбираем для бронирования.
            if (s.status == 'FREE') {
              setState(() => _selectedSpotId = s.spotId);
            }
          },
        ),
      ],
    );
  }

  Widget _detailsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          _detailRow(
            icon: Icons.place_rounded,
            iconColor: AppTheme.primary,
            title: widget.parking.address,
            subtitle: widget.parking.title,
          ),
          const _DividerInset(),
          _detailRow(
            icon: Icons.schedule_rounded,
            iconColor: AppTheme.warning,
            title: 'Круглосуточно',
            subtitle: 'Режим работы',
          ),
          const _DividerInset(),
          _detailRow(
            icon: Icons.payments_rounded,
            iconColor: AppTheme.success,
            title: '${widget.parking.tariffRubPerHour} ₽ / час',
            subtitle:
                'Первые ${widget.parking.freeFirstMinutes} мин бесплатно',
          ),
        ],
      ),
    );
  }

  Widget _detailRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _spotsGrid(List<Map<String, dynamic>> spots, int? mySpotId) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: spots.map((spot) {
        final spotId = spot['id'] as int;
        final number = spot['spot_number'] as int;
        final status = spot['status'] as String? ?? 'FREE';
        final isMine = spotId == mySpotId;
        final isSelected = spotId == _selectedSpotId;
        final isFree = status == 'FREE';
        return _SpotCard(
          number: number,
          status: status,
          isMine: isMine,
          isSelected: isSelected,
          onTap: () {
            if (isMine) return;
            if (!isFree) {
              _snack('Место №$number сейчас занято', AppTheme.warning);
              return;
            }
            setState(() => _selectedSpotId = spotId);
          },
        );
      }).toList(),
    );
  }

  Widget _legend() {
    return Row(
      children: [
        _legendDot(AppTheme.success, 'Свободно'),
        const SizedBox(width: 14),
        _legendDot(AppTheme.textSecondary, 'Занято'),
        const SizedBox(width: 14),
        _legendDot(AppTheme.primary, 'Моё место'),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style:
                const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
      ],
    );
  }

  Widget _actionBar(int? mySpotInThisZone, List<Map<String, dynamic>> spots) {
    final parking = context.read<ParkingProvider>();
    if (mySpotInThisZone != null) {
      final spotNumber = spots.firstWhere(
        (s) => s['id'] == mySpotInThisZone,
        orElse: () => {'spot_number': mySpotInThisZone},
      )['spot_number'];
      final expires = parking.myExpiresAt;
      return _bottomBar(
        infoTitle: 'Моё место №$spotNumber',
        infoSubtitle: expires == null
            ? const Text('Сейчас активно',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary))
            : Row(
                children: [
                  const Text('Осталось ',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                  CountdownText(
                    expires: expires,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
        button: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // «Продлить» — квадратная кнопка с одной иконкой «+».
            // На узких экранах (Pocophone F1) полноценный текст «Продлить»
            // вместе с «Освободить» съедал слишком много места, и
            // счётчик обратного отсчёта уходил под кнопку. Иконочный
            // вариант экономит ~80 пикселей и решает наложение.
            SizedBox(
              width: 50,
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: EdgeInsets.zero,
                ),
                onPressed: _extendMine,
                child: const Icon(Icons.add_rounded, size: 26),
              ),
            ),
            const SizedBox(width: 8),
            // «Освободить» — красная
            SizedBox(
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.danger,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: _releaseMine,
                child: const Text('Освободить'),
              ),
            ),
          ],
        ),
      );
    }

    if (_selectedSpotId == null) {
      return _bottomBar(
        infoTitle: 'Выберите место',
        infoSubtitle: const Text(
          'Тапните на любое свободное',
          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        button: const SizedBox.shrink(),
      );
    }

    final spotNumber = spots.firstWhere(
      (s) => s['id'] == _selectedSpotId,
      orElse: () => {'spot_number': _selectedSpotId},
    )['spot_number'];

    return _bottomBar(
      infoTitle: 'Место №$spotNumber',
      infoSubtitle: const Text(
        'Готово к бронированию',
        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
      ),
      button: FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size(160, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: _goToBooking,
        child: const Text('Забронировать'),
      ),
    );
  }

  Widget _bottomBar({
    required String infoTitle,
    required Widget infoSubtitle,
    required Widget button,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: const Border(
            top: BorderSide(color: AppTheme.separator, width: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(infoTitle,
                      style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700,
                      )),
                  const SizedBox(height: 2),
                  infoSubtitle,
                ],
              ),
            ),
            const SizedBox(width: 12),
            button,
          ],
        ),
      ),
    );
  }
}

class _SpotCard extends StatelessWidget {
  final int number;
  final String status;
  final bool isMine;
  final bool isSelected;
  final VoidCallback onTap;

  const _SpotCard({
    required this.number,
    required this.status,
    required this.isMine,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isFree = status == 'FREE';
    final isOccupied = status == 'OCCUPIED' && !isMine;

    final bg = isMine
        ? AppTheme.primary.withOpacity(0.12)
        : Theme.of(context).colorScheme.surface;
    final border = isSelected
        ? AppTheme.primary
        : isMine
            ? AppTheme.primary
            : AppTheme.separator;
    final numberColor = isMine
        ? AppTheme.primary
        : (isOccupied ? AppTheme.textSecondary : AppTheme.textPrimary);
    final dotColor = isMine
        ? AppTheme.primary
        : (isFree ? AppTheme.success : AppTheme.textSecondary);

    return SizedBox(
      width: 64,
      height: 64,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: border,
              width: isSelected || isMine ? 2 : 0.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$number',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: numberColor,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 6, height: 6,
                decoration:
                    BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DividerInset extends StatelessWidget {
  const _DividerInset();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 66),
      child: Divider(height: 0.5),
    );
  }
}
