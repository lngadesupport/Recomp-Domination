@echo off
setlocal EnableExtensions
cd /d "%~dp0"

title Recomp Domination - Windows x64 compiler

echo ============================================================
echo   Recomp Domination - full Windows x64 compiler bootstrap
echo ============================================================
echo.

set "GAME_ROOT=%~1"

if "%GAME_ROOT%"=="" (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_downhill.ps1"
) else (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_downhill.ps1" -GameRoot "%GAME_ROOT%"
)

set "RC=%ERRORLEVEL%"

echo.
echo ============================================================
if "%RC%"=="0" (
    echo BUILD FINALIZADO.
) else (
    echo BUILD INTERROMPIDO. Codigo de saida: %RC%
    echo Consulte a pasta logs para o diagnostico.
)
echo ============================================================
echo.
pause
exit /b %RC%
