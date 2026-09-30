@echo off
rem Starts the MOI visitor station full screen (Ctrl+Shift+Q closes it). Same as the 'Start VR Station' desktop icon.
start "" powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0visitor-station.ps1" %*
