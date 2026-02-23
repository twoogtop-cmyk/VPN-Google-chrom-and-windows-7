$ErrorActionPreference = "Stop"

function Write-Step($text) {
  Write-Host "[VLESS Installer] $text"
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

function Resolve-ChromePath {
  $candidates = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
  )

  foreach ($item in $candidates) {
    if (Test-Path $item) {
      return $item
    }
  }

  $regCandidates = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe"
  )

  foreach ($regPath in $regCandidates) {
    try {
      $val = (Get-ItemProperty -Path $regPath -ErrorAction Stop)."(default)"
      if ($val -and (Test-Path $val)) {
        return $val
      }
    } catch {
    }
  }

  return $null
}

function Try-InstallChrome {
  Write-Step "Chrome not found. Trying automatic install"
  $installer = Join-Path $env:TEMP "chrome_installer.exe"
  $urls = @(
    "https://dl.google.com/chrome/install/latest/chrome_installer.exe",
    "https://dl.google.com/tag/s/appguid%3D%7B8A69D345-D564-463c-AFF1-A69D9E530F96%7D%26lang%3Dru%26browser%3D4%26usagestats%3D0%26appname%3DGoogle%2520Chrome%26needsadmin%3Dfalse/update2/installers/ChromeSetup.exe"
  )

  try {
    Download-FileWithFallback $urls $installer "Google Chrome installer"
    Start-Process -FilePath $installer -ArgumentList "/silent", "/install" -Wait
  } catch {
    Write-Step "Automatic Chrome install failed"
  }

  Start-Sleep -Seconds 3
  return Resolve-ChromePath
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
$extTarget = Join-Path $installRoot "extension"
$controllerTarget = Join-Path $installRoot "controller"
$xrayTarget = Join-Path $runtimeRoot "xray"
$nodeTarget = Join-Path $runtimeRoot "node"

$desktop = [Environment]::GetFolderPath("Desktop")
$chromeShortcutPath = Join-Path $desktop "VLESS VPN Chrome.lnk"
$restartShortcutPath = Join-Path $desktop "VLESS VPN Restart Controller.lnk"
$uninstallShortcutPath = Join-Path $desktop "VLESS VPN Uninstall.lnk"

Write-Step "Installing to: $installRoot"
Ensure-Dir $installRoot
Ensure-Dir $runtimeRoot

Write-Step "Copying extension and controller files"
if (Test-Path $extTarget) { Remove-Item $extTarget -Recurse -Force }
if (Test-Path $controllerTarget) { Remove-Item $controllerTarget -Recurse -Force }
Copy-Item -Path (Join-Path $scriptRoot "extension") -Destination $extTarget -Recurse -Force
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

$xrayVersion = "v1.8.14"
$xrayZip = Join-Path $env:TEMP "xray-$xrayVersion-windows-64.zip"
$xrayUrl = "https://github.com/XTLS/Xray-core/releases/download/$xrayVersion/Xray-windows-64.zip"

Write-Step "Installing Xray-core $xrayVersion"
if (Test-Path $xrayTarget) { Remove-Item $xrayTarget -Recurse -Force }
Ensure-Dir $xrayTarget
$xrayUrls = @(
  "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-windows-64.zip",
  "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-windows-amd64.zip",
  $xrayUrl,
  "https://github.com/XTLS/Xray-core/releases/download/v1.8.24/Xray-windows-64.zip",
  "https://github.com/XTLS/Xray-core/releases/download/v1.8.24/Xray-windows-amd64.zip"
)
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

$uninstallBatPath = Join-Path $installRoot "uninstall.bat"
$uninstallBat = @"
@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
pause
"@
Set-Content -Path $uninstallBatPath -Value $uninstallBat -Encoding ASCII

Copy-Item -Path (Join-Path $scriptRoot "uninstall-windows.ps1") -Destination (Join-Path $installRoot "uninstall.ps1") -Force

Write-Step "Creating startup task"
$taskName = "VlessChromeVpnController"
$taskCmd = '"' + $startCmdPath + '"'
$startupMode = "task"
try {
  & schtasks /Create /TN $taskName /TR $taskCmd /SC ONLOGON /RL LIMITED /F | Out-Null
  Write-Step "Startup task created"
} catch {
  $startupMode = "run-key"
  Write-Step "Task creation failed, using per-user startup registry"
  $runPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
  $runValue = 'cmd /c ""' + $startCmdPath + '""'
  New-ItemProperty -Path $runPath -Name "VlessChromeVpnController" -PropertyType String -Value $runValue -Force | Out-Null
}

Write-Step "Starting controller now"
Start-Process -FilePath $startCmdPath -WindowStyle Minimized

$chromePath = Resolve-ChromePath
$chromeWasAutoInstalled = $false
if (!$chromePath) {
  $chromePath = Try-InstallChrome
  if ($chromePath) {
    $chromeWasAutoInstalled = $true
  }
}
$chromeArgs = "--load-extension=`"$extTarget`""

Write-Step "Creating desktop shortcuts"
if ($chromePath) {
  Create-Shortcut $chromeShortcutPath $chromePath $chromeArgs (Split-Path $chromePath -Parent) "Open Chrome with VLESS VPN extension" $chromePath
} else {
  $fallbackTarget = Join-Path $env:WINDIR "System32\cmd.exe"
  $fallbackArgs = "/c start chrome://extensions"
  Create-Shortcut $chromeShortcutPath $fallbackTarget $fallbackArgs $installRoot "Open extensions page" ""
}
Create-Shortcut $restartShortcutPath $startCmdPath "" $installRoot "Restart local VPN controller" ""
Create-Shortcut $uninstallShortcutPath $uninstallBatPath "" $installRoot "Uninstall VLESS VPN setup" ""

Write-Host ""
Write-Host "Install completed."
Write-Host ""
Write-Host "Use desktop shortcut: VLESS VPN Chrome"
Write-Host "Then open extension icon, paste vless:// link, click Enable."
if (!$chromePath) {
  Write-Host "Chrome executable was not found automatically."
  Write-Host "Install Google Chrome: https://www.google.com/chrome/"
  Write-Host "Then run installer again or open chrome://extensions manually and load: $extTarget"
} elseif ($chromeWasAutoInstalled) {
  Write-Host "Google Chrome was installed automatically."
}
if ($startupMode -eq "run-key") {
  Write-Host "Autostart configured via HKCU Run (without Task Scheduler)."
}
Write-Host "Personal cabinet: https://cp.sevenskull.ru/login"
Write-Host ""

if ($chromePath) {
  Start-Process -FilePath $chromeShortcutPath
}
