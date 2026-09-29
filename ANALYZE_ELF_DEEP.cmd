@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title Recomp Domination - deep ELF analysis
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\analyze_downhill_elf_deep.ps1" %*
set "RC=%ERRORLEVEL%"
echo.
pause
exit /b %RC%
