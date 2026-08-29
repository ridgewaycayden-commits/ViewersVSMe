@echo off
setlocal
cd /d C:\Users\mika9\ViewersVSMe

echo ========================================
echo   VIEWERS VS ME - COMPACT REAL MIDTOWN
echo ========================================
echo.

where python >nul 2>&1
if errorlevel 1 (
  echo ERROR: Python was not found in PATH.
  echo Install/use the same Python you used for the Arnis bootstrap, then rerun this file.
  pause
  exit /b 1
)

python "%~dp0tools\build_real_midtown_compact.py"
if errorlevel 1 (
  echo.
  echo BUILD FAILED - send ChatGPT this entire window.
  pause
  exit /b 1
)

echo.
echo DONE.
echo Keep Rojo running. In Studio, wait for RealMidtownCompact to appear under ServerStorage.
echo Then press Play to load the lightweight real Midtown map.
echo.
pause
