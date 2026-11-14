@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
set "PABC=%ROOT%tools\pabcnet\PascalABCNET-Console-net10\pabcnetc.dll"
set "LOG=%ROOT%out\build.log"

if not exist "%PABC%" (
  echo [build] Compiler not found: %PABC%
  exit /b 1
)
if not exist "%ROOT%out" mkdir "%ROOT%out"

pushd "%ROOT%src"

echo [build] analiticum.pas
dotnet "%PABC%" analiticum.pas /noconsole > "%LOG%" 2>nul
if errorlevel 1 goto fail
findstr /C:"[0]" "%LOG%" >nul
if not errorlevel 1 goto fail
if not exist "%ROOT%src\analiticum.exe" goto fail

echo [build] tests.pas
dotnet "%PABC%" tests.pas /noconsole > "%LOG%" 2>nul
if errorlevel 1 goto fail
findstr /C:"[0]" "%LOG%" >nul
if not errorlevel 1 goto fail
if not exist "%ROOT%src\tests.exe" goto fail

popd

for %%F in (analiticum tests) do (
  if exist "%ROOT%src\%%F.exe" move /Y "%ROOT%src\%%F.exe" "%ROOT%out\%%F.exe" >nul
  if exist "%ROOT%src\%%F.pdb" move /Y "%ROOT%src\%%F.pdb" "%ROOT%out\%%F.pdb" >nul
  if exist "%ROOT%src\%%F.runtimeconfig.json" move /Y "%ROOT%src\%%F.runtimeconfig.json" "%ROOT%out\%%F.runtimeconfig.json" >nul
)

echo [build] OK
echo [build] Run:   run.cmd
echo [build] Tests: run.cmd --test
echo [build] Demo:  run.cmd --demo 200
echo [build] Bench: run.cmd --bench
exit /b 0

:fail
popd
echo [build] FAILED
type "%LOG%"
exit /b 1
