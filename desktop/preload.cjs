const { contextBridge, ipcRenderer, webUtils } = require('electron');
const invoke = async (action, ...args) => {
  const result = await ipcRenderer.invoke('seal:invoke', action, ...args);
  if (!result.ok) throw new Error(result.error);
  return result.value;
};
const subscribe = (channel, fn) => {
  const listener = (_event, value) => fn(value);
  ipcRenderer.on(channel, listener);
  return () => ipcRenderer.removeListener(channel, listener);
};
contextBridge.exposeInMainWorld('seal', {
  initialState: () => invoke('initialState'),
  chooseTargets: () => invoke('chooseTargets'),
  acceptFiles: (files) => invoke('adopt', Array.from(files, (file) => webUtils.getPathForFile(file)).filter(Boolean)),
  inspect: (path) => invoke('inspect', path),
  preview: (path, identity, options, existing) => invoke('preview', path, identity, options, existing),
  identities: () => invoke('identities'),
  sign: (path, identity, options) => invoke('sign', path, identity, options),
  chooseEntitlements: () => invoke('chooseEntitlements'),
  removeXattr: (path, name, recursive) => invoke('removeXattr', path, name, recursive),
  clearXattrs: (path, recursive) => invoke('clearXattrs', path, recursive),
  reveal: (path) => invoke('reveal', path),
  copy: (text) => invoke('copy', text),
  resize: (preset) => invoke('resize', preset),
  onCommand: (fn) => subscribe('seal:command', fn),
  onOpen: (fn) => subscribe('seal:open', fn),
  onMenu: (fn) => subscribe('seal:menu', fn),
});
