@echo off
setlocal EnableExtensions
cd /d "%~dp0"

title Recomp Domination - full local pipeline

set "GAME_ROOT=%~1"
if "%GAME_ROOT%"=="" set "GAME_ROOT=D:\Recomp Domination"

echo ============================================================
echo   RECOMP DOMINATION - FULL LOCAL PIPELINE
echo ============================================================
echo Game root:
echo   %GAME_ROOT%
echo.

if not exist "%GAME_ROOT%\SCUS_971.77" (
    echo [ERRO] SCUS_971.77 nao encontrado em:
    echo   %GAME_ROOT%
    echo.
    pause
    exit /b 2
)

echo [1/4] Preparando dados locais do jogo...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\prepare_game_data.ps1" -GameRoot "%GAME_ROOT%"
set "PREP_RC=%ERRORLEVEL%"
if not "%PREP_RC%"=="0" (
    echo.
    echo [ERRO] Preparacao dos dados falhou. Codigo: %PREP_RC%
    echo O build nao sera iniciado.
    echo.
    pause
    exit /b %PREP_RC%
)

echo.
echo [2/4] Compilando recompilacao nativa Windows x64...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_downhill.ps1" -GameRoot "%GAME_ROOT%"
set "BUILD_RC=%ERRORLEVEL%"
if not "%BUILD_RC%"=="0" (
    echo.
    echo [ERRO] Build falhou. Codigo: %BUILD_RC%
    echo Coletando diagnosticos disponiveis...
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\collect_diagnostics.ps1" -GameRoot "%GAME_ROOT%"
    echo.
    pause
    exit /b %BUILD_RC%
)

set "DIST=%GAME_ROOT%\DownhillRecompiled"

echo.
echo [3/4] Executando probe nativo de 90 segundos...
if exist "%DIST%\run_downhill_probe.ps1" (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DIST%\run_downhill_probe.ps1" -Elf "%GAME_ROOT%\SCUS_971.77" -TimeoutSeconds 90
    set "PROBE_RC=%ERRORLEVEL%"
) else (
    echo [AVISO] run_downhill_probe.ps1 nao encontrado.
    set "PROBE_RC=9009"
)

if "%PROBE_RC%"=="124" (
    echo Probe atingiu o limite de 90 segundos. Isso e esperado para diagnostico.
) else if not "%PROBE_RC%"=="0" (
    echo Probe terminou com codigo %PROBE_RC%. O diagnostico ainda sera coletado.
)

echo.
echo [4/4] Coletando pacote de diagnosticos...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\collect_diagnostics.ps1" -GameRoot "%GAME_ROOT%"
set "DIAG_RC=%ERRORLEVEL%"

echo.
echo ============================================================
echo PIPELINE LOCAL FINALIZADO
echo ============================================================
echo Build:       %BUILD_RC%
echo Probe:       %PROBE_RC%
echo Diagnostics: %DIAG_RC%
echo.
echo Runner:
echo   %DIST%\ps2EntryRunner.exe
echo.
echo Probe log:
echo   %DIST%\first_boot_probe_latest.log
echo.
echo Triage:
echo   %DIST%\first_boot_probe_triage.json
echo.
echo Sugestoes:
echo   %DIST%\first_boot_probe_suggestions.json
echo.
echo O ZIP de diagnostico fica na raiz do jogo.
echo ============================================================
echo.
pause

if not "%BUILD_RC%"=="0" exit /b %BUILD_RC%
if not "%DIAG_RC%"=="0" exit /b %DIAG_RC%
exit /b 0
