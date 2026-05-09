/* eslint-disable @typescript-eslint/no-require-imports */
const { app, BrowserWindow, ipcMain, shell } = require("electron");
const http = require("node:http");
const path = require("node:path");
const { execFile, spawn } = require("node:child_process");
const { promisify } = require("node:util");
const dotenv = require("dotenv");

function loadDotenvFiles() {
  /** Packaged apps often have cwd != install dir; also load next to .exe and in userData. */
  if (app.isPackaged) {
    const nextToExe = path.dirname(process.execPath);
    let userData = "";
    try {
      userData = app.getPath("userData");
    } catch {
      // ignore before paths are ready (rare)
    }
    const roots = [nextToExe, userData].filter(Boolean);
    const files = [];
    for (const root of roots) {
      files.push(path.join(root, ".env"), path.join(root, ".env.local"));
    }
    for (const file of files) {
      dotenv.config({ path: file, override: true });
    }
  } else {
    dotenv.config({ path: path.join(process.cwd(), ".env") });
    dotenv.config({ path: path.join(process.cwd(), ".env.local"), override: true });
  }
}

loadDotenvFiles();

let mainWindow = null;
const execFileAsync = promisify(execFile);
let apiServer = null;
let cloudflareProcess = null;
let lastJobId = 0;
let messageQueue = Promise.resolve();
const apiLogs = [];
const maxApiLogs = 300;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 520,
    height: 500,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadFile(path.join(__dirname, "renderer", "index.html"));
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function appendApiLog(message) {
  const entry = {
    ts: new Date().toISOString(),
    message,
  };

  apiLogs.push(entry);
  if (apiLogs.length > maxApiLogs) {
    apiLogs.shift();
  }

  console.log(`[api] ${message}`);
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send("viber:log", entry);
  }
}

function normalizePhoneNumber(rawPhone) {
  return String(rawPhone || "").replace(/[^\d+]/g, "");
}

async function closeViberProcess() {
  try {
    await execFileAsync("powershell", [
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy",
      "Bypass",
      "-Command",
      "Get-Process | Where-Object { $_.ProcessName -match '(?i)viber' } | Stop-Process -Force -ErrorAction SilentlyContinue",
    ]);
  } catch {
    // Ignore close errors; process may not be running.
  }
}

async function openViberChatByPhone(phoneNumber) {
  const phone = normalizePhoneNumber(phoneNumber);
  if (!phone) {
    return null;
  }

  const digitsOnly = phone.replace(/[^\d]/g, "");
  const plusPhone = phone.startsWith("+") ? phone : `+${digitsOnly}`;
  const link = `viber://chat?number=${encodeURIComponent(plusPhone)}`;
  try {
    // Launch the protocol handler from a hidden PowerShell process.
    await execFileAsync("powershell", [
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy",
      "Bypass",
      "-WindowStyle",
      "Hidden",
      "-Command",
      `Start-Process "${link}" -WindowStyle Hidden`,
    ]);
    await sleep(1200);
    return { method: "hidden-protocol", detail: link };
  } catch {
    try {
      await shell.openExternal(link);
      await sleep(800);
      return { method: "deeplink", detail: link };
    } catch {
      return null;
    }
  }
}

async function sendMessageToViber(message, options = {}) {
  if (!message || !message.trim()) {
    return {
      ok: false,
      message: "Message cannot be empty.",
    };
  }

  const inputOffsetBottom = Number(process.env.VIBER_INPUT_OFFSET_BOTTOM || 70);
  const inputXPercent = Number(process.env.VIBER_INPUT_X_PERCENT || 50);
  const skipEnter = Boolean(options.skipEnter);

  try {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.minimize();
    }

    await execFileAsync("powershell", [
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      path.join(__dirname, "scripts", "send-viber.ps1"),
      "-Message",
      message.trim(),
      "-InputOffsetBottom",
      String(inputOffsetBottom),
      "-InputXPercent",
      String(inputXPercent),
      ...(skipEnter ? ["-SkipEnter"] : []),
    ]);
  } catch (error) {
    return {
      ok: false,
      message: `Failed to type/send: ${error.stderr || "unknown error"}`,
    };
  }

  return {
    ok: true,
    message: skipEnter
      ? "Message pasted (debug mode, Enter skipped)."
      : "Message pasted and sent with Enter.",
  };
}

