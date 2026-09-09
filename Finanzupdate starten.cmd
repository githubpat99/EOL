@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\update-dashboard-finance.ps1" -SelectFiles
if errorlevel 1 (
  echo.
  echo Das Finanzupdate wurde nicht abgeschlossen.
) else (
  echo.
  echo Das Finanzupdate wurde erfolgreich abgeschlossen.
  echo Bitte das Dashboard neu laden und die Werte pruefen.
)
echo.
pause
endlocal
