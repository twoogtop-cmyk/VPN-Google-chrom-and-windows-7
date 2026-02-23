#!/usr/bin/env node

const http = require("http");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");

const HOST = "127.0.0.1";
const PORT = 23999;
const SOCKS_PORT = 10808;

let xrayProcess = null;
let activeConfigPath = null;
let activeVlessUrl = null;

function resolveXrayBin() {
  if (process.env.XRAY_BIN) {
    return process.env.XRAY_BIN;
  }

  const rootDir = path.resolve(__dirname, "..");
  if (process.platform === "win32") {
    const bundledWin = path.join(rootDir, "xray", "xray.exe");
    if (fs.existsSync(bundledWin)) return bundledWin;
    return "xray.exe";
  }

  const bundledUnix = path.join(rootDir, "xray", "xray");
  if (fs.existsSync(bundledUnix)) return bundledUnix;
  return "xray";
}

function json(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(body)
  });
  res.end(body);
}

function parseBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => {
      if (!chunks.length) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString("utf8")));
      } catch {
        reject(new Error("Invalid JSON body"));
      }
    });
    req.on("error", reject);
  });
}

function parseVless(rawUrl) {
  let url;
  try {
    url = new URL(rawUrl);
  } catch {
    throw new Error("Invalid VLESS URL");
  }

  if (url.protocol !== "vless:") {
    throw new Error("URL must start with vless://");
  }

  const uuid = decodeURIComponent(url.username || "").trim();
  const address = (url.hostname || "").trim();
  const port = Number(url.port);
  if (!uuid || !address || !port) {
    throw new Error("VLESS URL must include uuid@host:port");
  }

  const params = url.searchParams;
  const network = (params.get("type") || "tcp").toLowerCase();
  const security = (params.get("security") || "none").toLowerCase();
  const flow = params.get("flow") || "";
  const serverName = params.get("sni") || params.get("serverName") || "";

  const streamSettings = {
    network,
    security
  };

  if (network === "ws") {
    streamSettings.wsSettings = {
      path: params.get("path") || "/",
      headers: {}
    };
    const hostHeader = params.get("host");
    if (hostHeader) {
      streamSettings.wsSettings.headers.Host = hostHeader;
    }
  }

  if (network === "grpc") {
    streamSettings.grpcSettings = {
      serviceName: params.get("serviceName") || "",
      multiMode: (params.get("mode") || "") === "multi"
    };
  }

  if (security === "tls") {
    streamSettings.tlsSettings = {
      serverName: serverName || undefined,
      allowInsecure: false,
      alpn: (params.get("alpn") || "").split(",").map((v) => v.trim()).filter(Boolean)
    };
  }

  if (security === "reality") {
    const publicKey = params.get("pbk") || "";
    if (!publicKey) {
      throw new Error("Reality config requires pbk parameter");
    }
    streamSettings.realitySettings = {
      show: false,
      fingerprint: params.get("fp") || "chrome",
      serverName: serverName || "",
      publicKey,
      shortId: params.get("sid") || "",
      spiderX: params.get("spx") || "/"
    };
  }

  return {
    address,
    port,
    uuid,
    flow,
    encryption: params.get("encryption") || "none",
    streamSettings
  };
}

function buildConfig(vlessUrl) {
  const parsed = parseVless(vlessUrl);

  return {
    log: { loglevel: "warning" },
    inbounds: [
      {
        tag: "socks-in",
        listen: HOST,
        port: SOCKS_PORT,
        protocol: "socks",
        settings: {
          auth: "noauth",
          udp: true,
          ip: HOST
        }
      }
    ],
    outbounds: [
      {
        tag: "proxy",
        protocol: "vless",
        settings: {
          vnext: [
            {
              address: parsed.address,
              port: parsed.port,
              users: [
                {
                  id: parsed.uuid,
                  encryption: parsed.encryption,
                  flow: parsed.flow || undefined
                }
              ]
            }
          ]
        },
        streamSettings: parsed.streamSettings
      }
    ]
  };
}

function writeConfig(config) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "xray-ext-"));
  const configPath = path.join(dir, "config.json");
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  return configPath;
}

function stopXray() {
  if (!xrayProcess) return;
  xrayProcess.kill("SIGTERM");
  xrayProcess = null;
  activeVlessUrl = null;
  if (activeConfigPath) {
    try {
      fs.rmSync(path.dirname(activeConfigPath), { recursive: true, force: true });
    } catch {
      // ignore cleanup error
    }
    activeConfigPath = null;
  }
}

function startXray(vlessUrl) {
  stopXray();

  const configPath = writeConfig(buildConfig(vlessUrl));
  const xrayBin = resolveXrayBin();
  const proc = spawn(xrayBin, ["run", "-config", configPath], {
    stdio: ["ignore", "pipe", "pipe"]
  });

  proc.stdout.on("data", (data) => {
    process.stdout.write(`[xray] ${data.toString()}`);
  });
  proc.stderr.on("data", (data) => {
    process.stderr.write(`[xray] ${data.toString()}`);
  });

  proc.on("exit", () => {
    if (xrayProcess === proc) {
      xrayProcess = null;
      activeVlessUrl = null;
    }
  });

  xrayProcess = proc;
  activeConfigPath = configPath;
  activeVlessUrl = vlessUrl;

  return SOCKS_PORT;
}

const server = http.createServer(async (req, res) => {
  try {
    if (req.method !== "POST") {
      json(res, 405, { error: "Only POST is supported" });
      return;
    }

    if (req.url === "/session/start") {
      const body = await parseBody(req);
      if (!body.vlessUrl) {
        json(res, 400, { error: "vlessUrl is required" });
        return;
      }

      const socksPort = startXray(String(body.vlessUrl));
      json(res, 200, { ok: true, socksPort });
      return;
    }

    if (req.url === "/session/stop") {
      stopXray();
      json(res, 200, { ok: true });
      return;
    }

    if (req.url === "/session/status") {
      json(res, 200, {
        ok: true,
        running: Boolean(xrayProcess),
        socksPort: xrayProcess ? SOCKS_PORT : null,
        hasConfig: Boolean(activeVlessUrl)
      });
      return;
    }

    json(res, 404, { error: "Not found" });
  } catch (err) {
    json(res, 500, {
      error: err instanceof Error ? err.message : String(err)
    });
  }
});

server.listen(PORT, HOST, () => {
  process.stdout.write(`Controller listening on http://${HOST}:${PORT}\n`);
});

function shutdown() {
  stopXray();
  server.close(() => process.exit(0));
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
