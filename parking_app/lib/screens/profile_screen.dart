import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/parking_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm_dialog.dart';
import 'admin_screen.dart';
import 'login_screen.dart';

/// ProfileScreen — данные пользователя, сводка по парковкам, выход.
/// Дизайн повторяет ритм iOS Settings: группы белых карточек с иконками.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final parking = context.watch<ParkingProvider>();
    final email = _emailFromToken(auth);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _UserHeader(email: email, isAdmin: auth.isAdmin),
          const SizedBox(height: 12),
          _StatsCard(
            activeNow: parking.mySpotId != null ? 1 : 0,
            totalBookings: parking.history.length,
          ),
          const SizedBox(height: 24),

          _SectionTitle('Автомобили'),
          _SettingsGroup(
            tiles: [
              _SettingsTile(
                icon: Icons.directions_car_rounded,
                iconColor: AppTheme.primary,
                title: 'А 777 АА 77',
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Основной',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
              _SettingsTile(
                icon: Icons.add_rounded,
                iconColor: AppTheme.primary,
                title: 'Добавить автомобиль',
                titleColor: AppTheme.primary,
                onTap: () => _comingSoon(context, 'Добавление автомобиля'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          _SectionTitle('Оплата'),
          _SettingsGroup(
            tiles: [
              _SettingsTile(
                icon: Icons.credit_card_rounded,
                iconColor: AppTheme.success,
                title: 'Способы оплаты',
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textSecondary),
                onTap: () => _comingSoon(context, 'Способы оплаты'),
              ),
              _SettingsTile(
                icon: Icons.receipt_long_rounded,
                iconColor: AppTheme.warning,
                title: 'История платежей',
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textSecondary),
                onTap: () => _comingSoon(context, 'История платежей'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          if (auth.isAdmin) ...[
            _SectionTitle('Администрирование'),
            _SettingsGroup(
              tiles: [
                _SettingsTile(
                  icon: Icons.shield_rounded,
                  iconColor: AppTheme.danger,
                  title: 'Панель администратора',
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: AppTheme.textSecondary),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminScreen()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],

          _SectionTitle('Аккаунт'),
          _SettingsGroup(
            tiles: [
              _SettingsTile(
                icon: Icons.logout_rounded,
                iconColor: AppTheme.danger,
                title: 'Выйти из аккаунта',
                titleColor: AppTheme.danger,
                onTap: () async {
                  final confirmed = await showConfirmDialog(
                    context,
                    title: 'Вы уверены, что хотите выйти из аккаунта?',
                    message:
                        'Активная бронь сохранится, но для доступа к ней '
                        'потребуется снова войти под своими данными.',
                    actionLabel: 'Выйти',
                    actionColor: AppTheme.danger,
                    actionIcon: Icons.logout_rounded,
                  );
                  if (confirmed != true) return;
                  await auth.logout();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (_) => false,
                    );
                  }
                },
              ),
            ],
          ),

          const SizedBox(height: 24),
          Center(
            child: Text(
              'Parking Service · ВКР НИУ «МЭИ»',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  /// Email пользователя из AuthProvider (он подтягивается через /me).
  /// Пока email ещё не пришёл — fallback на роль + ID.
  String _emailFromToken(AuthProvider auth) {
    if (auth.email != null && auth.email!.isNotEmpty) return auth.email!;
    if (auth.userId != null) {
      return auth.isAdmin
          ? 'Администратор (ID ${auth.userId})'
          : 'Пользователь (ID ${auth.userId})';
    }
    return 'Гость';
  }

  void _comingSoon(BuildContext context, String what) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text('$what — раздел в разработке'),
    ));
  }
}

class _UserHeader extends StatelessWidget {
  final String email;
  final bool isAdmin;
  const _UserHeader({required this.email, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primary, AppTheme.primaryDark],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              isAdmin ? Icons.shield_rounded : Icons.person_rounded,
              color: Colors.white, size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(email, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isAdmin ? AppTheme.warning : AppTheme.primary)
                        .withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isAdmin ? 'ADMIN' : 'USER',
                    style: TextStyle(
                      color: isAdmin ? AppTheme.warning : AppTheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final int activeNow;
  final int totalBookings;
  const _StatsCard({required this.activeNow, required this.totalBookings});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(child: _StatCell(value: '$activeNow', label: 'Активных')),
          _VerticalSeparator(),
          Expanded(child: _StatCell(value: '$totalBookings', label: 'Всего\nбронирований')),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String value;
  final String label;
  const _StatCell({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _VerticalSeparator extends StatelessWidget {
  const _VerticalSeparator();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 0.5,
      height: 44,
      color: AppTheme.separator,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> tiles;
  const _SettingsGroup({required this.tiles});

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];
    for (int i = 0; i < tiles.length; i++) {
      widgets.add(tiles[i]);
      if (i < tiles.length - 1) {
        widgets.add(const Padding(
          padding: EdgeInsets.only(left: 60),
          child: Divider(height: 0.5),
        ));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(children: widgets),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Color? titleColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.titleColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.14),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: titleColor ?? AppTheme.textPrimary,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
