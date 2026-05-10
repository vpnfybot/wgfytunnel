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
    call :run_with_picker %*
    set "EXIT_CODE=!ERRORLEVEL!"
    endlocal & exit /b %EXIT_CODE%
  )
)

call "%REAL_FLUTTER%" %*
set "EXIT_CODE=!ERRORLEVEL!"
endlocal & exit /b %EXIT_CODE%

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
powershell -NoProfile -ExecutionPolicy Bypass -File "%PICKER_SCRIPT%" !PICKER_ARGS!
exit /b !ERRORLEVEL!

:check_run_args
set "SHOULD_PICK_TARGET=1"

:arg_loop
if "%~1"=="" exit /b 0
if /I "%~1"=="-d" set "SHOULD_PICK_TARGET=" & exit /b 0
if /I "%~1"=="--device-id" set "SHOULD_PICK_TARGET=" & exit /b 0
if /I "%~1"=="-h" set "SHOULD_PICK_TARGET=" & exit /b 0
if /I "%~1"=="--help" set "SHOULD_PICK_TARGET=" & exit /b 0
if /I "%~1"=="--version" set "SHOULD_PICK_TARGET=" & exit /b 0
shift
goto arg_loop