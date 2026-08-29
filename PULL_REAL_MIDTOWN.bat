@echo off
setlocal
cd /d C:\Users\mika9\ViewersVSMe

echo ========================================
echo   VIEWERS VS ME - REAL MIDTOWN IMPORT

echo ========================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Import-RealMidtown.ps1"
echo.
pause
