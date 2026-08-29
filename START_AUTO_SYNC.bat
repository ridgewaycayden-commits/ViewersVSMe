@echo off
cd /d "%~dp0"
start "ViewersVSMe Auto Pull" powershell -NoExit -ExecutionPolicy Bypass -File "%~dp0auto_pull.ps1"
rojo serve
