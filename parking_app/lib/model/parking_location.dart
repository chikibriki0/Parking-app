import 'package:latlong2/latlong.dart' show LatLng;

/// ParkingLocation — статическая «легенда» парковки на карте.
///
/// Реальный backend знает только три зоны (A, B, C), которые мы привязали
/// к зданиям МЭИ. Остальные парковки добавлены для визуальной массовки на
/// карте Москвы и поиска — у них `bookable = false`, при попытке
/// забронировать показывается сообщение.
class ParkingLocation {
  /// Номер зоны в БД (parking_zones.id). Для фейковых парковок может быть 0.
  final int zoneId;

  /// Имя зоны в БД (parking_zones.name). Для фейковых — пустая строка.
  final String zoneName;

  /// Что показывать в UI как название парковки.
  final String title;

  /// Адрес для подзаголовка.
  final String address;

  /// Координаты pin'а на карте.
  final LatLng location;

  /// URL фотографии парковки.
  final String photoUrl;

  /// Доступна ли парковка для бронирования. Только три реальных зоны = true.
  final bool bookable;

  /// Общее количество мест (для display у фейковых).
  final int displayTotal;

  /// Свободных «по умолчанию» (для фейковых, у настоящих берётся из API).
  final int displayFree;

  /// Тариф ₽/час. 0 = бесплатно.
  final int tariffRubPerHour;

  /// Сколько первых минут бесплатно (например, 15).
  final int freeFirstMinutes;

  const ParkingLocation({
    required this.zoneId,
    required this.zoneName,
    required this.title,
    required this.address,
    required this.location,
    required this.photoUrl,
    this.bookable = true,
    this.displayTotal = 0,
    this.displayFree = 0,
    this.tariffRubPerHour = 100,
    this.freeFirstMinutes = 15,
  });

  /// Подсчёт стоимости брони с учётом бесплатных первых N минут.
  int costRub(Duration duration) {
    if (tariffRubPerHour == 0) return 0;
    final paidMinutes = duration.inMinutes - freeFirstMinutes;
    if (paidMinutes <= 0) return 0;
    // округляем вверх до часа? нет — пропорция по минутам, как на счётчиках
    return ((paidMinutes / 60.0) * tariffRubPerHour).ceil();
  }
}

// Фото со стабильных CDN, чтобы каждая парковка имела уникальный визуал.
const _photoA = 'https://images.unsplash.com/photo-1506521781263-d8422e82f27a?w=1200&q=80';
const _photoB = 'https://images.unsplash.com/photo-1573348722427-f1d6819fdf98?w=1200&q=80';
const _photoC = 'https://images.unsplash.com/photo-1611439113085-5b3f5e3a3f99?w=1200&q=80';
const _photoD = 'https://images.unsplash.com/photo-1545179605-1296651e9d43?w=1200&q=80';
const _photoE = 'https://images.unsplash.com/photo-1593173935417-c41c1d6e98e1?w=1200&q=80';
const _photoF = 'https://images.unsplash.com/photo-1597007030739-6d2e7172ee6f?w=1200&q=80';
const _photoG = 'https://images.unsplash.com/photo-1604063155785-ee4488b8ad15?w=1200&q=80';
const _photoH = 'https://images.unsplash.com/photo-1574006086727-feaa92ee7036?w=1200&q=80';

/// Реальные парковки (наш backend знает только их):
const List<ParkingLocation> _realParkings = [
  ParkingLocation(
    zoneId: 1,
    zoneName: 'A',
    title: 'НИУ «МЭИ» · корпус А',
    address: 'Красноказарменная ул., 14',
    location: LatLng(55.754802, 37.708373),
    photoUrl: _photoA,
  ),
  ParkingLocation(
    zoneId: 2,
    zoneName: 'B',
    title: 'НИУ «МЭИ» · корпус Б',
    address: 'Красноказарменная ул., 17',
    location: LatLng(55.756250, 37.710900),
    photoUrl: _photoB,
  ),
  ParkingLocation(
    zoneId: 3,
    zoneName: 'C',
    title: 'НИУ «МЭИ» · общежитие',
    address: 'Энергетический пр., 4',
    location: LatLng(55.752900, 37.705600),
    photoUrl: _photoC,
  ),
];

