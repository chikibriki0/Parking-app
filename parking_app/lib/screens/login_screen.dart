import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/parking_provider.dart';
import '../services/api_service.dart';
import '../services/biometric_service.dart';
import '../services/cars_service.dart';
import '../services/favorites_service.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm_dialog.dart';
import 'home_screen.dart';
import 'register_screen.dart';

/// Пост-логин-настройка: сбрасываем данные предыдущего пользователя
/// и привязываем сервисы (избранное, машины) к новому userId. Иначе
/// у новичка в профиле появится история, машины и избранное предыдущего
/// аккаунта на устройстве.
Future<void> applyAuthChange(BuildContext context) async {
  final auth = context.read<AuthProvider>();
  context.read<ParkingProvider>().resetUserState();
  await context.read<FavoritesService>().bindUser(auth.userId);
  await context.read<CarsService>().bindUser(auth.userId);
}

/// LoginScreen — экран входа в духе референса.
///
/// Содержит:
/// - иллюстрационную панель сверху (без зависимости от внешних ассетов —
///   composition из иконок и градиентов);
/// - поля Email + Пароль с иконками и переключателем видимости;
/// - кнопку «Войти», ссылку «Забыли пароль?»;
/// - разделитель «или»;
/// - кнопку «Войти по отпечатку» (показывается только если на устройстве
///   есть биометрия и пользователь её ранее включил);
/// - футер «Нет аккаунта? Зарегистрироваться».
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscurePassword = true;
  bool _showBiometric = false;

  @override
  void initState() {
    super.initState();
    _resolveBiometricButton();
  }

  /// Кнопка «Войти по отпечатку» показывается только если:
  /// - устройство поддерживает биометрию,
  /// - пользователь ранее включил её в настройках (после первого логина).
  Future<void> _resolveBiometricButton() async {
    final canUse = await BiometricService.canUse();
    final enabled = await BiometricService.isEnabled();
    if (!mounted) return;
    setState(() => _showBiometric = canUse && enabled);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await context.read<AuthProvider>().login(
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );

    if (!mounted) return;

    if (result['success'] == true) {
      // Перебиндить сервисы под нового пользователя ДО навигации на Home —
      // иначе HomeScreen увидит чужие машины/избранное.
      if (mounted) await applyAuthChange(context);
      // Если биометрия уже включена — обновим доверенный токен на свежий
      // (вдруг JWT_SECRET на сервере менялся).
      if (await BiometricService.isEnabled()) {
        final t = await ApiService.getToken();
        if (t != null) await BiometricService.saveToken(t);
      }
      // Если биометрия доступна, но ещё не включена — предложим её включить.
      final canUse = await BiometricService.canUse();
      final already = await BiometricService.isEnabled();
      if (canUse && !already && mounted) {
        final ok = await showConfirmDialog(
          context,
          title: 'Включить вход по отпечатку?',
          message:
              'В следующий раз вы сможете быстро войти в Parking, '
              'не вводя email и пароль — приложите палец к сенсору.',
          actionLabel: 'Включить',
          actionIcon: Icons.fingerprint_rounded,
        );
        if (ok == true) {
          await BiometricService.setEnabled(true);
          // Сохраняем свежий JWT в отдельное «биометрическое» хранилище —
          // оно переживёт logout.
          final t = await ApiService.getToken();
          if (t != null) await BiometricService.saveToken(t);
        }
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      setState(() {
        _error = result['message'] ?? 'Ошибка входа';
        _loading = false;
      });
    }
  }

  Future<void> _loginByBiometric() async {
    final ok = await BiometricService.authenticate(
      reason: 'Войдите в Parking по отпечатку',
    );
    if (!ok || !mounted) return;
    // Достаём «доверенный» токен — он сохранён при первом успешном
    // паролю-логине с согласием на биометрию и переживает logout.
    final trusted = await BiometricService.getToken();
    if (trusted == null) {
      setState(() => _error = 'Сначала войдите по паролю, чтобы включить отпечаток');
      return;
    }
    // Кладём токен обратно как «основной», чтобы AuthProvider и ApiService
    // его подхватили.
    await ApiService.saveToken(trusted);
    await context.read<AuthProvider>().checkAuth();
    if (!mounted) return;
    final loggedIn = context.read<AuthProvider>().isLoggedIn;
    if (loggedIn) {
      // Привязка сервисов под нового пользователя при биометрическом входе.
      await applyAuthChange(context);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      // Сохранённый JWT просрочен. Чистим и просим войти паролем.
      await BiometricService.setEnabled(false);
      setState(() {
        _showBiometric = false;
        _error = 'Сессия истекла, войдите по паролю';
      });
    }
  }

  void _comingSoon(String what) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text('$what — раздел в разработке'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _IllustrationPanel(),
              const SizedBox(height: 28),
              Text(
                'Parking Service',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Войдите в систему\nуправления парковкой',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              _field(
                controller: _emailController,
                label: 'Email',
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              _field(
                controller: _passwordController,
                label: 'Пароль',
                icon: Icons.lock_outline_rounded,
                obscure: _obscurePassword,
                suffix: IconButton(
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  onPressed: () => setState(
                      () => _obscurePassword = !_obscurePassword),
                ),
                onSubmitted: (_) => _login(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                        color: AppTheme.danger, fontSize: 14),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _loading ? null : _login,
                  child: _loading
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text('Войти'),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => _comingSoon('Восстановление пароля'),
                  child: const Text('Забыли пароль?'),
                ),
              ),
              const SizedBox(height: 8),
              const _Divider(label: 'или'),
              const SizedBox(height: 16),
              if (_showBiometric)
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _loginByBiometric,
                    icon: const Icon(Icons.fingerprint_rounded, size: 22),
                    label: const Text('Войти по отпечатку'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: BorderSide(
                          color: AppTheme.primary.withOpacity(0.4)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () => _comingSoon('Вход по QR-коду'),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 22),
                    label: const Text('Войти по QR-коду'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: BorderSide(
                          color: AppTheme.primary.withOpacity(0.4)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Нет аккаунта? ',
                      style: TextStyle(color: AppTheme.textSecondary)),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const RegisterScreen()),
                    ),
                    child: const Text(
                      'Зарегистрироваться',
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    ValueChanged<String>? onSubmitted,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: AppTheme.textSecondary, size: 20),
          suffixIcon: suffix,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }
}

