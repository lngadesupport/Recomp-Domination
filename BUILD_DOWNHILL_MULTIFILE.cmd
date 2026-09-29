@echo off
setlocal EnableExtensions
cd /d "%~dp0"

title Recomp Domination - Windows x64 compiler - multi-file

echo ============================================================
echo   Recomp Domination - multi-file compiler fallback
echo ============================================================
echo.
echo Este modo gera uma unidade C++ por funcao/bloco em vez de um
echo ps2_recompiled_functions.cpp gigante. Use quando o build
echo single-file atingir limite de memoria/compilador.
echo.

set "GAME_ROOT=%~1"

if "%GAME_ROOT%"=="" (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_downhill.ps1" -MultiFileOutput
) else (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_downhill.ps1" -GameRoot "%GAME_ROOT%" -MultiFileOutput
)

set "RC=%ERRORLEVEL%"

echo.
echo ============================================================
if "%RC%"=="0" (
    echo BUILD MULTI-FILE FINALIZADO.
) else (
    echo BUILD MULTI-FILE INTERROMPIDO. Codigo de saida: %RC%
    echo Consulte a pasta logs para o diagnostico.
)
echo ============================================================
echo.
pause
exit /b %RC%
