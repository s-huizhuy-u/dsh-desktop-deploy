@echo off
REM ===========================================================================
REM  DSH Desktop Professional Deployment Package - Installer Launcher
REM ---------------------------------------------------------------------------
REM  NOTE: This file is intentionally pure ASCII.
REM  Non-ASCII bytes corrupt cmd.exe batch parsing, so all Chinese user-facing
REM  text lives in the PowerShell engine (saved as UTF-8 with BOM).
REM  Code page 65001 is set so that engine output renders correctly.
REM
REM  Pause policy: the engine runs with -NoPause and this launcher owns the
REM  single end-of-run pause, so the window never closes before the user has
REM  read the result. Silent (unattended) runs skip the pause entirely.
REM ===========================================================================

chcp 65001 >nul 2>&1
setlocal EnableExtensions

set "PKG_ROOT=%~dp0"
set "ENGINE=%PKG_ROOT%scripts\Install-DSH.ps1"
title DSH Desktop - Installer

REM Detect silent mode so unattended deployments never block
set "SILENT=0"
echo %* | findstr /I "silent" >nul 2>&1
if not errorlevel 1 set "SILENT=1"

if not exist "%ENGINE%" goto :missing_engine

where powershell >nul 2>&1
if errorlevel 1 goto :no_powershell

powershell -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%ENGINE%" -NoPause %*
set "RC=%ERRORLEVEL%"

if "%SILENT%"=="1" goto :finish
if not "%RC%"=="0" goto :report_error
goto :pause_exit

:report_error
echo.
echo   ==================================================================
echo    The installer stopped before finishing. Exit code: %RC%
echo.
echo    What to do next:
echo      1. Read the message printed above this line.
echo      2. Open the "docs" folder and read 06-troubleshooting guide.
echo      3. Run "2-Environment-Check.bat" and send the report to support.
echo   ==================================================================
echo.

:pause_exit
echo   Press any key to close this window...
pause >nul
goto :finish

:finish
endlocal & exit /b %RC%

:missing_engine
echo.
echo   ==================================================================
echo    ERROR: required file is missing
echo           scripts\Install-DSH.ps1
echo.
echo    This package is incomplete. The archive was probably not fully
echo    extracted, or antivirus removed the file.
echo.
echo    Fix: right-click the original ZIP, choose "Extract All", extract
echo    to a local folder such as Desktop, then run this file again.
echo   ==================================================================
echo.
pause >nul
endlocal & exit /b 1

:no_powershell
echo.
echo   ==================================================================
echo    ERROR: Windows PowerShell was not found.
echo.
echo    This package needs Windows PowerShell 5.1 or newer. It ships with
echo    Windows 10 and Windows 11 by default.
echo.
echo    Fix: install Windows Management Framework 5.1, then run again.
echo   ==================================================================
echo.
pause >nul
endlocal & exit /b 1
