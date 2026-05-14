# Parking Service

Сервис управления парковочными местами. ВКР, направление 09.03.01 (НИУ «МЭИ», кафедра ВМСС).

Система состоит из:
- **`parking_service/`** — backend на Go (REST + WebSocket, JWT-аутентификация, PostgreSQL, Docker-развёртывание).
- **`parking_app/`** — Android-клиент на Flutter, общается с backend по REST и подписывается на обновления через WebSocket.

## Архитектура

```
┌────────────────┐      REST/JWT       ┌───────────────────────┐      ┌──────────────┐
│ Android-клиент │ ──────────────────▶ │  Go-backend (cmd/)    │ ───▶ │ PostgreSQL   │
│   (Flutter)    │ ◀──── WS push ───── │  service / repository │      │ parking_db   │
└────────────────┘                     │  model / config       │      └──────────────┘
                                       │  ↑ simulation goroutine        
                                       │  ↑ expiration sweeper (тикер)
                                       └───────────────────────┘
```

- События резерв/освобождение от пользователя обрабатываются **синхронно** в HTTP-хендлерах → клиент сразу получает HTTP-код (200/404/409).
- События от **симуляции** идут через буферизированный канал `manager.Events` и горутину-обработчик в `cmd/main.go` (требование ТЗ: каналы + горутины).
- **Автозавершение** парковки выполняется периодической горутиной-«суиппером» (`StartExpirationSweeper`), переживает перезапуски сервера.
- **WebSocket** транслирует все изменения мест всем подключённым клиентам.

## Быстрый старт (локально через Docker)

1. `cd parking_service`
2. Скопируйте `.env.example` в `.env` и **обязательно** замените `JWT_SECRET` на длинную случайную строку:
   ```bash
   # Linux/macOS:
   openssl rand -base64 48
   # Windows PowerShell:
   [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(48))
   ```
3. `docker compose up -d --build`
4. Сервис будет доступен на `http://localhost:8080`.
   Swagger-UI: `http://localhost:8080/swagger/index.html`.
   Health-check: `GET http://localhost:8080/health`.

Тестовые пользователи (пароль `password123`):
- `admin@parking.ru` — роль `ADMIN`
- `user@parking.ru` — роль `USER`

## Переменные окружения backend

| Переменная | Дефолт | Описание |
|---|---|---|
| `JWT_SECRET` | — (обязательно) | Секрет для подписи JWT. Без него сервис не стартует. |
| `JWT_TTL` | `24h` | Время жизни токена (формат Go duration). |
| `DATABASE_URL` | `postgres://postgres:postgres@postgres:5432/parking_db?sslmode=disable` | DSN PostgreSQL. |
| `HTTP_ADDR` | `:8080` | Адрес HTTP-сервера. |
| `PARKING_EXPIRE_AFTER` | `2m` | Через сколько активная парковка автозавершается. |
| `SIMULATION_ENABLED` | `false` | Включает встроенный эмулятор трафика. На демо — `true`. |
| `CORS_ALLOWED_ORIGINS` | `*` | Список через запятую или `*`. |

## Flutter-клиент

Минимально-нужная сборка для **Android-эмулятора** (Pixel/Nexus в Android Studio):

```bash
cd parking_app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080 \
            --dart-define=WS_BASE_URL=ws://10.0.2.2:8080/ws
```

`10.0.2.2` — спец-IP, по которому Android-эмулятор видит localhost хоста.

### Сборка APK для физического телефона

Сначала узнайте IP вашего ПК в локальной сети (например, `192.168.1.42`) и убедитесь, что Windows Firewall разрешает входящие TCP/8080. Затем:

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=http://192.168.1.42:8080 \
  --dart-define=WS_BASE_URL=ws://192.168.1.42:8080/ws
```

Готовый файл — `build/app/outputs/flutter-apk/app-release.apk`. Перенесите на телефон и установите. Backend при этом должен крутиться (`docker compose up`).

### Сборка APK под backend, развёрнутый в интернете

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://parking.example.com \
  --dart-define=WS_BASE_URL=wss://parking.example.com/ws
```

