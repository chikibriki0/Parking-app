import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/parking_provider.dart';
import 'screens/splash_screen.dart';
import 'services/cars_service.dart';
import 'services/favorites_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // intl: грузим символы для русской локали (нужно для DateFormat('...', 'ru')).
  await initializeDateFormatting('ru', null);
  runApp(const ParkingApp());
}

class ParkingApp extends StatelessWidget {
  const ParkingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ParkingProvider()),
        ChangeNotifierProvider(create: (_) => FavoritesService()..load()),
        ChangeNotifierProvider(create: (_) => CarsService()..bindUser(null)),
      ],
      child: MaterialApp(
        title: 'Моя парковка',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.light,
        theme: AppTheme.light,
        home: const SplashScreen(),
      ),
    );
  }
}