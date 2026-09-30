@echo off
title Mirror quality test
echo.
echo  MIRROR QUALITY TEST  (about 2 minutes)
echo.
echo  Shows the headset mirror on the VR screen with 4 different quality settings, one after the other,
echo  and saves pictures of each so they can be compared.
echo.
echo  Before you start:
echo    1. Close the VR station (Ctrl+Shift+Q).
echo    2. Headset connected by USB, the MOI app running on it.
echo    3. Someone wears the headset and presses START, so the film plays during the test.
echo.
pause
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0mirror_quality_test.ps1"
