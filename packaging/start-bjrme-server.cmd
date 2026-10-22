@echo off
setlocal
rem Parse this block before an update can replace this launcher file.
(
  if exist "%~dp0.raceprep-update\ready.json" (
    "%~dp0.raceprep-update\payload\bjrme-generator\bjrme-generator.exe" --beammp "%~dp0." --update-apply
    if errorlevel 1 exit /b 1
  )
  if "%~1"=="" (
    "%~dp0bjrme-generator\bjrme-generator.exe" --beammp "%~dp0." --server BeamMP-Server.exe
  ) else (
    "%~dp0bjrme-generator\bjrme-generator.exe" --beammp "%~dp0." --server "%~1"
  )
  exit /b
)
