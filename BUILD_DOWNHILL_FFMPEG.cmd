@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title Recomp Domination - Windows x64 + FFmpeg

set "GAME_ROOT=%~1"
if "%GAME_ROOT%"=="" set "GAME_ROOT=D:\Recomp Domination"

echo ============================================================
echo   Recomp Domination - optional FFmpeg MPEG build
echo ============================================================
echo Game root: %GAME_ROOT%
echo.
echo This mode enables the PS2Recomp Windows FFmpeg backend.
echo The normal BUILD_DOWNHILL.cmd remains the dependency-light baseline.
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_downhill.ps1" -GameRoot "%GAME_ROOT%" -EnableFfmpeg
set "RC=%ERRORLEVEL%"
set "MODE=single-file"

if not "%RC%"=="0" (
    echo.
    echo [AVISO] FFmpeg single-file build failed with code %RC%.
    echo Retrying multi-file with FFmpeg enabled...
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_downhill.ps1" -GameRoot "%GAME_ROOT%" -EnableFfmpeg -MultiFileOutput
    set "RC=%ERRORLEVEL%"
    set "MODE=multi-file"
)

echo.
echo ============================================================
if "%RC%"=="0" (
    echo FFMPEG BUILD FINALIZADO - %MODE%
    echo Runner: %GAME_ROOT%\DownhillRecompiled\ps2EntryRunner.exe
) else (
    echo FFMPEG BUILD FALHOU. Codigo: %RC%
)
echo ============================================================
echo.
pause
exit /b %RC%
