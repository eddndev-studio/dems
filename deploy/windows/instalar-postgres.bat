@echo off
setlocal enabledelayedexpansion
title DEMS - Instalador de PostgreSQL
cd /d "%~dp0"

REM ===================== AJUSTA ESTO =====================
REM  Carpeta donde quedara instalado PostgreSQL (la "ruta").
set "INSTALL_DIR=C:\pgsql"
REM  Version de PostgreSQL (binarios portables de EnterpriseDB).
set "PG_VERSION=16.6-1"
REM ======================================================

set "ZIP=%~dp0postgresql-%PG_VERSION%-windows-x64-binaries.zip"
set "URL=https://get.enterprisedb.com/postgresql/postgresql-%PG_VERSION%-windows-x64-binaries.zip"
set "PGBIN=%INSTALL_DIR%\bin"
set "PGDATA=%INSTALL_DIR%\data"
set "PGPORT=5432"

echo ============================================================
echo   Instalando PostgreSQL %PG_VERSION% en  %INSTALL_DIR%
echo ============================================================

REM ---------- 1) Conseguir el ZIP (local o descarga) ----------
if exist "%PGBIN%\initdb.exe" (
  echo [1/5] PostgreSQL ya esta en "%INSTALL_DIR%". Salto la instalacion.
  goto :initdb
)
if not exist "%ZIP%" (
  echo [1/5] Descargando PostgreSQL... ^(necesita internet UNA vez^)
  powershell -NoProfile -Command "try { Invoke-WebRequest -Uri '%URL%' -OutFile '%ZIP%' -UseBasicParsing; exit 0 } catch { Write-Host $_.Exception.Message; exit 1 }"
  if errorlevel 1 (
    echo.
    echo [ERROR] No se pudo descargar. Sin internet:
    echo   1^) En otra PC baja:  %URL%
    echo   2^) Copia ese .zip junto a este .bat ^(mismo nombre^) y reejecuta.
    pause & exit /b 1
  )
) else (
  echo [1/5] Usando ZIP local: %ZIP%
)

REM ---------- 2) Extraer a INSTALL_DIR ----------
echo [2/5] Extrayendo...
if exist "%TEMP%\dems_pg" rmdir /S /Q "%TEMP%\dems_pg"
powershell -NoProfile -Command "Expand-Archive -Path '%ZIP%' -DestinationPath '%TEMP%\dems_pg' -Force" || (echo [ERROR] No se pudo extraer el ZIP. & pause & exit /b 1)
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
REM El zip de EDB trae una carpeta raiz "pgsql"; copiamos su contenido a INSTALL_DIR.
xcopy /E /I /Y "%TEMP%\dems_pg\pgsql\*" "%INSTALL_DIR%\" >nul
rmdir /S /Q "%TEMP%\dems_pg"
if not exist "%PGBIN%\initdb.exe" (echo [ERROR] No quedo "%PGBIN%\initdb.exe". Revisa el ZIP. & pause & exit /b 1)

:initdb
REM ---------- 3) Inicializar el cluster ----------
if not exist "%PGDATA%" (
  echo [3/5] Inicializando base de datos en "%PGDATA%"...
  "%PGBIN%\initdb.exe" -U postgres -A trust -E UTF8 -D "%PGDATA%" || (echo [ERROR] initdb fallo. & pause & exit /b 1)
) else (
  echo [3/5] Cluster ya existe en "%PGDATA%".
)

REM ---------- 4) Arrancar + crear rol y base 'dems' ----------
echo [4/5] Arrancando PostgreSQL en el puerto %PGPORT%...
"%PGBIN%\pg_ctl.exe" -D "%PGDATA%" -o "-p %PGPORT%" -l "%INSTALL_DIR%\pg.log" -w start
"%PGBIN%\psql.exe" -U postgres -p %PGPORT% -d postgres -c "CREATE ROLE dems LOGIN PASSWORD 'dems';" 2>nul
"%PGBIN%\psql.exe" -U postgres -p %PGPORT% -d postgres -c "CREATE DATABASE dems OWNER dems;" 2>nul

REM ---------- 5) Restaurar datos si hay dump ----------
if exist "%~dp0dems_seed_data.sql" (
  echo [5/5] Restaurando datos ^(152 prototipos, edicion 2026, admin, rubricas^)...
  "%PGBIN%\psql.exe" -U dems -p %PGPORT% -d dems -v ON_ERROR_STOP=1 -f "%~dp0dems_seed_data.sql" || (echo [ERROR] restauracion fallo. & pause & exit /b 1)
) else (
  echo [5/5] No hay dems_seed_data.sql aqui. La BD queda vacia.
  echo        dems-api.exe creara las tablas al arrancar; usa seed-db.bat para datos base.
)

echo.
echo ============================================================
echo   LISTO. PostgreSQL instalado y corriendo.
echo   bin   = %PGBIN%
echo   datos = %PGDATA%   ^(puerto %PGPORT%^)
echo.
echo   Siguiente: ejecuta  run-server.bat   para arrancar el API.
echo   Detener Postgres:  "%PGBIN%\pg_ctl.exe" -D "%PGDATA%" stop
echo ============================================================
pause
