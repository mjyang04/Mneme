const {
  app,
  BrowserWindow,
  Menu,
  Tray,
  dialog,
  globalShortcut,
  ipcMain,
  nativeImage,
  shell
} = require("electron");
const http = require("node:http");
const path = require("node:path");
const { pathToFileURL } = require("node:url");

let backend = null;
let mainWindow = null;
let tray = null;
let isQuitting = false;

app.setAppUserModelId("local.mneme.windows");

function appRoot() {
  return app.getAppPath();
}

function assetPath(...parts) {
  return path.join(appRoot(), ...parts);
}

function iconPath() {
  const ico = assetPath("Assets", "AppIcon", "Mneme.ico");
  const png = assetPath("Assets", "AppIcon", "Mneme.png");
  return process.platform === "win32" ? ico : png;
}

async function startBackend() {
  const backendModuleURL = pathToFileURL(assetPath("Windows", "mneme-windows.mjs")).href;
  const { createWindowsDesktopBackend } = await import(backendModuleURL);
  backend = await createWindowsDesktopBackend({
    dataDir: app.getPath("userData"),
    port: 0,
    platformName: "windows-desktop"
  });
  const address = await backend.listen(0, "127.0.0.1");
  return `http://127.0.0.1:${address.port}`;
}

function getJson(url) {
  return new Promise((resolve, reject) => {
    const request = http.get(url, { timeout: 5_000 }, (response) => {
      let body = "";
      response.setEncoding("utf8");
      response.on("data", (chunk) => {
        body += chunk;
      });
      response.on("end", () => {
        if ((response.statusCode ?? 500) < 200 || (response.statusCode ?? 500) >= 300) {
          reject(new Error(`GET ${url} failed with ${response.statusCode}: ${body}`));
          return;
        }
        try {
          resolve(JSON.parse(body));
        } catch (error) {
          reject(error);
        }
      });
    });
    request.on("timeout", () => {
      request.destroy(new Error(`GET ${url} timed out.`));
    });
    request.on("error", reject);
  });
}

async function runPackagedSmoke(startURL) {
  const status = await getJson(`${startURL}/api/status`);
  if (status.platform !== "windows-desktop") {
    throw new Error(`Unexpected Mneme platform: ${status.platform}`);
  }
  console.log(`mneme.smoke.platform=${status.platform}`);
  console.log(`mneme.smoke.dataDir=${status.dataDir}`);
}

async function closeBackend() {
  if (!backend) return;
  const runningBackend = backend;
  backend = null;
  await runningBackend.close().catch(() => {});
}

async function exitAfterSmoke(code) {
  await closeBackend();
  app.exit(code);
}

function createWindow(startURL) {
  mainWindow = new BrowserWindow({
    width: 1180,
    height: 760,
    minWidth: 980,
    minHeight: 660,
    title: "Mneme",
    show: false,
    backgroundColor: "#f4f1ea",
    icon: iconPath(),
    webPreferences: {
      preload: assetPath("Windows", "desktop", "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false
    }
  });

  mainWindow.loadURL(startURL);
  mainWindow.once("ready-to-show", () => {
    mainWindow.show();
    mainWindow.focus();
  });
  mainWindow.on("close", (event) => {
    if (!isQuitting) {
      event.preventDefault();
      mainWindow.hide();
    }
  });
}

function showWindow() {
  if (!mainWindow) return;
  if (mainWindow.isMinimized()) {
    mainWindow.restore();
  }
  mainWindow.show();
  mainWindow.focus();
}

function toggleWindow() {
  if (!mainWindow) return;
  if (mainWindow.isVisible() && mainWindow.isFocused()) {
    mainWindow.hide();
    return;
  }
  showWindow();
}

function createTray() {
  const image = nativeImage.createFromPath(iconPath());
  const trayImage = process.platform === "win32" && !image.isEmpty()
    ? image.resize({ width: 16, height: 16 })
    : image;
  tray = new Tray(trayImage);
  tray.setToolTip("Mneme");
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: "Show Mneme", click: showWindow },
    {
      label: "Rebuild Index",
      click: () => mainWindow?.webContents.send("mneme:trigger-rebuild")
    },
    { type: "separator" },
    {
      label: "Quit",
      click: () => {
        isQuitting = true;
        app.quit();
      }
    }
  ]));
  tray.on("click", toggleWindow);
}

function registerShortcuts() {
  const registered = globalShortcut.register("Control+Space", toggleWindow);
  if (!registered) {
    console.warn("Could not register Control+Space global shortcut.");
  }
}

function registerIpc() {
  ipcMain.handle("mneme:select-source-folder", async () => {
    const result = await dialog.showOpenDialog(mainWindow, {
      title: "Add Mneme source folder",
      properties: ["openDirectory", "createDirectory"]
    });
    if (result.canceled || result.filePaths.length === 0) {
      return null;
    }
    return result.filePaths[0];
  });

  ipcMain.handle("mneme:open-path", async (_event, targetPath) => {
    if (typeof targetPath !== "string" || targetPath.trim() === "") {
      return { ok: false, error: "Path is required." };
    }
    const error = await shell.openPath(targetPath);
    return error ? { ok: false, error } : { ok: true };
  });

  ipcMain.handle("mneme:show-item-in-folder", async (_event, targetPath) => {
    if (typeof targetPath !== "string" || targetPath.trim() === "") {
      return { ok: false, error: "Path is required." };
    }
    shell.showItemInFolder(targetPath);
    return { ok: true };
  });
}

app.whenReady().then(async () => {
  registerIpc();
  const startURL = await startBackend();
  if (process.env.MNEME_ELECTRON_SMOKE === "1") {
    try {
      await runPackagedSmoke(startURL);
      await exitAfterSmoke(0);
    } catch (error) {
      console.error(error);
      await exitAfterSmoke(1);
    }
    return;
  }
  createWindow(startURL);
  createTray();
  registerShortcuts();
});

app.on("activate", showWindow);

app.on("before-quit", () => {
  isQuitting = true;
});

app.on("will-quit", () => {
  globalShortcut.unregisterAll();
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});

app.on("quit", async () => {
  await closeBackend();
});
