$ErrorActionPreference = "Stop"

function Write-Step($text) {
  Write-Host "[WebStore Pack] $text"
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$extPath = Join-Path $root "extension"
$distPath = Join-Path $root "dist"
$zipPath = Join-Path $distPath "vless-vpn-switch-extension.zip"

if (!(Test-Path $extPath)) {
  throw "Extension folder not found: $extPath"
}

if (!(Test-Path $distPath)) {
  New-Item -ItemType Directory -Path $distPath | Out-Null
}

if (Test-Path $zipPath) {
  Remove-Item $zipPath -Force
}

Write-Step "Creating zip: $zipPath"
Compress-Archive -Path (Join-Path $extPath "*") -DestinationPath $zipPath -CompressionLevel Optimal

Write-Step "Done"
Write-Host "ZIP ready: $zipPath"
