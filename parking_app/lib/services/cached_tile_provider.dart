import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// Тайл-провайдер, который кэширует тайлы карты на ДИСКЕ телефона.
///
/// Каждый тайл (например, https://tile.openstreetmap.org/15/19818/10245.png)
/// после первой загрузки сохраняется в системном кэше через
/// flutter_cache_manager. При повторном открытии того же фрагмента карты
/// тайлы берутся локально — без сети.
///
/// flutter_map при движении/зуме периодически вызывает getImage с новыми
/// координатами. CachedNetworkImageProvider под капотом сначала смотрит в
/// кэш, и лишь если нет — делает HTTP-запрос.
class CachedTileProvider extends TileProvider {
  CachedTileProvider({super.headers});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return CachedNetworkImageProvider(
      getTileUrl(coordinates, options),
      headers: headers,
    );
  }
}
