@echo off
setlocal EnableExtensions
cd /d "%~dp0"

title Recomp Domination - update and run

echo ============================================================
echo   RECOMP DOMINATION - UPDATE AND RUN
echo ============================================================
echo.

where git >nul 2>&1
if errorlevel 1 (
    echo [ERRO] git.exe nao foi encontrado no PATH.
    echo.
    pause
    exit /b 2
)

echo Atualizando bootstrap/compiler por fast-forward...
git fetch origin bootstrap/compiler
if errorlevel 1 (
    echo [AVISO] Nao foi possivel atualizar pela rede.
    echo Tentando continuar com o checkout local.
)

git checkout bootstrap/compiler
if errorlevel 1 (
    echo [ERRO] Nao foi possivel selecionar bootstrap/compiler.
    echo.
    pause
    exit /b 3
)

git merge --ff-only origin/bootstrap/compiler >nul 2>&1
if errorlevel 1 (
    echo [AVISO] Fast-forward remoto indisponivel ou existem mudancas locais.
    echo O pipeline continuara sem destruir suas alteracoes.
)

echo.
echo Iniciando pipeline completo...
call "%~dp0FULL_PIPELINE_DOWNHILL.cmd" %*
exit /b %ERRORLEVEL%
