@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\nfsmw_fixes.ps1" -Restore %*
pause
