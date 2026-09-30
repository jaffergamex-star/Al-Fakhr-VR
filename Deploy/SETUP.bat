@echo off
rem Double-click to install the MOI VR station on this PC and the connected headset.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0SETUP.ps1" %*
