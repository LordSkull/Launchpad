@echo off
setlocal
cd /d "%~dp0"

docker compose logs --tail=200 launchpad
echo.
pause
