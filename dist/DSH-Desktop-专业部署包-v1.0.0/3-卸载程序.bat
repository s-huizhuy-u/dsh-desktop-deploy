@echo off
REM ===========================================================================
REM  DSH Desktop Professional Deployment Package - Uninstaller Launcher
REM ---------------------------------------------------------------------------
REM  Pure ASCII by design. All Chinese output comes from the PowerShell engine.
REM
REM  Pause policy: the engine runs with -NoPause and this launcher owns the
REM  single end-of-run pause. Silent runs skip the pause entirely.
REM ===========================================================================

chcp 65001 >nul 2>&1
setlocal EnableExtensions

set "PKG_ROOT=%~dp0"
set "ENGINE=%PKG_ROOT%scripts\Uninstall-DSH.ps1"
title DSH Desktop - Uninstaller

set "SILENT=0"
echo %* | findstr /I "silent" >nul 2>&1
if not errorlevel 1 set "SILENT=1"

if not exist "%ENGINE%" goto :missing_engine

where powershell >nul 2>&1
if errorlevel 1 goto :no_powershell

powershell -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%ENGINE%" -NoPause %*
set "RC=%ERRORLEVEL%"

if "%SILENT%"=="1" goto :finish

if not "%RC%"=="0" (
    if not "%RC%"=="6" (
        echo.
        echo   ==================================================================
        echo    The uninstaller stopped early. Exit code: %RC%
        echo.
        echo    If the program folder still exists, restart the computer and
        echo    delete it manually, or contact technical support.
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
echo           scripts\Uninstall-DSH.ps1
echo.
echo    You can still uninstall manually:
echo      Windows Settings - Apps - Installed apps - DSH Desktop - Uninstall
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
