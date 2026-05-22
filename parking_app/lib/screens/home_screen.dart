import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/parking_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/active_parking_banner.dart';
import 'bookings_screen.dart';
import 'favorites_screen.dart';
import 'map_screen.dart';
import 'profile_screen.dart';

/// HomeScreen — корневой экран после логина с BottomNavigationBar.
/// Четыре вкладки: Карта · Бронирования · Избранное · Профиль.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  final List<Widget> _pages = const [
    MapScreen(),
    BookingsScreen(),
    FavoritesScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ParkingProvider>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // На вкладке «Бронирования» (index 1) активная парковка уже
          // показана большой синей карточкой — не дублируем баннером.
          if (_index != 1) const ActiveParkingBanner(),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                  top: BorderSide(color: AppTheme.separator, width: 0.5)),
            ),
            child: SafeArea(
              top: false,
              child: NavigationBar(
                backgroundColor: Theme.of(context).colorScheme.surface,
                indicatorColor: AppTheme.primary.withOpacity(0.12),
                labelBehavior:
                    NavigationDestinationLabelBehavior.alwaysShow,
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.map_outlined),
                    selectedIcon:
                        Icon(Icons.map_rounded, color: AppTheme.primary),
                    label: 'Карта',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.local_parking_outlined),
                    selectedIcon: Icon(Icons.local_parking_rounded,
                        color: AppTheme.primary),
                    label: 'Бронирования',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.bookmark_border_rounded),
                    selectedIcon: Icon(Icons.bookmark_rounded,
                        color: AppTheme.primary),
                    label: 'Избранное',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    selectedIcon: Icon(Icons.person_rounded,
                        color: AppTheme.primary),
                    label: 'Профиль',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
