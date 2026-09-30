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

echo [1/6] Verificando ambiente de compilacao...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\check_environment.ps1" -GameRoot "%GAME_ROOT%"
set "ENV_RC=%ERRORLEVEL%"
if not "%ENV_RC%"=="0" (
    echo.
    echo [ERRO] Preflight do ambiente falhou. Codigo: %ENV_RC%
    echo Corrija os itens marcados como FAIL antes de continuar.
    echo.
    pause
    exit /b %ENV_RC%
)

echo.
echo [2/6] Preparando dados locais do jogo...
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
echo [3/6] Preparando mapa Ghidra opcional...
if exist "%~dp0analysis\SCUS_971.77.functions.csv" if exist "%~dp0analysis\SCUS_971.77.ghidra.toml" (
    echo Reutilizando mapa Ghidra existente.
    set "GHIDRA_RC=0"
) else (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\generate_ghidra_map.ps1" -GameRoot "%GAME_ROOT%" -Optional
    set "GHIDRA_RC=%ERRORLEVEL%"
    if not "%GHIDRA_RC%"=="0" (
        echo [AVISO] Ghidra opcional falhou com codigo %GHIDRA_RC%.
        echo Prosseguindo com ps2_analyzer como fallback.
    )
)

echo.
echo [4/6] Compilando recompilacao nativa Windows x64...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_downhill.ps1" -GameRoot "%GAME_ROOT%"
set "BUILD_RC=%ERRORLEVEL%"
set "BUILD_MODE=single-file"

if not "%BUILD_RC%"=="0" (
    echo.
    echo [AVISO] Build single-file falhou com codigo %BUILD_RC%.
    echo Tentando novamente em modo multi-file para reduzir a pressao por unidade de traducao...
    echo.
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_downhill.ps1" -GameRoot "%GAME_ROOT%" -MultiFileOutput
    set "BUILD_RC=%ERRORLEVEL%"
    set "BUILD_MODE=multi-file"
)

if not "%BUILD_RC%"=="0" (
    echo.
    echo [ERRO] Build falhou tambem em modo multi-file. Codigo: %BUILD_RC%
    echo Coletando diagnosticos disponiveis...
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\collect_diagnostics.ps1" -GameRoot "%GAME_ROOT%"
    echo.
    pause
    exit /b %BUILD_RC%
)
set "DIST=%GAME_ROOT%\DownhillRecompiled"

echo.
echo [5/6] Executando probe nativo de 90 segundos...
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
echo [6/6] Coletando pacote de diagnosticos...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\collect_diagnostics.ps1" -GameRoot "%GAME_ROOT%"
set "DIAG_RC=%ERRORLEVEL%"

echo.
echo ============================================================
echo PIPELINE LOCAL FINALIZADO
echo ============================================================
echo Preflight:   %ENV_RC%
echo Game data:   %PREP_RC%
echo Ghidra:      %GHIDRA_RC%
echo Build:       %BUILD_RC% (%BUILD_MODE%)
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
