/* eslint-disable @typescript-eslint/no-require-imports */
const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("viberDesktop", {
  restartOpenAndSend: (phoneNumber, message) =>
    ipcRenderer.invoke("viber:restart-open-send", phoneNumber, message),
  getLogs: () => ipcRenderer.invoke("viber:get-logs"),
  getPublicTunnelUrl: () => ipcRenderer.invoke("viber:get-public-tunnel-url"),
  onLog: (callback) => {
    const handler = (_event, entry) => callback(entry);
    ipcRenderer.on("viber:log", handler);
    return () => ipcRenderer.removeListener("viber:log", handler);
  },
  onTunnelUrl: (callback) => {
    const handler = (_event, payload) => callback(payload);
    ipcRenderer.on("viber:tunnel-url", handler);
    return () => ipcRenderer.removeListener("viber:tunnel-url", handler);
  },
});
