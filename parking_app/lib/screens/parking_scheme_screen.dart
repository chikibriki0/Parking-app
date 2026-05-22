import 'package:flutter/material.dart';

import '../model/parking_location.dart';
import '../widgets/parking_scheme_view.dart';
import 'booking_screen.dart';

/// Полноэкранная схема парковки. Позволяет тапнуть на свободное место и
/// перейти к экрану бронирования.
class ParkingSchemeScreen extends StatefulWidget {
  final ParkingLocation parking;
  final List<SchemeSpot> spots;

  const ParkingSchemeScreen({
    super.key,
    required this.parking,
    required this.spots,
  });

  @override
  State<ParkingSchemeScreen> createState() => _ParkingSchemeScreenState();
}

class _ParkingSchemeScreenState extends State<ParkingSchemeScreen> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final spots = widget.spots.map((s) {
      // Помечаем выделенное в превью пользователем
      if (s.spotId == _selected) {
        return SchemeSpot(
          spotId: s.spotId,
          number: s.number,
          status: s.status,
          isMine: true, // переиспользуем «синий» цвет для «вы выбрали»
        );
      }
      return s;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Схема парковки')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Center(
                  child: ParkingSchemeView(
                    spots: spots,
                    onTap: (s) {
                      if (s.status == 'OCCUPIED' && !s.isMine) return;
                      setState(() => _selected = s.spotId);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const ParkingSchemeLegend(),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _selected == null
                      ? null
                      : () {
                          final chosen = widget.spots
                              .firstWhere((s) => s.spotId == _selected);
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => BookingScreen(
                                parking: widget.parking,
                                spotId: chosen.spotId,
                                spotNumber: chosen.number,
                              ),
                            ),
                          );
                        },
                  child: const Text('Выбрать место'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
