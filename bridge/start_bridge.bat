@echo off
cd /d "%~dp0"
title VIEWERS VS ME - TIKTOK LIVE BRIDGE

echo ========================================
echo   VIEWERS VS ME - TIKTOK LIVE BRIDGE
echo ========================================
echo.

where py >nul 2>&1
if errorlevel 1 (
  echo Python was not found. Install Python 3 and make sure the Python launcher is enabled.
  pause
  exit /b 1
)

echo Checking TikTokLive...
py -m pip install --disable-pip-version-check -q -U TikTokLive
if errorlevel 1 (
  echo.
  echo Could not install/update TikTokLive.
  pause
  exit /b 1
)

echo Starting bridge...
py viewers_vs_me_bridge.py
if errorlevel 1 (
  echo.
  echo Bridge stopped with an error.
  pause
)
