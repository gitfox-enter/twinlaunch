@echo off
title Reset password for local user "10"

net session >nul 2>&1
if errorlevel 1 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo ================================================
echo   Reset password for local user "10"
echo ================================================
echo.
echo   Just press ENTER to CLEAR the password.
echo   (runas then never asks for anything again)
echo.
echo   Or type a new password before pressing ENTER.
echo.
set /p NEWPW=Password for "10": 

if "%NEWPW%"=="" (
    net user 10 ""
) else (
    net user 10 "%NEWPW%"
)

echo.
echo --- account state after reset ---
echo.
net user 10
echo.
echo Done. Press any key to close this window.
pause >nul
