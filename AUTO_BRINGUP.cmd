@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title Recomp Domination - iterative bring-up

set "GAME_ROOT=%~1"
if "%GAME_ROOT%"=="" set "GAME_ROOT=D:\Recomp Domination"
set "FFMPEG_ARG="
if /I "%~2"=="NOFFMPEG" set "FFMPEG_ARG=-DisableAutoFfmpeg"

echo ============================================================
echo   Recomp Domination - guarded iterative bring-up
echo ============================================================
echo Game root: %GAME_ROOT%
if defined FFMPEG_ARG (
  echo Auto FFmpeg escalation: DISABLED
) else (
  echo Auto FFmpeg escalation: evidence-driven
)
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\auto_bringup.ps1" -GameRoot "%GAME_ROOT%" %FFMPEG_ARG%
set "RC=%ERRORLEVEL%"

echo.
echo Auto bring-up exit code: %RC%
echo Reports: %~dp0analysis\local\auto_bringup_*.json
echo Sessions: %~dp0analysis\local\bringup_sessions\
pause
exit /b %RC%
