@echo off
setlocal
cd /d "%~dp0"

echo.
echo [Launchpad] Stopping...
docker compose down

if errorlevel 1 (
    echo.
    echo [ERROR] Docker could not stop Launchpad cleanly.
    pause
    exit /b 1
)

echo [Launchpad] Stopped.
echo User songs and the local database were preserved.
timeout /t 2 /nobreak >nul
