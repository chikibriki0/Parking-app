import 'dart:async';
import 'package:flutter/material.dart';
import '../providers/parking_provider.dart';
import '../theme/app_theme.dart';

class MyParkingCard extends StatefulWidget {
  final ParkingProvider parking;
  final VoidCallback onRelease;

  const MyParkingCard({
    super.key,
    required this.parking,
    required this.onRelease,
  });

  @override
  State<MyParkingCard> createState() => _MyParkingCardState();
}

class _MyParkingCardState extends State<MyParkingCard> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.parking.myStartTime != null) {
        setState(() {
          _elapsed = DateTime.now().difference(widget.parking.myStartTime!);
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatElapsed() {
    final h = _elapsed.inHours;
    final m = _elapsed.inMinutes % 60;
    final s = _elapsed.inSeconds % 60;

    final hStr = h.toString().padLeft(2, '0');
    final mStr = m.toString().padLeft(2, '0');
    final sStr = s.toString().padLeft(2, '0');

    return '$hStr:$mStr:$sStr';
  }

  String _getSpotInfo() {
    final parking = widget.parking;
    final spotId = parking.mySpotId;
    if (spotId == null) return '';

    for (final zone in parking.zones) {
      final spots = zone['spots'] as List? ?? [];
      for (final spot in spots) {
        if (spot['id'] == spotId) {
          return 'Место ${spot['spot_number']} · Зона ${zone['name']}';
        }
      }
    }
    return 'Место #$spotId';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primary, AppTheme.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.directions_car_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ваше место',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    _getSpotInfo(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined,
                          color: Colors.white70, size: 15),
                      const SizedBox(width: 4),
                      Text(
                        _formatElapsed(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: widget.onRelease,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.danger,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13),
              ),
              child: const Text('Выехать'),
            ),
          ],
        ),
      ),
    );
  }
}