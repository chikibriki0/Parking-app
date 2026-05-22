import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../model/parking_location.dart';
import '../providers/parking_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/duration_picker.dart';
import '../widgets/result_dialog.dart';

/// BookingScreen — экран подтверждения брони с тарифом и кнопкой «Оплатить».
/// Реальной оплаты нет (ВКР), показывается UI как в коммерческих парковках:
/// тариф, время, авто, способ оплаты, сумма и итоговая кнопка.
class BookingScreen extends StatefulWidget {
  final ParkingLocation parking;
  final int spotId;
  final int spotNumber;

  const BookingScreen({
    super.key,
    required this.parking,
    required this.spotId,
    required this.spotNumber,
  });

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  ParkingDurationOption _duration =
      const ParkingDurationOption('2 часа', Duration(hours: 2));

  String _car = 'А 777 АА 77';
  String _payment = 'VISA •••• 1234';
  bool _processing = false;
  // После успешной оплаты — на этом же экране показываем зелёный
  // success-блок и убираем нижнюю кнопку «Оплатить».
  bool _booked = false;
  int _paidRub = 0;

  String _fmtTime(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Future<void> _pickDuration() async {
    final res = await showDurationPicker(
      context,
      spotNumber: widget.spotNumber,
      initial: _duration,
    );
    if (res != null) setState(() => _duration = res);
  }

  Future<void> _payAndBook() async {
    setState(() => _processing = true);
    final parking = context.read<ParkingProvider>();
    final result =
        await parking.reserveSpot(widget.spotId, duration: _duration.duration);
    if (!mounted) return;

    if (result['success'] == true) {
      setState(() {
        _processing = false;
        _booked = true;
        _paidRub = widget.parking.costRub(_duration.duration);
      });
    } else {
      setState(() => _processing = false);
      await showResultDialog(
        context,
        kind: ResultDialogKind.error,
        title: 'Не удалось забронировать',
        message: (result['message'] as String?) ??
            'Попробуйте другое место или повторите позже.',
        primaryLabel: 'Понятно',
      );
    }
  }

  void _openParking() {
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final end = now.add(_duration.duration);
    final cost = widget.parking.costRub(_duration.duration);

    return Scaffold(
      appBar: AppBar(title: const Text('Бронирование')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _placeHeader(),
                  const SizedBox(height: 16),
                  _rowCard(
                    title: 'Время',
                    valueWidget: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Сегодня, ${_fmtTime(now)} – ${_fmtTime(end)}',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        Text(_duration.label,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    trailingLabel: 'Изменить',
                    onTap: _pickDuration,
                  ),
                  const SizedBox(height: 10),
                  _rowCard(
                    title: 'Тариф',
                    valueWidget: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${widget.parking.tariffRubPerHour} ₽ / час',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        Text(
                          'Первые ${widget.parking.freeFirstMinutes} мин бесплатно',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _rowCard(
                    title: 'К оплате',
                    valueWidget: Text(
                      cost == 0 ? 'Бесплатно' : '$cost ₽',
                      style: TextStyle(
                        color: cost == 0 ? AppTheme.success : AppTheme.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _rowCard(
                    title: 'Автомобиль',
                    valueWidget: Text(_car,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    trailingLabel: 'Изменить',
                    onTap: () => _changeCar(),
                  ),
                  const SizedBox(height: 10),
                  _rowCard(
                    title: 'Способ оплаты',
                    valueWidget: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1F71),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'VISA',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('•••• 1234',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    trailingLabel: 'Изменить',
                    onTap: () => _changePayment(),
                  ),
                  // Зелёный success-блок после успешной оплаты — прямо
                  // на экране, под карточками. Закрывается через
                  // «Перейти к парковке» (popUntil firstRoute).
                  if (_booked) ...[
                    const SizedBox(height: 16),
                    _successCard(),
                  ],
                ],
              ),
            ),
            if (!_booked)
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: const Border(
                    top: BorderSide(color: AppTheme.separator, width: 0.5),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    height: 54,
                    child: FilledButton(
                      onPressed: _processing ? null : _payAndBook,
                      child: _processing
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(cost == 0
                              ? 'Забронировать бесплатно'
                              : 'Оплатить $cost ₽'),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Зелёный success-блок, который появляется в карточечной ленте после
  /// успешной оплаты. По кнопке «Перейти к парковке» возвращаемся на карту.
  Widget _successCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0, right: 0,
            child: InkWell(
              onTap: _openParking,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(15),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.close_rounded,
                    size: 16, color: AppTheme.textSecondary),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.success.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.check_rounded,
                    color: AppTheme.success, size: 32),
              ),
              const SizedBox(height: 14),
              Text(
                'Парковка забронирована!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                _paidRub == 0
                    ? 'Место №${widget.spotNumber} забронировано на ${_duration.label}.'
                        ' Оплата не потребовалась — вы уложились в '
                        'первые ${widget.parking.freeFirstMinutes} мин.'
                    : 'Место №${widget.spotNumber} забронировано на ${_duration.label}.\n'
                        'Списано $_paidRub ₽ с карты $_payment.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _openParking,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Перейти к парковке'),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _placeHeader() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
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
                Text('Место №${widget.spotNumber}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                Text('${widget.parking.title} · Зона ${widget.parking.zoneName}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowCard({
    required String title,
    required Widget valueWidget,
    String? trailingLabel,
    VoidCallback? onTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                valueWidget,
              ],
            ),
          ),
          if (trailingLabel != null)
            TextButton(
              onPressed: onTap,
              child: Text(trailingLabel),
            ),
        ],
      ),
    );
  }

  Future<void> _changeCar() async {
    final cars = ['А 777 АА 77', 'В 111 ВВ 99', 'Е 555 ЕЕ 50'];
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Выберите автомобиль',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 14),
              for (final c in cars)
                ListTile(
                  leading: const Icon(Icons.directions_car_rounded),
                  title: Text(c),
                  trailing: c == _car
                      ? const Icon(Icons.check_rounded, color: AppTheme.primary)
                      : null,
                  onTap: () => Navigator.pop(ctx, c),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null) setState(() => _car = chosen);
  }

  Future<void> _changePayment() async {
    final methods = ['VISA •••• 1234', 'MIR •••• 7788', 'Apple Pay'];
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Способ оплаты',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 14),
              for (final m in methods)
                ListTile(
                  leading: const Icon(Icons.credit_card_rounded),
                  title: Text(m),
                  trailing: m == _payment
                      ? const Icon(Icons.check_rounded, color: AppTheme.primary)
                      : null,
                  onTap: () => Navigator.pop(ctx, m),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null) setState(() => _payment = chosen);
  }
}
