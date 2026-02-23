# Chrome extension: VLESS VPN toggle

## IMPORTANT: how to get VLESS link

VLESS link is issued by request via support in personal cabinet:

1. Open https://cp.sevenskull.ru/login
2. Sign in
3. Create support ticket
4. Request VLESS configuration link (`vless://...`)

Without this link, VPN connection cannot be enabled.

This project contains:

- `extension/` - Chrome Extension (Manifest V3) with popup UI
- `controller/` - local Node.js controller that starts/stops Xray from a VLESS URL
- `install-windows.ps1` / `install-windows.bat` - automatic installer for Windows 7/10/11
- `install-marketplace-windows.ps1` / `install-marketplace-windows.bat` - companion installer for users from Chrome Web Store
- `uninstall-windows.ps1` / `uninstall-windows.bat` - full uninstall scripts
- `package-webstore.ps1` - build ZIP for Chrome Web Store upload
- `PRIVACY_POLICY.md` / `privacy-policy.html` - privacy policy templates
- `check-windows.ps1` / `check-windows.bat` - quick diagnostics on Windows

## Why a local controller is required

Chrome extensions cannot implement the VLESS protocol tunnel directly. The extension can only set browser proxy settings.

So the architecture is:

1. You paste a `vless://...` link in the extension popup
2. Extension sends the link to local controller (`127.0.0.1:23999`)
3. Controller starts `xray` with generated config and local SOCKS inbound (`127.0.0.1:10808`)
4. Extension enables Chrome proxy to `socks5://127.0.0.1:10808`

## Requirements

- Google Chrome
- Node.js 18+
- Xray installed and available in `PATH` as `xray`

## Auto install for Windows 7/10/11

Use this if you want easiest setup for non-technical users.

1. Run `install-windows.bat` (as Administrator recommended)
2. Wait for completion
3. Use desktop shortcut **VLESS VPN Chrome**
4. In extension popup: paste `vless://...` and click **Enable**

Installer details:

- Installs portable Node.js `v16.20.2` (good compatibility for older Windows)
- Installs Xray-core `v1.8.14`
- Creates autostart task `VlessChromeVpnController` (runs at logon)
- Starts controller immediately after install
- Creates desktop shortcuts:
  - `VLESS VPN Chrome`
  - `VLESS VPN Restart Controller`
  - `VLESS VPN Uninstall`

## Marketplace companion mode

Use this when extension is installed from Chrome Web Store:

1. Run `install-marketplace-windows.bat`
2. Install extension from Chrome Web Store
3. Open extension popup and click **Включить**

This mode installs only local runtime (controller + Node + Xray) required for VLESS tunnel.

## Run controller

```bash
cd controller
npm start
```

You should see:

`Controller listening on http://127.0.0.1:23999`

On Windows auto-install, this step is not required manually.

## Load extension in Chrome

1. Open `chrome://extensions`
2. Enable **Developer mode**
3. Click **Load unpacked**
4. Select the `extension` folder from this project

## Use

1. Open extension popup
2. Paste VLESS link (issued via support ticket in personal cabinet)
3. Click **Enable**
4. If you need a new config, use personal cabinet: https://cp.sevenskull.ru/login

If successful, badge becomes `ON` and status shows SOCKS port.

Click **Disable** to stop routing.

## Added reliability features

- Auto-restore after Chrome restart (if VPN was enabled)
- Health check every 1 minute from background worker
- Automatic re-apply/restart if controller/Xray session is missing
- Popup wizard buttons: controller check + connection test

## Notes

- Controller currently supports common VLESS options: `tcp`, `ws`, `grpc`, `tls`, `reality`
- If your URL uses exotic/rare transport settings, you may need to extend parser in `controller/server.js`
- This changes **browser** proxy, not full system VPN

## Full uninstall

- Run `uninstall-windows.bat`
- Or use desktop shortcut `VLESS VPN Uninstall`
