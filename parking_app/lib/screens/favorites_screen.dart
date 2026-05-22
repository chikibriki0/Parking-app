import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../model/parking_location.dart';
import '../services/favorites_service.dart';
import '../theme/app_theme.dart';
import 'parking_details_screen.dart';

/// FavoritesScreen — список избранных парковок.
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final favs = context.watch<FavoritesService>();
    final items = kParkings.where((p) => favs.contains(p.title)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Избранное')),
      body: items.isEmpty
          ? _empty(context)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _item(context, items[i], favs),
            ),
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.bookmark_border_rounded,
              size: 72, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          Text('Избранных парковок пока нет',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Добавляйте парковки в избранное, чтобы быстро возвращаться '
              'к нужным точкам.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, ParkingLocation p, FavoritesService favs) {
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ParkingDetailsScreen(parking: p),
      )),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.local_parking_rounded,
                  color: AppTheme.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.title,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 2),
                  Text(p.address,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 6),
                  Text(
                    '${p.tariffRubPerHour} ₽ / час',
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.bookmark_rounded,
                  color: AppTheme.primary),
              onPressed: () => favs.toggle(p.title),
            ),
          ],
        ),
      ),
    );
  }
}
