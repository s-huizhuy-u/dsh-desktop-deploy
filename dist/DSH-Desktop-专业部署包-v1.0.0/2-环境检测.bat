@echo off
REM ===========================================================================
REM  DSH Desktop Professional Deployment Package - Environment Check Launcher
REM ---------------------------------------------------------------------------
REM  Pure ASCII by design. All Chinese output comes from the PowerShell engine.
REM
REM  This is an interactive diagnostic tool, so it always pauses at the end
REM  (except when "silent" is passed) - the user must be able to read the
REM  conclusion and the list of blocking issues.
REM ===========================================================================

chcp 65001 >nul 2>&1
setlocal EnableExtensions

set "PKG_ROOT=%~dp0"
set "ENGINE=%PKG_ROOT%scripts\Test-DSHEnvironment.ps1"
title DSH Desktop - Environment Check

set "SILENT=0"
echo %* | findstr /I "silent" >nul 2>&1
if not errorlevel 1 set "SILENT=1"

if not exist "%ENGINE%" goto :missing_engine

where powershell >nul 2>&1
if errorlevel 1 goto :no_powershell

powershell -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%ENGINE%" -NoPause -Export %*
set "RC=%ERRORLEVEL%"

if "%SILENT%"=="1" goto :finish

if not "%RC%"=="0" (
    if not "%RC%"=="2" (
        echo.
        echo   ==================================================================
        echo    The environment check could not complete. Exit code: %RC%
        echo    Please send the log files in the "logs" folder to support.
        echo   ==================================================================
        echo.
    )
)

echo   Press any key to close this window...
pause >nul
goto :finish

:finish
endlocal & exit /b %RC%

:missing_engine
echo.
echo   ==================================================================
echo    ERROR: required file is missing
echo           scripts\Test-DSHEnvironment.ps1
echo.
echo    Fix: re-extract the original ZIP archive, then run again.
echo   ==================================================================
echo.
pause >nul
endlocal & exit /b 1

:no_powershell
echo.
echo   ==================================================================
echo    ERROR: Windows PowerShell was not found on this computer.
echo    Fix: install Windows Management Framework 5.1, then run again.
echo   ==================================================================
echo.
pause >nul
endlocal & exit /b 1
