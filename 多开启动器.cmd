@echo off
setlocal
start "" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0MultiInstanceManager.ps1" -HideConsole
if errorlevel 1 pause
