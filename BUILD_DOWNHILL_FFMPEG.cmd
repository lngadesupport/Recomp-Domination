@echo off
setlocal EnableExtensions
cd /d "%~dp0"

title Recomp Domination - Windows x64 + FFmpeg

echo ============================================================
echo   Recomp Domination - native Windows x64 build with FFmpeg
echo ============================================================
echo.

set "GAME_ROOT=%~1"
if "%GAME_ROOT%"=="" (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_downhill.ps1" -EnableFfmpeg
) else (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_downhill.ps1" -GameRoot "%GAME_ROOT%" -EnableFfmpeg
)

set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
    echo BUILD COM FFMPEG FINALIZADO.
) else (
    echo BUILD COM FFMPEG FALHOU. Codigo: %RC%
)
echo.
pause
exit /b %RC%