async function restartOpenAndSend(phoneNumber, message) {
  if (!message || !message.trim()) {
    return {
      ok: false,
      message: "Message cannot be empty.",
    };
  }

  const phone = normalizePhoneNumber(phoneNumber);
  if (!phone) {
    return {
      ok: false,
      message: "Phone number is required.",
    };
  }

  await closeViberProcess();
  await sleep(1000);

  const openedLink = await openViberChatByPhone(phone);
  if (!openedLink) {
    return {
      ok: false,
      message: "Could not open Viber chat via deeplink.",
    };
  }

  await sleep(2800);
  await sleep(1500);

  const sendResult = await sendMessageToViber(message.trim(), { skipEnter: false });
  if (!sendResult.ok) {
    return sendResult;
  }

  return {
    ok: true,
    message: openedLink
      ? openedLink.method === "hidden-protocol"
        ? `Opened by hidden protocol launch: ${openedLink.detail}. Message pasted and sent.`
        : openedLink.method === "deeplink"
        ? `Opened by deeplink: ${openedLink.detail}. Message pasted and sent.`
        : `Opened chat: ${openedLink.detail}. Message pasted and sent.`
      : "Could not confirm opening chat by number. Message pasted and sent.",
  };
}

function jsonResponse(res, statusCode, payload) {
  res.writeHead(statusCode, { "Content-Type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(payload));
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk.toString("utf8");
      if (body.length > 1024 * 1024) {
        reject(new Error("Body too large"));
      }
    });
    req.on("end", () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch {
        reject(new Error("Invalid JSON"));
      }
    });
    req.on("error", (error) => reject(error));
  });
}

function isAuthorized(req) {
  const expectedKey = process.env.VIBER_API_KEY;
  if (!expectedKey) {
    return true;
  }

  const headerKey = req.headers["x-api-key"];
  return typeof headerKey === "string" && headerKey === expectedKey;
}

function enqueueSendJob(phoneNumber, message) {
  const jobId = ++lastJobId;
  const startedAt = Date.now();

  messageQueue = messageQueue
    .catch(() => {
      // Keep queue alive even if previous job failed.
    })
    .then(async () => {
      const result = await restartOpenAndSend(phoneNumber, message);
      return {
        jobId,
        queuedAt: startedAt,
        completedAt: Date.now(),
        result,
      };
    });

  return messageQueue;
}

