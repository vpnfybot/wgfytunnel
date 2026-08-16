@echo off
setlocal EnableDelayedExpansion

set "REAL_FLUTTER=%USERPROFILE%\development\flutter\bin\flutter.bat"
if not exist "%REAL_FLUTTER%" (
  for /f "delims=" %%I in ('where flutter 2^>nul') do (
    if /I not "%%~fI"=="%~f0" (
      set "REAL_FLUTTER=%%~fI"
      goto real_flutter_found
    )
  )

  echo Flutter SDK not found. 1>&2
  exit /b 1
)

:real_flutter_found
if /I "%~1"=="run" (
  call :check_run_args %*
  if defined SHOULD_PICK_TARGET (
    goto run_with_picker
  )
)

"%REAL_FLUTTER%" %*
exit /b %ERRORLEVEL%

:run_with_picker
set "PICKER_SCRIPT=%~dp0..\run_flutter_device_picker.ps1"
set "PICKER_ARGS="
shift

:picker_arg_loop
if "%~1"=="" goto picker_args_done
set "PICKER_ARGS=!PICKER_ARGS! "%~1""
shift
goto picker_arg_loop

:picker_args_done
powershell -NoProfile -ExecutionPolicy Bypass -File "%PICKER_SCRIPT%" !PICKER_ARGS! || call cmd.exe /c "@if %%ERRORLEVEL%% EQU -1073741510 (exit 9009) else exit %%ERRORLEVEL%%"
exit /b %ERRORLEVEL%

:check_run_args
set "SHOULD_PICK_TARGET=1"

:arg_loop
if "%~1"=="" exit /b 0
if /I "%~1"=="-h" set "SHOULD_PICK_TARGET=" & exit /b 0
if /I "%~1"=="--help" set "SHOULD_PICK_TARGET=" & exit /b 0
if /I "%~1"=="--version" set "SHOULD_PICK_TARGET=" & exit /b 0
shift
goto arg_loop
