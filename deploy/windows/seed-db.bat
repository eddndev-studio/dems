@echo off
REM Carga datos BASE (categorias, admin admin@dems.local/admin1234, plantillas de
REM rubrica) en una BD vacia. Requiere que dems-api.exe haya arrancado al menos una
REM vez (para crear las tablas via migraciones) y que PostgreSQL este corriendo.
REM NO usar si ya restauraste dems_seed_data.sql (ese trae todo, incluidos prototipos).
cd /d "%~dp0"
echo Cargando datos base con seed.exe ...
seed.exe
echo.
pause
