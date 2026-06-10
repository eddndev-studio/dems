@echo off
cd /d "%~dp0"
echo ============================================
echo   DEMS API - servidor local
echo   Escuchando en http://0.0.0.0:8080
echo   (cierra esta ventana o Ctrl+C para detener)
echo ============================================
echo.
dems-api.exe
echo.
echo El servidor se detuvo.
pause
