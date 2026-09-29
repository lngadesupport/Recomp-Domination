@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "GAME_ROOT=%~1"
if "%GAME_ROOT%"=="" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\status_downhill.ps1"
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\status_downhill.ps1" -GameRoot "%GAME_ROOT%"
)
echo.
pause
