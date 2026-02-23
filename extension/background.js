const CONTROLLER_BASE = "http://127.0.0.1:23999";
const HEALTH_ALARM = "vpn-health-check";
const HEALTH_PERIOD_MINUTES = 1;
let opQueue = Promise.resolve();

function queueOp(operation) {
  opQueue = opQueue.then(operation, operation);
  return opQueue;
}

function setBadge(state) {
  if (state === "on") {
    chrome.action.setBadgeText({ text: "ON" });
    chrome.action.setBadgeBackgroundColor({ color: "#1a7f37" });
    return;
  }

  if (state === "error") {
    chrome.action.setBadgeText({ text: "ERR" });
    chrome.action.setBadgeBackgroundColor({ color: "#be123c" });
    return;
  }

  chrome.action.setBadgeText({ text: "OFF" });
  chrome.action.setBadgeBackgroundColor({ color: "#6b7280" });
}

async function callController(path, payload, timeoutMs = 5000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  let res;
  try {
    res = await fetch(`${CONTROLLER_BASE}${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload || {}),
      signal: controller.signal
    });
  } catch (err) {
    if (err instanceof Error && err.name === "AbortError") {
      throw new Error("Controller timeout");
    }
    throw err;
  } finally {
    clearTimeout(timer);
  }

  if (!res.ok) {
    let detail = "";
    try {
      const data = await res.json();
      detail = data.error || JSON.stringify(data);
    } catch {
      detail = await res.text();
    }
    throw new Error(detail || `Controller error ${res.status}`);
  }

  return res.json();
}

async function fetchJsonWithTimeout(url, timeoutMs = 7000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: controller.signal, cache: "no-store" });
    if (!res.ok) {
      throw new Error(`HTTP ${res.status}`);
    }
    return res.json();
  } catch (err) {
    if (err instanceof Error && err.name === "AbortError") {
      throw new Error("Network timeout");
    }
    throw err;
  } finally {
    clearTimeout(timer);
  }
}

async function readState() {
  return chrome.storage.local.get(["enabled", "vlessUrl", "socksPort", "lastError"]);
}

async function writeState(patch) {
  await chrome.storage.local.set(patch);
}

async function setEnabledState(enabled, extra = {}) {
  await writeState({ enabled, ...extra });
  setBadge(enabled ? "on" : "off");
}

async function markError(error) {
  await writeState({ lastError: error });
  setBadge("error");
}

async function applyProxy(port) {
  await chrome.proxy.settings.set({
    value: {
      mode: "fixed_servers",
      rules: {
        singleProxy: {
          scheme: "socks5",
          host: "127.0.0.1",
          port
        },
        bypassList: ["<local>", "localhost", "127.0.0.1"]
      }
    },
    scope: "regular"
  });
}

async function clearProxy() {
  await chrome.proxy.settings.clear({ scope: "regular" });
}

function parseVlessUrl(raw) {
  let url;
  try {
    url = new URL(raw);
  } catch {
    throw new Error("Invalid URL format");
  }

  if (url.protocol !== "vless:") {
    throw new Error("Only vless:// links are supported");
  }

  if (!url.username || !url.hostname || !url.port) {
    throw new Error("VLESS link must include uuid@host:port");
  }

  return {
    protocol: url.protocol,
    uuid: url.username,
    host: url.hostname,
    port: Number(url.port)
  };
}

async function enableVpn(vlessUrl) {
  parseVlessUrl(vlessUrl);
  const started = await callController("/session/start", { vlessUrl });
  const socksPort = Number(started.socksPort || 10808);

  await applyProxy(socksPort);
  await setEnabledState(true, { vlessUrl, socksPort, lastError: "" });

  return { enabled: true, socksPort };
}

async function disableVpn() {
  await clearProxy();
  try {
    await callController("/session/stop", {});
  } catch {
    // If controller is already down, proxy is already disabled.
  }

  await setEnabledState(false, { socksPort: null, lastError: "" });
  return { enabled: false };
}

async function restoreSession() {
  const state = await readState();

  if (!state.enabled) {
    setBadge("off");
    return { enabled: false };
  }

  if (!state.vlessUrl) {
    await setEnabledState(false, { lastError: "VLESS link is not set", socksPort: null });
    return { enabled: false };
  }

  try {
    const status = await callController("/session/status", {}, 2500);
    const socksPort = Number(status.socksPort || 10808);

    if (!status.running) {
      return enableVpn(state.vlessUrl);
    }

    await applyProxy(socksPort);
    await writeState({ socksPort, lastError: "" });
    setBadge("on");
    return { enabled: true, socksPort };
  } catch (err) {
    const error = err instanceof Error ? err.message : String(err);
    await markError(error);
    return { enabled: true, error };
  }
}

async function runHealthCheck() {
  const state = await readState();
  if (!state.enabled) {
    setBadge("off");
    return;
  }
  await restoreSession();
}

chrome.runtime.onInstalled.addListener(async () => {
  await chrome.alarms.create(HEALTH_ALARM, { periodInMinutes: HEALTH_PERIOD_MINUTES });
  await queueOp(restoreSession);
});

chrome.runtime.onStartup.addListener(async () => {
  await chrome.alarms.create(HEALTH_ALARM, { periodInMinutes: HEALTH_PERIOD_MINUTES });
  await queueOp(restoreSession);
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name !== HEALTH_ALARM) return;
  queueOp(runHealthCheck);
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  const run = async () => {
    if (message.type === "get-state") {
      const state = await readState();
      return {
        enabled: Boolean(state.enabled),
        vlessUrl: state.vlessUrl || "",
        socksPort: state.socksPort || null,
        lastError: state.lastError || ""
      };
    }

    if (message.type === "enable") {
      return enableVpn(message.vlessUrl);
    }

    if (message.type === "disable") {
      return disableVpn();
    }

    if (message.type === "controller-status") {
      const status = await callController("/session/status", {}, 2500);
      return {
        ok: true,
        running: Boolean(status.running),
        socksPort: status.socksPort || null
      };
    }

    if (message.type === "test-connection") {
      const state = await readState();
      if (!state.enabled) {
        throw new Error("VPN выключен. Сначала нажмите Включить.");
      }
      const ipData = await fetchJsonWithTimeout("https://api.ipify.org/?format=json", 8000);
      return {
        ok: true,
        ip: ipData.ip || "unknown"
      };
    }

    throw new Error("Unknown message type");
  };

  queueOp(run)
    .then((result) => sendResponse({ ok: true, result }))
    .catch(async (err) => {
      const error = err instanceof Error ? err.message : String(err);
      await markError(error);
      sendResponse({ ok: false, error });
    });

  return true;
});
