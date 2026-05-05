@echo off
:: Unofficial VLC Addons Installer
:: Auto-elevates to admin

net session >nul 2>&1
if not %errorLevel% == 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/k %~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

:menu
cls
echo.
echo  ================================
echo   Unofficial VLC Addons Installer
echo  ================================
echo.
echo  1) Auto Install  (closes VLC, installs, reopens VLC)
echo  2) Manual Install Instructions
echo  3) Close
echo.
set /p choice=" Select option: "

if "%choice%"=="1" goto :auto
if "%choice%"=="2" goto :manual
if "%choice%"=="3" exit /b
goto :menu

:manual
cls
echo.
echo  Manual Install Instructions
echo  ===========================
echo.
echo  1. Copy these files:
echo.
echo     unofficial_vlc_intf.lua
echo     -^> C:\Program Files\VideoLAN\VLC\lua\intf\
echo.
echo     unofficial_vlc_addons.lua
echo     -^> %%APPDATA%%\vlc\lua\sd\
echo.
echo     unofficial_vlc_playlist.lua
echo     -^> %%APPDATA%%\vlc\lua\playlist\
echo.
echo     unofficial_vlc_manager.lua
echo     -^> %%APPDATA%%\vlc\lua\extensions\
echo.
echo  2. Open %%APPDATA%%\vlc\vlcrc and set:
echo.
echo     lua-intf=unofficial_vlc_intf
echo     extraintf=luaintf:http
echo     http-host=127.0.0.1
echo     http-port=8181
echo     http-password=vlcaddons
echo.
echo  3. Restart VLC.
echo.
pause
goto :menu

:auto
echo.
echo  Closing VLC...
taskkill /f /im vlc.exe >nul 2>&1
taskkill /f /im vlc-cache-gen.exe >nul 2>&1
:: Kill anything on port 8181
for /f "tokens=5" %%a in ('netstat -ano 2^>nul ^| findstr ":8181 " ^| findstr "LISTENING"') do taskkill /f /pid %%a >nul 2>&1
timeout /t 3 >nul
:: Make sure vlc.exe is fully gone
:waitvlc
tasklist /fi "imagename eq vlc.exe" 2>nul | find /i "vlc.exe" >nul
if not errorlevel 1 (
    timeout /t 1 >nul
    goto :waitvlc
)

echo  Finding VLC...
set VLC_INSTALL=
for %%p in (
    "%ProgramFiles%\VideoLAN\VLC"
    "%ProgramFiles(x86)%\VideoLAN\VLC"
) do (
    if exist "%%~p\vlc.exe" set VLC_INSTALL=%%~p
)

if "%VLC_INSTALL%"=="" (
    echo  ERROR: VLC not found. Please install VLC first.
    pause
    goto :menu
)

echo  Found VLC at: %VLC_INSTALL%

set VLC_USER=%APPDATA%\vlc
set LUA_INTF=%VLC_INSTALL%\lua\intf
set LUA_SD=%VLC_USER%\lua\sd
set LUA_PL=%VLC_USER%\lua\playlist
set LUA_EXT=%VLC_USER%\lua\extensions
set VLCRC=%VLC_USER%\vlcrc

mkdir "%LUA_INTF%" 2>nul
mkdir "%VLC_USER%\lua\intf" 2>nul
mkdir "%LUA_SD%" 2>nul
mkdir "%LUA_PL%" 2>nul
mkdir "%LUA_EXT%" 2>nul

:: Install intf script to both locations
copy /y "%~dp0unofficial_vlc_intf.lua" "%LUA_INTF%\unofficial_vlc_intf.lua" >nul
copy /y "%~dp0unofficial_vlc_intf.lua" "%VLC_USER%\lua\intf\unofficial_vlc_intf.lua" >nul
copy /y "%~dp0unofficial_vlc_addons.lua"   "%LUA_SD%\unofficial_vlc_addons.lua" >nul
copy /y "%~dp0unofficial_vlc_playlist.lua" "%LUA_PL%\unofficial_vlc_playlist.lua" >nul
copy /y "%~dp0unofficial_vlc_manager.lua"  "%LUA_EXT%\unofficial_vlc_manager.lua" >nul

echo  Copied Lua scripts.

powershell -ExecutionPolicy Bypass -Command "$f='%VLCRC%'; $c=[IO.File]::ReadAllText($f); $c=$c -replace '(?m)#?lua-intf=\S*','lua-intf=unofficial_vlc_intf'; $c=$c -replace '(?m)#?extraintf=\S*','extraintf=luaintf'; $c=$c -replace '(?m)#?http-host=\S*','http-host='; $c=$c -replace '(?m)#?http-port=\S*','http-port='; $c=$c -replace '(?m)#?http-password=\S*','http-password='; $c=$c -replace '(?m)#?qt-system-tray=\S*','qt-system-tray=0'; $c=$c -replace '(?m)#?qt-minimize-systray=\S*','qt-minimize-systray=0'; $c=$c -replace '(?m)#?qt-close-to-systray=\S*','qt-close-to-systray=0'; $c=$c -replace '(?m)#?one-instance=\S*','one-instance=0'; $c=$c -replace '(?m)#?one-instance-when-started-from-file=\S*','one-instance-when-started-from-file=0'; if($c -notmatch '(?m)^lua-intf='){$c+=[char]10+'lua-intf=unofficial_vlc_intf'}; if($c -notmatch '(?m)^extraintf='){$c+=[char]10+'extraintf=luaintf'}; [IO.File]::WriteAllText($f,$c)" 
echo  Configured vlcrc.
echo  Freeing port 8181...
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":8181 " ^| findstr "LISTENING"') do (
    echo  Killing PID %%a holding port 8181...
    taskkill /F /PID %%a >nul 2>&1
)
timeout /t 1 >nul

echo  Starting VLC...
start "" "%VLC_INSTALL%\vlc.exe"

echo.
echo  ================================
echo  Done!
echo  Add addons: View - Unofficial VLC Addons Manager
echo  Browse:     View - Internet - Unofficial VLC Addons
echo  Web UI:     http://127.0.0.1:8181
echo  ================================
echo.
pause
