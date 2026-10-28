@echo off
setlocal
cd /d "%~dp0"
set "GODOT=%~dp0..\Godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot executable not found:
  echo %GODOT%
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0." --resolution 1240x860
