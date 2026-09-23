@echo off
setlocal
cd /d "%~dp0"

echo.
echo ==========================================
echo   ICE AND FLAME - RELEASE TRANSLATION
echo ==========================================
echo.

where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo [ERROR] powershell.exe not found.
    pause
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0RELEASE_TRANSLATION.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" (
    echo [ERROR] Translation release failed. Exit code: %EXIT_CODE%
) else (
    echo [OK] Translation release completed successfully.
)
echo.
pause
exit /b %EXIT_CODE%