/// Декоративная панель сверху с иллюстрацией парковки.
/// Сделана из встроенных Material-иконок и градиента — никаких сторонних
/// ассетов не требуется.
class _IllustrationPanel extends StatelessWidget {
  const _IllustrationPanel();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.primary.withOpacity(0.10),
              AppTheme.primary.withOpacity(0.02),
            ],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // «Здания» вдалеке
            Positioned(
              top: 14, left: 24,
              child: Icon(Icons.apartment_rounded,
                  size: 70, color: AppTheme.primary.withOpacity(0.18)),
            ),
            Positioned(
              top: 24, right: 30,
              child: Icon(Icons.business_rounded,
                  size: 60, color: AppTheme.primary.withOpacity(0.20)),
            ),
            // Машина по центру
            Positioned(
              bottom: 28,
              child: Icon(Icons.directions_car_filled_rounded,
                  size: 90, color: AppTheme.primary),
            ),
            // Дорожная разметка
            Positioned(
              bottom: 14, left: 0, right: 0,
              child: SizedBox(
                height: 6,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                      8,
                      (_) => Container(
                            width: 16, height: 4,
                            decoration: BoxDecoration(
                              color: AppTheme.textSecondary.withOpacity(0.35),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          )),
                ),
              ),
            ),
            // Pin парковки сверху-справа
            Positioned(
              top: 16, right: 88,
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Text(
                  'P',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final String label;
  const _Divider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppTheme.separator)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(label,
              style: const TextStyle(color: AppTheme.textSecondary)),
        ),
        const Expanded(child: Divider(color: AppTheme.separator)),
      ],
    );
  }
}
