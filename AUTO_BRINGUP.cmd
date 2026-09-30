@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title Recomp Domination - iterative bring-up
set "GAME_ROOT=%~1"
if "%GAME_ROOT%"=="" set "GAME_ROOT=D:\Recomp Domination"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\auto_bringup.ps1" -GameRoot "%GAME_ROOT%"
set "RC=%ERRORLEVEL%"
echo.
echo Auto bring-up exit code: %RC%
pause
exit /b %RC%
