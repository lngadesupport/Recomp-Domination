@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "GAME_ROOT=%~1"
if "%GAME_ROOT%"=="" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\collect_diagnostics.ps1"
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\collect_diagnostics.ps1" -GameRoot "%GAME_ROOT%"
)

set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo Falha ao coletar diagnosticos. Codigo: %RC%
pause
exit /b %RC%
