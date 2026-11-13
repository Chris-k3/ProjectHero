@echo off
setlocal
cd /d "%~dp0"
python "%~dp0tools\install_to_zomboid.py"
echo.
echo Instalacion completada en %USERPROFILE%\Zomboid\mods\Zomb-Band_GH3*
echo En Project Zomboid (menu Mods): activa "Zomb-Band III (Guitar Hero Edition)" (ID: ZombBandGH3)
echo y desactiva la version original "Zomb-Band" si la tienes instalada para evitar conflictos.
pause
