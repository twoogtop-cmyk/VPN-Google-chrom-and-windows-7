const vlessInput = document.getElementById("vless");
const toggleBtn = document.getElementById("toggle");
const saveBtn = document.getElementById("save");
const checkControllerBtn = document.getElementById("checkController");
const checkTunnelBtn = document.getElementById("checkTunnel");
const statusEl = document.getElementById("status");

let enabled = false;

function setStatus(text, type) {
  statusEl.textContent = text || "";
  statusEl.classList.remove("ok", "err");
  if (type) statusEl.classList.add(type);
}

function setBusy(isBusy) {
  toggleBtn.disabled = isBusy;
  saveBtn.disabled = isBusy;
  checkControllerBtn.disabled = isBusy;
  checkTunnelBtn.disabled = isBusy;
}

function refreshButton() {
  toggleBtn.textContent = enabled ? "Выключить" : "Включить";
}

async function send(message) {
  const response = await chrome.runtime.sendMessage(message);
  if (!response?.ok) {
    throw new Error(response?.error || "Unknown error");
  }
  return response.result;
}

async function loadState() {
  const state = await send({ type: "get-state" });
  enabled = state.enabled;
  vlessInput.value = state.vlessUrl || "";
  refreshButton();

  if (state.lastError) {
    setStatus(state.lastError, "err");
  } else if (enabled) {
    setStatus(`Включено (SOCKS порт ${state.socksPort || "?"})`, "ok");
  } else {
    setStatus("Выключено");
  }
}

saveBtn.addEventListener("click", async () => {
  const vlessUrl = vlessInput.value.trim();
  await chrome.storage.local.set({ vlessUrl });
  setStatus("Сохранено", "ok");
});

checkControllerBtn.addEventListener("click", async () => {
  try {
    setBusy(true);
    const status = await send({ type: "controller-status" });
    if (status.running) {
      setStatus(`Контроллер работает (SOCKS порт ${status.socksPort || "?"})`, "ok");
    } else {
      setStatus("Контроллер доступен, но VPN сессия не запущена", "err");
    }
  } catch (err) {
    setStatus(`Проверка контроллера не пройдена: ${err instanceof Error ? err.message : String(err)}`, "err");
  } finally {
    setBusy(false);
  }
});

checkTunnelBtn.addEventListener("click", async () => {
  try {
    setBusy(true);
    const result = await send({ type: "test-connection" });
    setStatus(`Подключение работает. Текущий IP: ${result.ip}`, "ok");
  } catch (err) {
    setStatus(`Проверка подключения не пройдена: ${err instanceof Error ? err.message : String(err)}`, "err");
  } finally {
    setBusy(false);
  }
});

toggleBtn.addEventListener("click", async () => {
  try {
    setBusy(true);
    const vlessUrl = vlessInput.value.trim();

    if (!enabled && !vlessUrl) {
      setStatus("Сначала вставь VLESS ссылку", "err");
      return;
    }

    if (enabled) {
      await send({ type: "disable" });
      enabled = false;
      refreshButton();
      setStatus("Выключено", "ok");
      return;
    }

    const result = await send({ type: "enable", vlessUrl });
    enabled = true;
    refreshButton();
    setStatus(`Включено (SOCKS порт ${result.socksPort})`, "ok");
  } catch (err) {
    setStatus(err instanceof Error ? err.message : String(err), "err");
  } finally {
    setBusy(false);
  }
});

loadState().catch((err) => {
  setStatus(err instanceof Error ? err.message : String(err), "err");
});

setInterval(() => {
  loadState().catch(() => {});
}, 5000);
