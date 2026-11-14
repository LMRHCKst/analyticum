@echo off
setlocal EnableExtensions
set ROOT=%~dp0

if /I "%~1"=="--test" (
  if not exist "%ROOT%out\tests.exe" call "%ROOT%build.cmd"
  if errorlevel 1 exit /b 1
  dotnet "%ROOT%out\tests.exe"
  exit /b %errorlevel%
)

if not exist "%ROOT%out\analiticum.exe" (
  call "%ROOT%build.cmd"
  if errorlevel 1 exit /b 1
)

dotnet "%ROOT%out\analiticum.exe" %*
exit /b %errorlevel%
