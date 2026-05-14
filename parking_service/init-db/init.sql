CREATE TABLE users (
    id         SERIAL PRIMARY KEY,
    email      TEXT UNIQUE NOT NULL,
    password   TEXT NOT NULL,
    role       TEXT NOT NULL DEFAULT 'USER',
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE parking_zones (
    id          SERIAL PRIMARY KEY,
    name        TEXT NOT NULL,
    total_spots INTEGER NOT NULL,
    created_at  TIMESTAMP DEFAULT NOW()
);

CREATE TABLE parking_spots (
    id          SERIAL PRIMARY KEY,
    zone_id     INTEGER REFERENCES parking_zones(id) ON DELETE CASCADE,
    spot_number INTEGER NOT NULL,
    status      TEXT NOT NULL DEFAULT 'FREE',
    UNIQUE(zone_id, spot_number)
);

CREATE TABLE parking_sessions (
    id         SERIAL PRIMARY KEY,
    user_id    INT REFERENCES users(id) ON DELETE CASCADE,
    spot_id    INT REFERENCES parking_spots(id) ON DELETE CASCADE,
    start_time TIMESTAMP NOT NULL,
    end_time   TIMESTAMP,
    source     TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE UNIQUE INDEX one_active_parking_per_user
    ON parking_sessions(user_id)
    WHERE end_time IS NULL;

CREATE TABLE parking_history (
    id         SERIAL PRIMARY KEY,
    user_id    INT REFERENCES users(id) ON DELETE SET NULL,
    spot_id    INT REFERENCES parking_spots(id) ON DELETE SET NULL,
    start_time TIMESTAMP,
    end_time   TIMESTAMP,
    source     TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO parking_zones (name, total_spots) VALUES ('A', 5), ('B', 5), ('C', 5);

INSERT INTO parking_spots (zone_id, spot_number) VALUES
    (1,1),(1,2),(1,3),(1,4),(1,5),
    (2,1),(2,2),(2,3),(2,4),(2,5),
    (3,1),(3,2),(3,3),(3,4),(3,5);

-- Тестовые пользователи, пароль: password123
INSERT INTO users (email, password, role) VALUES
    ('admin@parking.ru',
     '$2a$10$2eWeZ4qPW8PUKeKOcnTXreZLUYSwcqD5KEO5tmYnMf6JP9tscUQ5a',
     'ADMIN'),
    ('user@parking.ru',
     '$2a$10$2eWeZ4qPW8PUKeKOcnTXreZLUYSwcqD5KEO5tmYnMf6JP9tscUQ5a',
     'USER');