function startApiServer() {
  const port = Number(process.env.VIBER_API_PORT || 8787);
  const host = process.env.VIBER_API_HOST || "0.0.0.0";

  apiServer = http.createServer(async (req, res) => {
    const method = req.method || "GET";
    const url = req.url || "/";
    const startedAt = Date.now();
    const ip =
      req.headers["x-forwarded-for"]?.toString().split(",")[0]?.trim() ||
      req.socket.remoteAddress ||
      "unknown";

    function logResponse(statusCode) {
      const elapsedMs = Date.now() - startedAt;
      appendApiLog(`${method} ${url} from=${ip} status=${statusCode} ms=${elapsedMs}`);
    }

    if (method === "GET" && url === "/health") {
      appendApiLog(`incoming ${method} ${url} from=${ip}`);
      jsonResponse(res, 200, {
        ok: true,
        service: "viber-desktop-sender",
        queueActive: true,
      });
      logResponse(200);
      return;
    }

    if (method === "POST" && url === "/send") {
      appendApiLog(`incoming ${method} ${url} from=${ip}`);
      if (!isAuthorized(req)) {
        jsonResponse(res, 401, {
          ok: false,
          error: "Unauthorized. Provide x-api-key header.",
        });
        logResponse(401);
        return;
      }

      let payload;
      try {
        payload = await readJsonBody(req);
      } catch (error) {
        jsonResponse(res, 400, {
          ok: false,
          error: error.message,
        });
        logResponse(400);
        return;
      }

      const phoneNumber = String(payload.phoneNumber || "");
      const message = String(payload.message || "");
      appendApiLog(`payload phone=${phoneNumber || "<empty>"} messageLength=${message.length}`);
      if (!phoneNumber.trim() || !message.trim()) {
        jsonResponse(res, 400, {
          ok: false,
          error: "phoneNumber and message are required.",
        });
        logResponse(400);
        return;
      }

      try {
        const job = await enqueueSendJob(phoneNumber, message);
        const status = job.result.ok ? 200 : 500;
        jsonResponse(res, status, {
          ok: job.result.ok,
          jobId: job.jobId,
          queuedAt: job.queuedAt,
          completedAt: job.completedAt,
          result: job.result,
        });
        logResponse(status);
      } catch (error) {
        jsonResponse(res, 500, {
          ok: false,
          error: error.message || "Unexpected server error.",
        });
        logResponse(500);
      }
      return;
    }

    jsonResponse(res, 404, {
      ok: false,
      error: "Not found.",
    });
    logResponse(404);
  });

  apiServer.listen(port, host);
  appendApiLog(`server listening on ${host}:${port}`);
}

function startCloudflareTunnel() {
  const enabled = String(process.env.CLOUDFLARE_TUNNEL_ENABLED || "").toLowerCase() === "true";
  if (!enabled) {
    appendApiLog("cloudflare tunnel disabled (CLOUDFLARE_TUNNEL_ENABLED != true)");
    return;
  }

  const port = Number(process.env.VIBER_API_PORT || 8787);
  const host = process.env.VIBER_API_HOST || "127.0.0.1";
  const tunnelUrl = `http://${host}:${port}`;
  const cloudflaredPath = process.env.CLOUDFLARED_PATH || "cloudflared";

  appendApiLog(`starting Cloudflare tunnel for ${tunnelUrl}`);
  cloudflareProcess = spawn(cloudflaredPath, ["tunnel", "--url", tunnelUrl, "--no-autoupdate"], {
    windowsHide: true,
    stdio: ["ignore", "pipe", "pipe"],
  });

  function handleCloudflaredOutput(prefix, chunk) {
    const text = chunk.toString("utf8");
    const lines = text.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
    for (const line of lines) {
      appendApiLog(`${prefix}: ${line}`);
      const matches = line.match(/https:\/\/[a-z0-9-]+\.trycloudflare\.com/gi);
      if (matches) {
        for (const url of matches) {
          appendApiLog(`public URL: ${url}`);
        }
      }
    }
  }

  cloudflareProcess.stdout.on("data", (chunk) => handleCloudflaredOutput("cloudflared", chunk));
  cloudflareProcess.stderr.on("data", (chunk) => handleCloudflaredOutput("cloudflared", chunk));

  cloudflareProcess.on("error", (error) => {
    appendApiLog(`cloudflared failed to start: ${error.message}`);
  });

  cloudflareProcess.on("close", (code) => {
    appendApiLog(`cloudflared exited with code ${code}`);
    cloudflareProcess = null;
  });
}

app.whenReady().then(() => {
  createWindow();
  startApiServer();
  startCloudflareTunnel();

  ipcMain.handle("viber:restart-open-send", async (_event, phoneNumber, message) =>
    restartOpenAndSend(phoneNumber, message),
  );
  ipcMain.handle("viber:get-logs", async () => apiLogs);

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on("window-all-closed", () => {
  if (cloudflareProcess) {
    cloudflareProcess.kill();
    cloudflareProcess = null;
  }
  if (apiServer) {
    apiServer.close();
  }
  if (process.platform !== "darwin") {
    app.quit();
  }
});
