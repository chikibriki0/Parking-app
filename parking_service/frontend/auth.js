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

const token = localStorage.getItem("token");

// если уже залогинен — не пускаем на login/register
if (
  token &&
  (
    window.location.pathname.includes("login.html") ||
    window.location.pathname.includes("register.html")
  )
) {
  window.location.href = "index.html";
}

// ===== LOGIN =====
const loginForm = document.getElementById("loginForm");
if (loginForm) {
  const errorText = document.getElementById("loginError");
  const loginButton = loginForm.querySelector("button");

  loginForm.addEventListener("submit", async (e) => {
    e.preventDefault();

    const email = document.getElementById("email").value.trim();
    const password = document.getElementById("password").value.trim();

    errorText.innerText = "";

    try {
      loginButton.disabled = true;
      loginButton.innerText = "Входим...";
      showLoader("Выполняем вход...");

      const response = await fetch("http://localhost:8080/login", {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify({ email, password })
      });

      if (!response.ok) {
        errorText.innerText = "Неверный email или пароль";
        showToast("Ошибка входа", "error");
        return;
      }

      const data = await response.json();

      localStorage.setItem("token", data.token);
      showToast("Вход выполнен успешно", "success");

      setTimeout(() => {
        window.location.href = "index.html";
      }, 700);

    } catch (err) {
      errorText.innerText = "Ошибка соединения с сервером";
      showToast("Сервер недоступен", "error");
    } finally {
      loginButton.disabled = false;
      loginButton.innerText = "Войти";
      hideLoader();
    }
  });
}

// ===== REGISTER =====
const registerForm = document.getElementById("registerForm");
if (registerForm) {
  const errorText = document.getElementById("registerError");
  const registerButton = registerForm.querySelector("button");

  registerForm.addEventListener("submit", async (e) => {
    e.preventDefault();

    const email = document.getElementById("email").value.trim();
    const password = document.getElementById("password").value.trim();

    errorText.innerText = "";

    if (!email || !password) {
      errorText.innerText = "Введите email и пароль";
      showToast("Заполните все поля", "warning");
      return;
    }

    if (password.length < 6) {
      errorText.innerText = "Пароль должен быть не короче 6 символов";
      showToast("Слишком короткий пароль", "warning");
      return;
    }

    try {
      registerButton.disabled = true;
      registerButton.innerText = "Регистрируем...";
      showLoader("Создаём аккаунт...");

      const response = await fetch("http://localhost:8080/register", {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify({ email, password })
      });

      if (!response.ok) {
        if (response.status === 409) {
          errorText.innerText = "Пользователь с таким email уже существует";
          showToast("Такой email уже зарегистрирован", "warning");
        } else {
          errorText.innerText = "Ошибка регистрации";
          showToast("Ошибка регистрации", "error");
        }
        return;
      }

      showToast("Регистрация успешна! Теперь войдите", "success");

      setTimeout(() => {
        window.location.href = "login.html";
      }, 900);

    } catch (err) {
      errorText.innerText = "Ошибка соединения с сервером";
      showToast("Сервер недоступен", "error");
    } finally {
      registerButton.disabled = false;
      registerButton.innerText = "Зарегистрироваться";
      hideLoader();
    }
  });
}