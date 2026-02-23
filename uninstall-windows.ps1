$ErrorActionPreference = "Stop"

function Write-Step($text) {
  Write-Host "[VLESS Uninstall] $text"
}

$installRoot = Join-Path $env:LOCALAPPDATA "VlessChromeVpn"
$taskName = "VlessChromeVpnController"

$desktop = [Environment]::GetFolderPath("Desktop")
$chromeShortcutPath = Join-Path $desktop "VLESS VPN Chrome.lnk"
$restartShortcutPath = Join-Path $desktop "VLESS VPN Restart Controller.lnk"
$uninstallShortcutPath = Join-Path $desktop "VLESS VPN Uninstall.lnk"

Write-Step "Stopping startup task"
try {
  & schtasks /End /TN $taskName 2>$null | Out-Null
} catch {
}
try {
  & schtasks /Delete /TN $taskName /F 2>$null | Out-Null
} catch {
}

Write-Step "Removing per-user startup registry entry"
try {
  Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "VlessChromeVpnController" -ErrorAction SilentlyContinue
} catch {
}

Write-Step "Stopping running controller process"
try {
  try {
    Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:23999/session/stop" -Body "{}" -ContentType "application/json" -TimeoutSec 2 | Out-Null
  } catch {
  }

  $nodePath = Join-Path $installRoot "runtime\node\node.exe"
  $xrayPath = Join-Path $installRoot "runtime\xray\xray.exe"

  $all = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue
  foreach ($proc in $all) {
    if ($proc.ExecutablePath -and ($proc.ExecutablePath -ieq $nodePath -or $proc.ExecutablePath -ieq $xrayPath)) {
      try {
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
      } catch {
      }
    }
  }

  $procs = Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -and $_.CommandLine -like "*VlessChromeVpn*controller\\server.js*"
  }
  foreach ($p in $procs) {
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
  }
} catch {
}

Write-Step "Removing installed files"
if (Test-Path $installRoot) {
  $removed = $false
  for ($i = 0; $i -lt 5; $i++) {
    try {
      Remove-Item $installRoot -Recurse -Force -ErrorAction Stop
      $removed = $true
      break
    } catch {
      Start-Sleep -Milliseconds 800
      try {
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
          $_.ExecutablePath -and ($_.ExecutablePath -like "*$installRoot*")
        } | ForEach-Object {
          Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
      } catch {
      }
    }
  }

  if (-not $removed) {
    Write-Host "[WARN] Some files are locked. Reboot Windows and run uninstall again." -ForegroundColor Yellow
  }
}

Write-Step "Removing desktop shortcuts"
if (Test-Path $chromeShortcutPath) { Remove-Item $chromeShortcutPath -Force }
if (Test-Path $restartShortcutPath) { Remove-Item $restartShortcutPath -Force }
if (Test-Path $uninstallShortcutPath) { Remove-Item $uninstallShortcutPath -Force }

Write-Host ""
Write-Host "Uninstall completed."
