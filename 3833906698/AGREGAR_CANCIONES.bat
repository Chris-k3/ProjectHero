@echo off
setlocal
cd /d "%~dp0"
if "%~1"=="" (
    python "%~dp0tools\add_songs.py"
) else (
    python "%~dp0tools\add_songs.py" %*
)
if exist "%USERPROFILE%\Zomboid\mods\Zomb-Band_GH3" (
    echo Sincronizando nuevas canciones con Zomboid...
    python "%~dp0tools\install_to_zomboid.py"
)
echo.
echo Listo! Si agregaste canciones nuevas, ya estan listas para Zomb-Band III.
pause
