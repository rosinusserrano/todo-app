@echo off
REM Double-clickable wrapper for install-windows.ps1.
REM
REM -ExecutionPolicy Bypass applies to this one invocation only; it does not
REM change the machine's policy. Without it a default Windows install refuses to
REM run the script at all, which looks exactly like the script being broken.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-windows.ps1" %*
pause
