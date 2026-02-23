$ErrorActionPreference = "Stop"

function Write-Step($text) {
  Write-Host "[VLESS Companion] $text"
}

function Ensure-Tls12 {
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  } catch {
  }
}

function Download-File($url, $outFile) {
  Ensure-Tls12
  Write-Step "Downloading: $url"
  $wc = New-Object Net.WebClient
  $wc.DownloadFile($url, $outFile)
}

function Download-FileWithFallback($urls, $outFile, $name) {
  $lastError = $null
  foreach ($url in $urls) {
    try {
      Download-File $url $outFile
      Write-Step "$name downloaded successfully"
      return
    } catch {
      $lastError = $_
      Write-Step "Failed URL, trying next mirror"
    }
  }
  throw "Failed to download $name. Last error: $lastError"
}

function Expand-ZipCompat($zipPath, $destDir) {
  if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) {
    Expand-Archive -Path $zipPath -DestinationPath $destDir -Force
    return
  }

  $shell = New-Object -ComObject shell.application
  $zip = $shell.NameSpace($zipPath)
  $dest = $shell.NameSpace($destDir)
  if ($null -eq $zip -or $null -eq $dest) {
    throw "Failed to extract archive: $zipPath"
  }
  $dest.CopyHere($zip.Items(), 0x10)
  Start-Sleep -Seconds 2
}

function Ensure-Dir($path) {
  if (!(Test-Path $path)) {
    New-Item -ItemType Directory -Path $path | Out-Null
  }
}

function Create-Shortcut($shortcutPath, $targetPath, $arguments, $workingDir, $description, $iconLocation) {
  $wsh = New-Object -ComObject WScript.Shell
  $shortcut = $wsh.CreateShortcut($shortcutPath)
  $shortcut.TargetPath = $targetPath
  $shortcut.Arguments = $arguments
  $shortcut.WorkingDirectory = $workingDir
  $shortcut.Description = $description
  if ($iconLocation) {
    $shortcut.IconLocation = $iconLocation
  }
  $shortcut.Save()
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$installRoot = Join-Path $env:LOCALAPPDATA "VlessChromeVpn"
$runtimeRoot = Join-Path $installRoot "runtime"
$controllerTarget = Join-Path $installRoot "controller"
$xrayTarget = Join-Path $runtimeRoot "xray"
$nodeTarget = Join-Path $runtimeRoot "node"

$desktop = [Environment]::GetFolderPath("Desktop")
$restartShortcutPath = Join-Path $desktop "VLESS VPN Restart Controller.lnk"
$uninstallShortcutPath = Join-Path $desktop "VLESS VPN Uninstall.lnk"
$storeShortcutPath = Join-Path $desktop "VLESS VPN Установить расширение.lnk"

Write-Step "Installing companion to: $installRoot"
Ensure-Dir $installRoot
Ensure-Dir $runtimeRoot

Write-Step "Copying controller files"
if (Test-Path $controllerTarget) { Remove-Item $controllerTarget -Recurse -Force }
Copy-Item -Path (Join-Path $scriptRoot "controller") -Destination $controllerTarget -Recurse -Force

$nodeVersion = "v16.20.2"
$nodeZip = Join-Path $env:TEMP "node-$nodeVersion-win-x64.zip"
$nodeUrl = "https://nodejs.org/dist/$nodeVersion/node-$nodeVersion-win-x64.zip"

Write-Step "Installing portable Node.js $nodeVersion"
if (Test-Path $nodeTarget) { Remove-Item $nodeTarget -Recurse -Force }
Ensure-Dir $nodeTarget
Download-File $nodeUrl $nodeZip
$nodeExtract = Join-Path $env:TEMP "node-$nodeVersion-unpack"
if (Test-Path $nodeExtract) { Remove-Item $nodeExtract -Recurse -Force }
Ensure-Dir $nodeExtract
Expand-ZipCompat $nodeZip $nodeExtract
$nodeInner = Get-ChildItem -Path $nodeExtract -Directory | Select-Object -First 1
if ($null -eq $nodeInner) {
  throw "Failed to unpack Node.js"
}
Copy-Item -Path (Join-Path $nodeInner.FullName "*") -Destination $nodeTarget -Recurse -Force

$xrayZip = Join-Path $env:TEMP "xray-latest-windows-64.zip"
$xrayUrls = @(
  "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-windows-64.zip",
  "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-windows-amd64.zip"
)

Write-Step "Installing Xray-core"
if (Test-Path $xrayTarget) { Remove-Item $xrayTarget -Recurse -Force }
Ensure-Dir $xrayTarget
Download-FileWithFallback $xrayUrls $xrayZip "Xray-core"
Expand-ZipCompat $xrayZip $xrayTarget

$startCmdPath = Join-Path $installRoot "start-controller.cmd"
$startCmd = @"
@echo off
setlocal
set "ROOT=%~dp0"
set "XRAY_BIN=%ROOT%runtime\xray\xray.exe"
"%ROOT%runtime\node\node.exe" "%ROOT%controller\server.js"
"@
Set-Content -Path $startCmdPath -Value $startCmd -Encoding ASCII

Copy-Item -Path (Join-Path $scriptRoot "uninstall-windows.ps1") -Destination (Join-Path $installRoot "uninstall.ps1") -Force

$uninstallBatPath = Join-Path $installRoot "uninstall.bat"
$uninstallBat = @"
@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
pause
"@
Set-Content -Path $uninstallBatPath -Value $uninstallBat -Encoding ASCII

Write-Step "Configuring autostart"
$taskName = "VlessChromeVpnController"
$taskCmd = '"' + $startCmdPath + '"'
try {
  & schtasks /Create /TN $taskName /TR $taskCmd /SC ONLOGON /RL LIMITED /F | Out-Null
} catch {
  $runPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
  $runValue = 'cmd /c ""' + $startCmdPath + '""'
  New-ItemProperty -Path $runPath -Name "VlessChromeVpnController" -PropertyType String -Value $runValue -Force | Out-Null
}

Write-Step "Starting controller now"
Start-Process -FilePath $startCmdPath -WindowStyle Minimized

Write-Step "Creating desktop shortcuts"
$cmdPath = Join-Path $env:WINDIR "System32\cmd.exe"
$storeArgs = "/c start https://chromewebstore.google.com/"
Create-Shortcut $restartShortcutPath $startCmdPath "" $installRoot "Restart local VPN controller" ""
Create-Shortcut $uninstallShortcutPath $uninstallBatPath "" $installRoot "Uninstall VLESS VPN setup" ""
Create-Shortcut $storeShortcutPath $cmdPath $storeArgs $installRoot "Open Chrome Web Store" ""

Write-Host ""
Write-Host "Companion install completed."
Write-Host "Install extension from Chrome Web Store, then open extension popup and click Enable."
Write-Host "Personal cabinet: https://cp.sevenskull.ru/login"
