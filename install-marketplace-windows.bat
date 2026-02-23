@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%install-marketplace-windows.ps1"
if errorlevel 1 (
  echo.
  echo Companion installation failed.
  pause
  exit /b 1
)
echo.
echo Companion installation completed successfully.
pause
