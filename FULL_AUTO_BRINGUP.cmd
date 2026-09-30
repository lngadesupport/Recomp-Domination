@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title Recomp Domination - FULL AUTO BRING-UP

set "GAME_ROOT=%~1"
if "%GAME_ROOT%"=="" set "GAME_ROOT=D:\Recomp Domination"
set "FFMPEG_ARG="
if /I "%~2"=="NOFFMPEG" set "FFMPEG_ARG=-DisableAutoFfmpeg"
set "GHIDRA_ARG="
if /I "%~3"=="NOGHIDRA" set "GHIDRA_ARG=-SkipGhidra"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\full_auto_bringup.ps1" -GameRoot "%GAME_ROOT%" %FFMPEG_ARG% %GHIDRA_ARG%
set "RC=%ERRORLEVEL%"

echo.
echo ============================================================
echo FULL AUTO BRING-UP exit code: %RC%
echo Reports:  %~dp0analysis\local\full_auto_bringup_*.json
echo Sessions: %~dp0analysis\local\bringup_sessions\
echo ============================================================
echo.
pause
exit /b %RC%
