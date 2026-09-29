@echo off
setlocal EnableExtensions
cd /d "%~dp0"

title Recomp Domination - prepare local game data

set "GAME_ROOT=%~1"
if "%GAME_ROOT%"=="" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\prepare_game_data.ps1"
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\prepare_game_data.ps1" -GameRoot "%GAME_ROOT%"
)

set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
  echo Dados locais preparados.
) else (
  echo Preparacao interrompida. Codigo: %RC%
)
echo.
pause
exit /b %RC%
