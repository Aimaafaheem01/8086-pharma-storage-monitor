@echo off
rem Double-click to run the 8086 Pharma Monitor in DOSBox.
rem DOSBox only understands short 8.3 file names, so the EXE is run as PHARMA.EXE.
set "HERE=%~dp0"
if not exist "%HERE%PHARMA.EXE" (
  if exist "%HERE%pharma_monitor.exe" copy /y "%HERE%pharma_monitor.exe" "%HERE%PHARMA.EXE" >nul
)
if not exist "%HERE%PHARMA.EXE" (
  if exist "%HERE%build\PHARMA.EXE" set "HERE=%~dp0build\"
)
if not exist "%HERE%PHARMA.EXE" (
  echo Could not find PHARMA.EXE or pharma_monitor.exe next to this file.
  pause
  exit /b
)
set "DB="
if exist "C:\Program Files (x86)\DOSBox-0.74-3\DOSBox.exe" set "DB=C:\Program Files (x86)\DOSBox-0.74-3\DOSBox.exe"
if exist "C:\Program Files\DOSBox-0.74-3\DOSBox.exe" set "DB=C:\Program Files\DOSBox-0.74-3\DOSBox.exe"
if exist "C:\Program Files (x86)\DOSBox-0.74\DOSBox.exe" set "DB=C:\Program Files (x86)\DOSBox-0.74\DOSBox.exe"
if exist "C:\Program Files\DOSBox Staging\dosbox.exe" set "DB=C:\Program Files\DOSBox Staging\dosbox.exe"
if "%DB%"=="" (
  echo DOSBox was not found. Please install DOSBox from dosbox.com first, then double-click this file again.
  pause
  exit /b
)
"%DB%" "%HERE%PHARMA.EXE" -exit
