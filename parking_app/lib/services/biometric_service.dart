import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// BiometricService — обёртка над local_auth.
///
/// Делает три вещи:
/// 1) проверяет доступность сенсора отпечатков/Face ID,
/// 2) запускает системный диалог биометрии,
/// 3) хранит «доверенный» JWT-токен для входа по отпечатку. Этот токен
///    лежит отдельно от обычного auth-токена в SharedPreferences и НЕ
///    удаляется при logout — это позволяет пользователю вернуться в
///    аккаунт по отпечатку, не вводя пароль снова. По задумке так же
///    устроены банковские приложения.
class BiometricService {
  static const _kEnabledKey = 'biometric_enabled_v1';
  static const _kTokenKey = 'biometric_jwt_v1';
  static final _auth = LocalAuthentication();

  /// На устройстве вообще есть биометрия (сенсор + хотя бы один
  /// зарегистрированный отпечаток / лицо)?
  static Future<bool> canUse() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Запускает диалог биометрии. Возвращает true только при успешной
  /// идентификации. При отказе/ошибке — false.
  static Future<bool> authenticate({
    String reason = 'Подтвердите вход в Parking',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// Пользователь включил вход по биометрии в этом приложении?
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabledKey) ?? false;
  }

  /// Включает/выключает биометрический вход. При выключении доверенный
  /// токен очищается — иначе он навечно лежит в SharedPreferences.
  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabledKey, value);
    if (!value) {
      await prefs.remove(_kTokenKey);
    }
  }

  /// Сохраняет JWT для следующего входа по биометрии. Вызывается сразу
  /// после успешного пароль-логина при согласии пользователя.
  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTokenKey, token);
  }

  /// Достаёт сохранённый биометрический токен. null — если его нет
  /// (биометрия не включалась, либо токен был очищен).
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kTokenKey);
  }
}
