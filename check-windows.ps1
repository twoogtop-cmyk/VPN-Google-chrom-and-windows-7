$ErrorActionPreference = "Continue"

function Show-Ok($text) {
  Write-Host "[OK] $text" -ForegroundColor Green
}

function Show-Warn($text) {
  Write-Host "[WARN] $text" -ForegroundColor Yellow
}

function Show-Err($text) {
  Write-Host "[ERR] $text" -ForegroundColor Red
}

$installRoot = Join-Path $env:LOCALAPPDATA "VlessChromeVpn"
$controllerScript = Join-Path $installRoot "controller\server.js"
$nodeExe = Join-Path $installRoot "runtime\node\node.exe"
$xrayExe = Join-Path $installRoot "runtime\xray\xray.exe"
$taskName = "VlessChromeVpnController"

Write-Host "=== VLESS VPN Quick Check ==="

if (Test-Path $installRoot) { Show-Ok "Install folder found: $installRoot" } else { Show-Err "Install folder not found" }
if (Test-Path $controllerScript) { Show-Ok "Controller script found" } else { Show-Err "Controller script missing" }
if (Test-Path $nodeExe) { Show-Ok "Portable Node found" } else { Show-Err "Portable Node missing" }
if (Test-Path $xrayExe) { Show-Ok "Xray found" } else { Show-Err "Xray missing" }

$taskInfo = & schtasks /Query /TN $taskName 2>$null
if ($LASTEXITCODE -eq 0) {
  Show-Ok "Startup task exists: $taskName"
} else {
  Show-Warn "Startup task not found: $taskName"
}

try {
  $status = Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:23999/session/status" -Body "{}" -ContentType "application/json" -TimeoutSec 3
  if ($status.ok) {
    if ($status.running) {
      Show-Ok "Controller reachable, VPN session running, SOCKS: $($status.socksPort)"
    } else {
      Show-Warn "Controller reachable, but VPN session is not running"
    }
  } else {
    Show-Warn "Controller reachable, unexpected response"
  }
} catch {
  Show-Err "Controller is not reachable on 127.0.0.1:23999"
  Show-Warn "Try desktop shortcut: VLESS VPN Restart Controller"
}

Write-Host ""
Write-Host "If extension still fails:" 
Write-Host "1) Open Chrome via shortcut: VLESS VPN Chrome"
Write-Host "2) In popup click: Проверить контроллер"
Write-Host "3) Then click: Проверить подключение"
