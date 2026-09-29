@echo off
setlocal EnableExtensions
cd /d "%~dp0"

title Recomp Domination - accept entry suggestions

set "GAME_ROOT=%~1"
if "%GAME_ROOT%"=="" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\accept_entry_suggestions.ps1"
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\accept_entry_suggestions.ps1" -GameRoot "%GAME_ROOT%"
)

set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
  echo Sugestoes processadas. Se novos enderecos foram aceitos, rode BUILD_DOWNHILL.cmd.
) else (
  echo Falha ao processar sugestoes. Codigo: %RC%
)
echo.
pause
exit /b %RC%
