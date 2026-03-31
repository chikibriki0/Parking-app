const token = localStorage.getItem("token");


let actionInProgress = false;

function showLoader(text = "Загрузка...") {
  const loader = document.getElementById("pageLoader");
  const loaderText = document.getElementById("loaderText");

  if (loaderText) {
    loaderText.innerText = text;
  }

  if (loader) {
    loader.classList.remove("hidden");
  }
}

function hideLoader() {
  const loader = document.getElementById("pageLoader");
  if (loader) {
    loader.classList.add("hidden");
  }
}

function showToast(message, type = "info") {
  const container = document.getElementById("toastContainer");
  if (!container) return;

  const toast = document.createElement("div");
  toast.className = `toast ${type}`;
  toast.innerText = message;

  container.appendChild(toast);

  setTimeout(() => {
    toast.classList.add("hide");
    setTimeout(() => toast.remove(), 300);
  }, 3000);
}

// 🔒 защита страницы
if (!token) {
  window.location.href = "login.html";
}

const ws = new WebSocket("ws://localhost:8080/ws");

const spots = {};
const spotMeta = {};
const mapDiv = document.getElementById("map");

let mySpot = null;
let mySpotNumber = null;
let myZoneName = null;
let myStartTime = null;

document.getElementById("logoutBtn").addEventListener("click", () => {
  localStorage.removeItem("token");
  showToast("Вы вышли из системы", "info");

  setTimeout(() => {
    window.location.href = "login.html";
  }, 700);
});

async function loadMyParking() {
  try {
    const response = await fetch("http://localhost:8080/my/parking", {
      headers: {
        "Authorization": "Bearer " + token
      }
    });

    if (!response.ok) {
      mySpot = null;
      mySpotNumber = null;
      myZoneName = null;
      myStartTime = null;
      return;
    }

    const data = await response.json();

    mySpot = data.spot_id;
    myStartTime = new Date(data.start_time);

    if (spotMeta[mySpot]) {
      mySpotNumber = spotMeta[mySpot].spotNumber;
      myZoneName = spotMeta[mySpot].zoneName;
    }

  } catch (err) {
    console.error("Ошибка загрузки моего места:", err);
  }
}

async function loadParkingMap() {
  try {
    const response = await fetch("http://localhost:8080/parking/map");

    if (!response.ok) {
      console.error("Ошибка загрузки карты");
      return;
    }

    const data = await response.json();

    mapDiv.innerHTML = "";

    data.zones.forEach(zone => {
      const zoneCard = document.createElement("div");
      zoneCard.className = "zone-card";

      const title = document.createElement("div");
      title.className = "zone-title";
      title.innerText = `Зона ${zone.name}`;

      const zoneDiv = document.createElement("div");
      zoneDiv.className = "spots";

      zone.spots.forEach(spot => {
        const el = document.createElement("div");
        el.id = "spot-" + spot.id;
        el.innerText = spot.spot_number;
        el.className = "spot";

        spots[spot.id] = spot.status;
        spotMeta[spot.id] = {
          spotNumber: spot.spot_number,
          zoneName: zone.name
        };

        updateSpotStyle(el, spot.id, spot.status);

        el.onclick = async () => {
          const status = spots[spot.id];
          if (actionInProgress) return;
          try {
                actionInProgress = true;
                el.classList.add("loading");

                let response;
            showLoader("Освобождаем место...");
            if (spot.id === mySpot) {
              response = await fetch(`http://localhost:8080/release/${spot.id}`, {
                method: "POST",
                headers: {
                  "Authorization": "Bearer " + token
                }
              });

              if (response.ok) {
                mySpot = null;
                mySpotNumber = null;
                myZoneName = null;
                myStartTime = null;

                await loadParkingMap();
                await loadStats();
                await loadHistory();
                updateMyParkingInfo();

                showToast("Парковочное место освобождено", "success");
                } else {
                showToast("Не удалось освободить место", "error");
                }

              return;
            }

            if (status === "OCCUPIED") {
              showToast("Это место уже занято", "warning");
              return;
            }

            if (status === "FREE") {
              showLoader("Переносим бронирование...");
              if (mySpot !== null) {
                await fetch(`http://localhost:8080/release/${mySpot}`, {
                  method: "POST",
                  headers: {
                    "Authorization": "Bearer " + token
                  }
                });
              }
              showLoader("Бронируем место...");
              response = await fetch(`http://localhost:8080/reserve/${spot.id}`, {
                method: "POST",
                headers: {
                  "Authorization": "Bearer " + token
                }
              });

              if (response.ok) {
  mySpot = spot.id;
  myStartTime = new Date();

                    if (spotMeta[mySpot]) {
                        mySpotNumber = spotMeta[mySpot].spotNumber;
                        myZoneName = spotMeta[mySpot].zoneName;
                    }

                    await loadParkingMap();
                    await loadStats();
                    await loadHistory();
                    updateMyParkingInfo();

                    showToast(`Место ${mySpotNumber} (${myZoneName}) успешно забронировано`, "success");
                    } else {
                    showToast("Не удалось забронировать место", "error");
                }
            }

          } catch (err) {
            showToast("Ошибка соединения с сервером", "error");
          }finally {
            actionInProgress = false;
            el.classList.remove("loading");
            hideLoader();
            }
        };

        zoneDiv.appendChild(el);
      });

      zoneCard.appendChild(title);
      zoneCard.appendChild(zoneDiv);
      mapDiv.appendChild(zoneCard);
    });

  } catch (err) {
    console.error("Ошибка карты:", err);
  }
}

