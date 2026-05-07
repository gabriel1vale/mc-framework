@echo off
REM mc-framework CLI launcher.
REM Wraps mc.ps1 with execution policy bypass and argument forwarding.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0mc.ps1" %*
