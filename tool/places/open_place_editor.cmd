@echo off
setlocal
cd /d "%~dp0\..\.."
set "SCRIPT=tool\places\preview_places.py"

echo Starting Nuuk City Live place editor...

where python >nul 2>nul
if not errorlevel 1 (
  python "%SCRIPT%"
  if not errorlevel 9009 goto done
)

py -3 "%SCRIPT%"
if not errorlevel 1 goto done

echo.
echo Python 3 is not installed, or the Windows py launcher points to a missing Python install.
echo This editor needs Python 3 with tkinter. The standard Windows Python installer includes tkinter.
echo.
where winget >nul 2>nul
if errorlevel 1 goto no_winget

choice /M "Install Python 3.12 for this user with winget now"
if errorlevel 2 goto done

winget install --id Python.Python.3.12 -e --scope user --accept-package-agreements --accept-source-agreements
if errorlevel 1 goto done

set "PY312=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
if exist "%PY312%" (
  "%PY312%" "%SCRIPT%"
  goto done
)

py -3 "%SCRIPT%"
goto done

:no_winget
echo Install Python from https://www.python.org/downloads/windows/ and run this launcher again.

:done
echo.
pause
