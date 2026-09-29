@echo off
setlocal EnableExtensions
cd /d "%~dp0"

title Recomp Domination - Ghidra headless map

set "GAME_ROOT=%~1"
set "GHIDRA_HOME_ARG=%~2"

if "%GAME_ROOT%"=="" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\generate_ghidra_map.ps1"
) else if "%GHIDRA_HOME_ARG%"=="" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\generate_ghidra_map.ps1" -GameRoot "%GAME_ROOT%"
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\generate_ghidra_map.ps1" -GameRoot "%GAME_ROOT%" -GhidraHome "%GHIDRA_HOME_ARG%"
)

set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
  echo Mapa Ghidra gerado. Rode BUILD_DOWNHILL.cmd novamente.
) else (
  echo Geracao do mapa interrompida. Codigo: %RC%
)
echo.
pause
exit /b %RC%
