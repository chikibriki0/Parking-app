import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _users = [];
  List<dynamic> _sessions = [];
  List<dynamic> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      ApiService.getAdminUsers(),
      ApiService.getAdminActiveSessions(),
      ApiService.getAdminHistory(),
    ]);
    if (mounted) {
      setState(() {
        _users = results[0];
        _sessions = results[1];
        _history = results[2];
        _loading = false;
      });
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '—';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return DateFormat('dd.MM HH:mm').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  Future<void> _adminRelease(int spotId) async {
    final ok = await ApiService.adminReleaseSpot(spotId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Место освобождено' : 'Ошибка'),
          backgroundColor: ok ? AppTheme.success : AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      if (ok) _loadAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings_outlined,
                color: AppTheme.primary, size: 24),
            SizedBox(width: 8),
            Text('Панель администратора'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadAll,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primary,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.people_outline, size: 18),
                  const SizedBox(width: 4),
                  Text('Пользователи (${_users.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.directions_car_outlined, size: 18),
                  const SizedBox(width: 4),
                  Text('Активные (${_sessions.length})'),
                ],
              ),
            ),
            const Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_rounded, size: 18),
                  SizedBox(width: 4),
                  Text('История'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildUsersList(),
                _buildSessionsList(),
                _buildHistoryList(),
              ],
            ),
    );
  }

  Widget _buildUsersList() {
    if (_users.isEmpty) {
      return _emptyState('Нет пользователей', Icons.people_outline);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _users.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final user = _users[i];
        final role = user['role'] as String? ?? 'USER';
        return _listCard(
          leading: CircleAvatar(
            backgroundColor:
                (role == 'ADMIN' ? AppTheme.warning : AppTheme.primary)
                    .withOpacity(0.15),
            child: Icon(
              role == 'ADMIN' ? Icons.star_rounded : Icons.person_rounded,
              color: role == 'ADMIN' ? AppTheme.warning : AppTheme.primary,
              size: 22,
            ),
          ),
          title: user['email'] as String? ?? '—',
          subtitle: 'ID: ${user['id']} · Роль: $role',
          trailing: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (role == 'ADMIN' ? AppTheme.warning : AppTheme.primary)
                  .withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              role,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: role == 'ADMIN' ? AppTheme.warning : AppTheme.primary,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSessionsList() {
    if (_sessions.isEmpty) {
      return _emptyState('Нет активных парковок', Icons.directions_car_outlined);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final s = _sessions[i];
        final spotId = s['spot_id'];
        return _listCard(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.danger.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.local_parking_rounded,
                color: AppTheme.danger, size: 24),
          ),
          title: s['email'] as String? ?? '—',
          subtitle:
              'Место: ${s['spot_number']} · Зона: ${s['zone_name'] ?? '—'}\nНачало: ${_formatDate(s['start_time'])}',
          trailing: IconButton(
            icon: const Icon(Icons.lock_open_rounded, color: AppTheme.danger),
            tooltip: 'Принудительно освободить',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  title: const Text('Освободить место?'),
                  content: Text(
                      'Принудительно освободить место пользователя ${s['email']}?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Отмена'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.danger),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Освободить'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                _adminRelease(spotId as int);
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildHistoryList() {
    if (_history.isEmpty) {
      return _emptyState('История пуста', Icons.history_rounded);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final h = _history[i];
        return _listCard(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.textSecondary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.history_rounded,
                color: AppTheme.textSecondary, size: 24),
          ),
          title: h['email'] as String? ?? '—',
          subtitle:
              'Место: ${h['spot_number']} · Зона: ${h['zone_name'] ?? '—'}\n${_formatDate(h['start_time'])} → ${_formatDate(h['end_time'])}',
          trailing: null,
        );
      },
    );
  }

  Widget _listCard({
    required Widget leading,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: leading,
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Text(subtitle,
            style: const TextStyle(
                fontSize: 13, color: AppTheme.textSecondary)),
        trailing: trailing,
      ),
    );
  }

  Widget _emptyState(String text, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            text,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}