> Android по умолчанию запрещает HTTP без TLS (cleartext) в release-сборках. Для домена в интернете используйте HTTPS, для локального теста по IP это и так работает.

## Структура кода backend

```
parking_service/
├── cmd/main.go              # точка входа, маршруты HTTP
├── internal/
│   ├── config/              # загрузка env
│   ├── model/               # доменные структуры, симуляция трафика
│   ├── repository/          # доступ к PostgreSQL (pgx)
│   └── service/             # JWT, middleware, бизнес-логика, WebSocket
├── docs/                    # сгенерированный swagger
├── frontend/                # старый веб-UI (для админ-демонстраций)
├── init-db/init.sql         # схема + сидинг
├── docker-compose.yml
└── Dockerfile               # multi-stage
```

## REST API

| Метод | Путь | Доступ | Описание |
|---|---|---|---|
| POST | `/register` | public | Регистрация (email + password ≥ 6) |
| POST | `/login` | public | Возвращает JWT |
| GET  | `/parking/map` | public | Все зоны со списком мест и статусами |
| GET  | `/spots` | public | Плоский список всех мест |
| GET  | `/zones/{id}/spots` | public | Места в зоне |
| GET  | `/stats` | public | total/occupied/free |
| GET  | `/health` | public | Liveness |
| GET  | `/swagger/` | public | Swagger UI |
| GET  | `/ws` | public | WebSocket для push-обновлений |
| POST | `/reserve/{spotId}` | USER | Бронь места |
| POST | `/release/{spotId}` | USER | Освобождение своего места |
| GET  | `/my/parking` | USER | Активная парковка пользователя |
| GET  | `/my/history` | USER | История пользователя |
| GET  | `/admin/users` | ADMIN | Все пользователи |
| GET  | `/admin/active-sessions` | ADMIN | Все активные брони |
| GET  | `/admin/history` | ADMIN | Полная история (200 последних) |
| POST | `/admin/release/{spotId}` | ADMIN | Принудительное освобождение |

Все защищённые маршруты ждут заголовок `Authorization: Bearer <JWT>`.

### Коды ответа /reserve

- `200` — успешно
- `400` — невалидный spotId
- `401` — нет токена
- `404` — место не существует
- `409` — место занято или у пользователя уже есть активная бронь
- `500` — внутренняя ошибка

## Безопасность

- Пароли хранятся как `bcrypt`-хэши.
- JWT подписаны HS256, секрет — из `JWT_SECRET`.
- Bcrypt-хэши тестовых пользователей в `init-db/init.sql` соответствуют паролю `password123` — после развёртывания на проде их следует удалить или сменить пароли.
- На уровне БД: уникальный частичный индекс `one_active_parking_per_user` гарантирует, что у пользователя не может быть двух активных сессий одновременно (даже при гонке).
- Транзакция `StartParking` использует `SELECT ... FOR UPDATE` на строке места, что исключает гонку «двое забронировали одно место».

## Что внутри ТЗ ВКР

Все 7 пунктов задания реализованы:
1. ✅ Go-сервис, хранение зон/мест/пользователей/истории
2. ✅ Клиент-серверная архитектура REST API + бизнес-логика + PostgreSQL + JWT
3. ✅ Безопасные пароли (bcrypt), JWT с проверкой подписи и срока, защищённые маршруты
4. ✅ Подсистема парковки: резерв/освобождение/автозавершение, асинхронность через каналы и горутины (симуляция, sweeper)
5. ✅ REST API для регистрации, входа, мест, резерва, освобождения, активной парковки, истории
6. ✅ Схема БД с целостностью (FK, уникальные индексы)
7. ✅ Android-клиент с регистрацией, входом, картой, бронированием, отслеживанием времени
8. ✅ Развёртывание в Docker (сервис + БД)
