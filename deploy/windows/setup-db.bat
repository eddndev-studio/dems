@echo off
setlocal
cd /d "%~dp0"

REM ============================================================
REM  AJUSTA a la carpeta \bin de tu PostgreSQL 16+
REM  (ZIP portable extraido -> p.ej. C:\pgsql\bin)
set "PGBIN=C:\pgsql\bin"
REM ============================================================

set "PGDATA=%~dp0pgdata"
set "PGPORT=5432"

if not exist "%PGBIN%\initdb.exe" (
  echo [ERROR] No encuentro PostgreSQL en "%PGBIN%". Edita PGBIN y reintenta.
  pause & exit /b 1
)

if not exist "%PGDATA%" (
  echo [1/4] Inicializando cluster en "%PGDATA%" ...
  "%PGBIN%\initdb.exe" -U postgres -A trust -E UTF8 -D "%PGDATA%" || (echo [ERROR] initdb & pause & exit /b 1)
)

echo [2/4] Arrancando PostgreSQL (puerto %PGPORT%) ...
"%PGBIN%\pg_ctl.exe" -D "%PGDATA%" -o "-p %PGPORT%" -l "%~dp0pg.log" -w start

echo [3/4] Creando rol y base 'dems' (ignora "ya existe") ...
"%PGBIN%\psql.exe" -U postgres -p %PGPORT% -d postgres -c "CREATE ROLE dems LOGIN PASSWORD 'dems';" 2>nul
"%PGBIN%\psql.exe" -U postgres -p %PGPORT% -d postgres -c "CREATE DATABASE dems OWNER dems;" 2>nul

if exist "%~dp0dems_seed_data.sql" (
  echo [4/4] Restaurando datos desde dems_seed_data.sql ...
  "%PGBIN%\psql.exe" -U dems -p %PGPORT% -d dems -v ON_ERROR_STOP=1 -f "%~dp0dems_seed_data.sql" || (echo [ERROR] restore & pause & exit /b 1)
  echo [OK] Datos restaurados.
) else (
  echo [4/4] No hay dems_seed_data.sql en esta carpeta.
  echo       La BD queda VACIA. dems-api.exe creara las tablas al arrancar;
  echo       luego corre  seed-db.bat  para los datos base ^(categorias, admin, rubricas^).
)

echo.
echo PostgreSQL corriendo en el puerto %PGPORT%. Ahora ejecuta run-server.bat
echo Para detener Postgres:  "%PGBIN%\pg_ctl.exe" -D "%PGDATA%" stop
pause
