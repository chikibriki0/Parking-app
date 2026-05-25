import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Автомобиль пользователя. Для прототипа храним локально, на сервер
/// ничего не отправляем — в проде это место займёт endpoint /me/cars.
class UserCar {
  /// Российский гос-номер автомобиля в формате «А 777 АА 77» (без пробелов
  /// в хранении — добавляются только при показе). Проверяется регуляркой
  /// при сохранении в форме.
  final String plate;

  /// Серия и номер СТС (свидетельство о регистрации ТС), 10 знаков:
  /// 2 цифры серии + 2 буквы + 6 цифр. Например: «77АА123456».
  final String sts;

  /// Является ли «основным» автомобилем (помечен бейджем в профиле).
  final bool primary;

  const UserCar({
    required this.plate,
    required this.sts,
    this.primary = false,
  });

  UserCar copyWith({String? plate, String? sts, bool? primary}) => UserCar(
        plate: plate ?? this.plate,
        sts: sts ?? this.sts,
        primary: primary ?? this.primary,
      );

  Map<String, dynamic> toJson() => {
        'plate': plate,
        'sts': sts,
        'primary': primary,
      };

  factory UserCar.fromJson(Map<String, dynamic> json) => UserCar(
        plate: json['plate'] as String,
        sts: json['sts'] as String,
        primary: json['primary'] as bool? ?? false,
      );

  /// Форматирование номера для отображения: «А777АА77» → «А 777 АА 77».
  /// Если не сматчился по российскому шаблону — возвращаем как есть.
  String get displayPlate {
    final m = RegExp(r'^([А-ЯA-Z])(\d{3})([А-ЯA-Z]{2})(\d{2,3})$')
        .firstMatch(plate);
    if (m == null) return plate;
    return '${m[1]} ${m[2]} ${m[3]} ${m[4]}';
  }

  /// Форматирование СТС: «77АА123456» → «77 АА 123456».
  String get displaySts {
    final m = RegExp(r'^(\d{2})([А-ЯA-Z]{2})(\d{6})$').firstMatch(sts);
    if (m == null) return sts;
    return '${m[1]} ${m[2]} ${m[3]}';
  }
}

/// CarsService — управление списком автомобилей пользователя.
///
/// Хранение в SharedPreferences под per-user ключом, чтобы у разных
/// аккаунтов на одном устройстве не пересекались машины.
class CarsService extends ChangeNotifier {
  int? _userId;
  List<UserCar> _cars = [];
  bool _loaded = false;

  List<UserCar> get cars => List.unmodifiable(_cars);
  bool get loaded => _loaded;

  String _keyFor(int? userId) =>
      userId == null ? 'cars_guest_v1' : 'cars_u${userId}_v1';

  /// Привязка к пользователю (после login и при checkAuth).
  Future<void> bindUser(int? userId) async {
    _userId = userId;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFor(userId));
    if (raw == null || raw.isEmpty) {
      _cars = [];
    } else {
      try {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        _cars = list.map(UserCar.fromJson).toList();
      } catch (_) {
        _cars = [];
      }
    }
    _loaded = true;
    notifyListeners();
  }

  /// Сброс при logout.
  void clear() {
    _userId = null;
    _cars = [];
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyFor(_userId),
      jsonEncode(_cars.map((c) => c.toJson()).toList()),
    );
  }

  /// Добавить автомобиль. Первый добавленный автоматически становится
  /// «основным».
  Future<void> add(UserCar car) async {
    final isFirst = _cars.isEmpty;
    _cars.add(car.copyWith(primary: isFirst || car.primary));
    if (car.primary && !isFirst) {
      // Сбрасываем «основной» у остальных, оставляем только у нового.
      for (var i = 0; i < _cars.length - 1; i++) {
        if (_cars[i].primary) {
          _cars[i] = _cars[i].copyWith(primary: false);
        }
      }
    }
    await _save();
    notifyListeners();
  }

  Future<void> remove(String plate) async {
    final removed = _cars.firstWhere(
      (c) => c.plate == plate,
      orElse: () => const UserCar(plate: '', sts: ''),
    );
    _cars.removeWhere((c) => c.plate == plate);
    // Если удалили основной — повышаем первый из оставшихся.
    if (removed.primary && _cars.isNotEmpty) {
      _cars[0] = _cars[0].copyWith(primary: true);
    }
    await _save();
    notifyListeners();
  }

  Future<void> setPrimary(String plate) async {
    for (var i = 0; i < _cars.length; i++) {
      _cars[i] = _cars[i].copyWith(primary: _cars[i].plate == plate);
    }
    await _save();
    notifyListeners();
  }

  /// true — если такой номер уже есть в списке. Используется для валидации
  /// формы при добавлении.
  bool hasPlate(String plate) =>
      _cars.any((c) => c.plate.toUpperCase() == plate.toUpperCase());
}
