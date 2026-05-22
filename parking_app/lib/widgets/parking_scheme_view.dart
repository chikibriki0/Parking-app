import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Один слот на схеме.
class SchemeSpot {
  final int spotId;
  final int number;
  final String status; // FREE | OCCUPIED
  final bool isMine;

  const SchemeSpot({
    required this.spotId,
    required this.number,
    required this.status,
    required this.isMine,
  });
}

/// ParkingSchemeView — схема парковки «вид сверху».
///
/// Парковка делится на секции по 8 машиномест (4×2). Между рядами секций —
/// горизонтальные проезды, между секциями в одном ряду — пробел. Все места
/// реальные (из БД), декоративных пустых слотов нет.
///
/// При 48 машиноместах = 6 секций (3 ряда × 2 колонки) — как на референсе.
/// При меньшем числе мест количество секций сокращается, и пустые «слоты»
/// в последней секции не рисуются.
class ParkingSchemeView extends StatelessWidget {
  final List<SchemeSpot> spots;

  /// Callback при тапе на машиноместо. Если null — некликабельно (превью).
  final ValueChanged<SchemeSpot>? onTap;

  /// Кол-во машиномест в секции. 4 в ряду × 2 ряда = 8.
  static const int spotsPerSection = 8;
  static const int sectionsPerRow = 2;
  static const int colsInSection = 4;

  const ParkingSchemeView({
    super.key,
    required this.spots,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Бьём места на секции по 8.
    final sections = <List<SchemeSpot>>[];
    for (int i = 0; i < spots.length; i += spotsPerSection) {
      sections.add(spots.sublist(
        i,
        i + spotsPerSection > spots.length ? spots.length : i + spotsPerSection,
      ));
    }

    // Группируем секции по два — на каждый «ряд» парковки.
    final sectionRows = <List<List<SchemeSpot>>>[];
    for (int i = 0; i < sections.length; i += sectionsPerRow) {
      sectionRows.add(sections.sublist(
        i,
        i + sectionsPerRow > sections.length
            ? sections.length
            : i + sectionsPerRow,
      ));
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFD9DEE4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (int row = 0; row < sectionRows.length; row++) ...[
            Row(
              children: [
                for (int c = 0; c < sectionsPerRow; c++) ...[
                  Expanded(
                    child: c < sectionRows[row].length
                        ? _section(sectionRows[row][c])
                        : const SizedBox.shrink(),
                  ),
                  if (c < sectionsPerRow - 1) const SizedBox(width: 14),
                ],
              ],
            ),
            if (row < sectionRows.length - 1) const _LaneArrows(),
          ],
        ],
      ),
    );
  }

  /// Секция = белая «плита» парковки с 4×2 машиноместами.
  Widget _section(List<SchemeSpot> sectionSpots) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: _rowChildren(sectionSpots, 0, colsInSection),
          ),
          const SizedBox(height: 5),
          Row(
            children: _rowChildren(sectionSpots, colsInSection, colsInSection),
          ),
        ],
      ),
    );
  }

  List<Widget> _rowChildren(List<SchemeSpot> spots, int start, int count) {
    final out = <Widget>[];
    for (int i = 0; i < count; i++) {
      final idx = start + i;
      final slot = idx < spots.length ? _slot(spots[idx]) : const _EmptySlot();
      out.add(Expanded(child: slot));
      if (i < count - 1) out.add(const SizedBox(width: 4));
    }
    return out;
  }

  Widget _slot(SchemeSpot s) {
    Color color;
    if (s.isMine) {
      color = AppTheme.primary;
    } else if (s.status == 'OCCUPIED') {
      color = const Color(0xFFB4B8C0);
    } else {
      color = AppTheme.success;
    }

    return GestureDetector(
      onTap: onTap == null ? null : () => onTap!(s),
      child: AspectRatio(
        aspectRatio: 0.7,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ),
    );
  }
}

/// Пустой слот в неполной секции (например, если мест меньше 8).
class _EmptySlot extends StatelessWidget {
  const _EmptySlot();
  @override
  Widget build(BuildContext context) =>
      const AspectRatio(aspectRatio: 0.7, child: SizedBox());
}

/// Горизонтальная полоса проезда между рядами секций — со стрелочкой вниз.
class _LaneArrows extends StatelessWidget {
  const _LaneArrows();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Icon(
          Icons.keyboard_double_arrow_down_rounded,
          color: Color(0xFF7F858E),
          size: 22,
        ),
      ),
    );
  }
}

/// Легенда — используется на full-screen экране схемы.
class ParkingSchemeLegend extends StatelessWidget {
  const ParkingSchemeLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _legend(AppTheme.success, 'Свободно'),
        const SizedBox(width: 16),
        _legend(const Color(0xFFB4B8C0), 'Занято'),
        const SizedBox(width: 16),
        _legend(AppTheme.primary, 'Вы выбрали'),
      ],
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14, height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            )),
      ],
    );
  }
}
