@echo off
setlocal
cd /d "%~dp0"

echo.
echo ========================================
echo          Launchpad - Start
echo ========================================
echo.

where docker >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Docker was not found.
    echo Install Docker Desktop, start it, then run this file again.
    echo.
    pause
    exit /b 1
)

docker info >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Docker Desktop is installed but Docker is not running.
    echo Start Docker Desktop, wait until it is ready, then try again.
    echo.
    pause
    exit /b 1
)

if not exist "user_data\songs" mkdir "user_data\songs"

echo [Launchpad] Building and starting the app...
echo The first launch can take several minutes because the legacy Ruby image
echo and gems have to be downloaded and built.
echo.

docker compose up -d --build
if errorlevel 1 (
    echo.
    echo [ERROR] Docker could not start Launchpad.
    echo Run CHECK_LAUNCHPAD_LOGS.bat to inspect the error.
    echo.
    pause
    exit /b 1
)

echo.
echo [Launchpad] Waiting for the web server...

for /L %%I in (1,1,90) do (
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "try { $r = Invoke-WebRequest -UseBasicParsing 'http://localhost:3000/' -TimeoutSec 2; if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) { exit 0 } } catch {}; exit 1" >nul 2>&1
    if not errorlevel 1 goto READY
    timeout /t 1 /nobreak >nul
)

echo.
echo [WARNING] Launchpad did not answer within 90 seconds.
echo Opening the logs so you can see what happened.
docker compose logs --tail=100 launchpad
echo.
pause
exit /b 1

:READY
echo.
echo [Launchpad] Ready: http://localhost:3000
start "" "http://localhost:3000/"
echo.
echo You can close this window. Launchpad keeps running in Docker.
echo To stop it, double-click STOP_LAUNCHPAD.bat.
echo.
pause
