@echo off
rem RLMM Setup: double-click to install UDK for Rocket League map making, or to update an existing install.
if exist "%~dp0install.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/armand0e/rlmm-setup/main/install.ps1 | iex"
)
