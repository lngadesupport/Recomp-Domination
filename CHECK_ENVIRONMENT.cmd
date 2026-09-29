@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title Recomp Domination - environment check
set "GAME_ROOT=%~1"
if "%GAME_ROOT%"=="" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\check_environment.ps1"
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\check_environment.ps1" -GameRoot "%GAME_ROOT%"
)
set "RC=%ERRORLEVEL%"
echo.
pause
exit /b %RC%
