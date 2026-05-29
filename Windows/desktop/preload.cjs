const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("mnemeDesktop", {
  isDesktop: true,
  platform: process.platform,
  selectSourceFolder: () => ipcRenderer.invoke("mneme:select-source-folder"),
  openPath: (targetPath) => ipcRenderer.invoke("mneme:open-path", targetPath),
  showItemInFolder: (targetPath) => ipcRenderer.invoke("mneme:show-item-in-folder", targetPath),
  onTriggerRebuild: (callback) => {
    if (typeof callback !== "function") {
      return () => {};
    }
    const listener = () => callback();
    ipcRenderer.on("mneme:trigger-rebuild", listener);
    return () => ipcRenderer.removeListener("mneme:trigger-rebuild", listener);
  }
});
