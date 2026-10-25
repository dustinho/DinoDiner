@echo off
REM Build DinoDiner.pdx with the official Playdate SDK compiler.
cd /d "%~dp0"
if defined PLAYDATE_SDK_PATH set "PATH=%PLAYDATE_SDK_PATH%\bin;%PATH%"
pdc source DinoDiner.pdx || exit /b 1
echo Built DinoDiner.pdx
