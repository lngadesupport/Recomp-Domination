@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title Recomp Domination - second-pass bring-up

set "GAME_ROOT=%~1"
if "%GAME_ROOT%"=="" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\auto_bringup_second_pass.ps1"
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\auto_bringup_second_pass.ps1" -GameRoot "%GAME_ROOT%"
)
set "RC=%ERRORLEVEL%"
echo.
pause
exit /b %RC%