/// Фейковые парковки для массовки на карте Москвы.
const List<ParkingLocation> _fakeParkings = [
  ParkingLocation(
    zoneId: 0, zoneName: '',
    title: 'Парковка у спорткомплекса',
    address: 'ул. Радио, 10с1',
    location: LatLng(55.760400, 37.700100),
    photoUrl: _photoD,
    bookable: false,
    displayTotal: 40, displayFree: 24,
  ),
  ParkingLocation(
    zoneId: 0, zoneName: '',
    title: 'БЦ «Энергия»',
    address: 'ш. Энтузиастов, 38',
    location: LatLng(55.751200, 37.722500),
    photoUrl: _photoE,
    bookable: false,
    displayTotal: 20, displayFree: 8,
  ),
  ParkingLocation(
    zoneId: 0, zoneName: '',
    title: 'ТЦ «Город» Лефортово',
    address: 'ш. Энтузиастов, 12',
    location: LatLng(55.756100, 37.696800),
    photoUrl: _photoF,
    bookable: false,
    displayTotal: 120, displayFree: 47,
  ),
  ParkingLocation(
    zoneId: 0, zoneName: '',
    title: 'Бизнес-центр Lefort',
    address: 'Электрозаводская ул., 27с8',
    location: LatLng(55.763400, 37.712900),
    photoUrl: _photoG,
    bookable: false,
    displayTotal: 60, displayFree: 12,
  ),
  ParkingLocation(
    zoneId: 0, zoneName: '',
    title: 'Парковка у метро Авиамоторная',
    address: 'ш. Энтузиастов, 11',
    location: LatLng(55.751900, 37.717100),
    photoUrl: _photoH,
    bookable: false,
    displayTotal: 80, displayFree: 33,
  ),
  ParkingLocation(
    zoneId: 0, zoneName: '',
    title: 'Парковка ВНИИНМ',
    address: 'ул. Рогожский Вал, 18',
    location: LatLng(55.745700, 37.690400),
    photoUrl: _photoD,
    bookable: false,
    displayTotal: 30, displayFree: 5,
  ),
  ParkingLocation(
    zoneId: 0, zoneName: '',
    title: 'Парковка Курского вокзала',
    address: 'ул. Земляной Вал, 29',
    location: LatLng(55.757500, 37.660800),
    photoUrl: _photoE,
    bookable: false,
    displayTotal: 200, displayFree: 56,
  ),
  ParkingLocation(
    zoneId: 0, zoneName: '',
    title: 'Парковка у Чкаловской',
    address: 'Земляной Вал, 26',
    location: LatLng(55.756200, 37.659000),
    photoUrl: _photoF,
    bookable: false,
    displayTotal: 25, displayFree: 9,
  ),
  ParkingLocation(
    zoneId: 0, zoneName: '',
    title: 'ТРЦ «Атриум»',
    address: 'ул. Земляной Вал, 33',
    location: LatLng(55.757000, 37.658100),
    photoUrl: _photoG,
    bookable: false,
    displayTotal: 350, displayFree: 124,
  ),
  ParkingLocation(
    zoneId: 0, zoneName: '',
    title: 'Парковка у Бауманской',
    address: 'Бауманская ул., 35',
    location: LatLng(55.770800, 37.677700),
    photoUrl: _photoH,
    bookable: false,
    displayTotal: 70, displayFree: 18,
  ),
  ParkingLocation(
    zoneId: 0, zoneName: '',
    title: 'БЦ «Северная башня»',
    address: 'Тестовская ул., 10',
    location: LatLng(55.748900, 37.534200),
    photoUrl: _photoD,
    bookable: false,
    displayTotal: 500, displayFree: 217,
  ),
  ParkingLocation(
    zoneId: 0, zoneName: '',
    title: 'Парковка ГУМа',
    address: 'Красная площадь, 3',
    location: LatLng(55.754700, 37.621400),
    photoUrl: _photoE,
    bookable: false,
    displayTotal: 150, displayFree: 22,
  ),
  ParkingLocation(
    zoneId: 0, zoneName: '',
    title: 'Парковка Москва-Сити',
    address: 'Пресненская наб., 12',
    location: LatLng(55.749500, 37.539800),
    photoUrl: _photoF,
    bookable: false,
    displayTotal: 1500, displayFree: 412,
  ),
  ParkingLocation(
    zoneId: 0, zoneName: '',
    title: 'ТРЦ «Авиапарк»',
    address: 'Ходынский бул., 4',
    location: LatLng(55.788900, 37.531800),
    photoUrl: _photoG,
    bookable: false,
    displayTotal: 2800, displayFree: 894,
  ),
  ParkingLocation(
    zoneId: 0, zoneName: '',
    title: 'Парковка ВДНХ',
    address: 'просп. Мира, 119',
    location: LatLng(55.829600, 37.633500),
    photoUrl: _photoH,
    bookable: false,
    displayTotal: 800, displayFree: 312,
  ),
];

/// Полный список парковок на карте (реальные + фейковые).
const List<ParkingLocation> kParkings = [
  ..._realParkings,
  ..._fakeParkings,
];

/// Маппинг технического имени зоны из БД («A», «B», «C») в
/// человекочитаемое название («НИУ МЭИ · корпус А» и т.д.). Используется
/// в админ-панели и в карточке активной парковки, чтобы пользователь
/// видел осмысленный адрес, а не однобуквенный идентификатор.
String friendlyZoneName(String? dbName) {
  if (dbName == null || dbName.isEmpty) return '—';
  for (final p in _realParkings) {
    if (p.zoneName == dbName) return p.title;
  }
  return 'Зона $dbName';
}