function updateSpotStyle(el, spotId, status) {
  el.className = "spot";

  if (status === "OCCUPIED") {
    if (spotId === mySpot) {
      el.classList.add("my");
    } else {
      el.classList.add("occupied");
    }
  } else {
    el.classList.add("free");
  }
}

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);

  const spotId = data.spot_id;
  const isOccupied = data.type == 0;

  spots[spotId] = isOccupied ? "OCCUPIED" : "FREE";

  const el = document.getElementById("spot-" + spotId);
  if (!el) return;

  updateSpotStyle(el, spotId, spots[spotId]);
};

async function loadStats() {
  try {
    const res = await fetch("http://localhost:8080/stats");
    const data = await res.json();

    document.getElementById("statsCards").innerHTML = `
      <div class="stat-card stat-total">Всего: ${data.total_spots}</div>
      <div class="stat-card stat-free">Свободно: ${data.free}</div>
      <div class="stat-card stat-occupied">Занято: ${data.occupied}</div>
    `;
  } catch (err) {
    console.error("Ошибка статистики:", err);
  }
}

async function loadHistory() {
  try {
    const response = await fetch("http://localhost:8080/my/history", {
      headers: {
        "Authorization": "Bearer " + token
      }
    });

    if (!response.ok) {
      console.error("Ошибка загрузки истории");
      return;
    }

    const history = await response.json();
    const historyDiv = document.getElementById("history");
    historyDiv.innerHTML = "";

    if (!history.length) {
      historyDiv.innerHTML = `<div class="empty">История пока пуста</div>`;
      return;
    }

    const wrapper = document.createElement("div");
    wrapper.className = "history-list";

    history.forEach(item => {
      const block = document.createElement("div");
      block.className = "history-item";

      const start = new Date(item.start_time);
      const end = item.end_time ? new Date(item.end_time) : null;

      const formatDate = (date) => date.toLocaleString("ru-RU");

      const formatDuration = (start, end) => {
        if (!end) return "ещё активна";

        const diffMs = end - start;
        const totalSec = Math.floor(diffMs / 1000);

        const hours = Math.floor(totalSec / 3600);
        const minutes = Math.floor((totalSec % 3600) / 60);
        const seconds = totalSec % 60;

        let parts = [];
        if (hours > 0) parts.push(`${hours} ч`);
        if (minutes > 0) parts.push(`${minutes} мин`);
        parts.push(`${seconds} сек`);

        return parts.join(" ");
      };

      const meta = spotMeta[item.spot_id];
      const displaySpot = meta
        ? `${meta.spotNumber} (${meta.zoneName})`
        : `ID ${item.spot_id}`;

      block.innerHTML = `
        <b>Место ${displaySpot}</b><br>
        Начало: ${formatDate(start)}<br>
        Конец: ${end ? formatDate(end) : "ещё занято"}<br>
        Длительность: ${formatDuration(start, end)}
      `;

      wrapper.appendChild(block);
    });

    historyDiv.appendChild(wrapper);

  } catch (err) {
    console.error("Ошибка истории:", err);
  }
}

function updateMyParkingInfo() {
  const el = document.getElementById("myParkingInfo");

  if (mySpot === null || !myStartTime) {
    el.innerText = "";
    return;
  }

  const now = new Date();
  const diffMs = now - myStartTime;
  const totalSec = Math.floor(diffMs / 1000);

  const hours = Math.floor(totalSec / 3600);
  const minutes = Math.floor((totalSec % 3600) / 60);
  const seconds = totalSec % 60;

  const format = (n) => String(n).padStart(2, "0");

  el.innerText =
    `🚗 Моё место: ${mySpotNumber} (${myZoneName}) | ⏱ ${format(hours)}:${format(minutes)}:${format(seconds)}`;
}

(async () => {
  try {
    showLoader("Загружаем парковку...");

    await loadParkingMap();
    await loadMyParking();
    await loadParkingMap();
    await loadStats();
    await loadHistory();
    updateMyParkingInfo();
  } catch (err) {
    showToast("Ошибка загрузки данных", "error");
  } finally {
    hideLoader();
  }
})();

setInterval(loadStats, 3000);
setInterval(loadHistory, 5000);
setInterval(updateMyParkingInfo, 1000);