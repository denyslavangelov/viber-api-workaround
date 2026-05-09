/* eslint-disable @typescript-eslint/no-require-imports */
const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("viberDesktop", {
  restartOpenAndSend: (phoneNumber, message) =>
    ipcRenderer.invoke("viber:restart-open-send", phoneNumber, message),
  getLogs: () => ipcRenderer.invoke("viber:get-logs"),
  onLog: (callback) => {
    const handler = (_event, entry) => callback(entry);
    ipcRenderer.on("viber:log", handler);
    return () => ipcRenderer.removeListener("viber:log", handler);
  },
});
