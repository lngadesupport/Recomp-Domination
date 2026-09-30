@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title Recomp Domination - compare bring-up iterations

if "%~1"=="" (
  echo Uso:
  echo   COMPARE_BRINGUP.cmd ^<session_dir^> [from_iteration] [to_iteration]
  echo.
  echo Exemplo:
  echo   COMPARE_BRINGUP.cmd "analysis\local\bringup_sessions\20260930_120000" 1 2
  echo.
  pause
  exit /b 2
)

set "FROM_ARG="
if not "%~2"=="" set "FROM_ARG=-FromIteration %~2"
set "TO_ARG="
if not "%~3"=="" set "TO_ARG=-ToIteration %~3"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\compare_bringup_iterations.ps1" -SessionDir "%~1" %FROM_ARG% %TO_ARG%
set "RC=%ERRORLEVEL%"
echo.
pause
exit /b %RC%
