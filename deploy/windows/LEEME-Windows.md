# DEMS — Servidor offline en Windows (red local)

Correr el backend de DEMS en una **PC Windows sin internet**, sirviendo a tablets/teléfonos
con la app DEMS por **red local**.

```
   [ Tablets / teléfonos con la app DEMS ]
                 │  WiFi / cable (misma red local)
                 ▼
   http://<IP-DE-ESTA-PC>:8080
                 │
   ┌─────────────────────────────────────────┐
   │  PC Windows = SERVIDOR                    │
   │   dems-api.exe  ──►  PostgreSQL           │
   │  (0.0.0.0:8080)      (localhost:5432)     │
   └─────────────────────────────────────────┘
```

## Contenido del bundle (de CI)

| Archivo | Qué es |
|---|---|
| `dems-api.exe` | Servidor (API). Migra al arrancar y sirve. |
| `seed.exe` | Datos base para BD vacía (categorías, admin, plantillas). |
| `.env` | Configuración (con `JWT_SECRET` ya generado por CI). |
| `setup-db.bat` / `run-server.bat` / `seed-db.bat` | Scripts de arranque. |

> **Datos del concurso**: el bundle de CI **no** incluye los 152 prototipos (son datos, no
> binarios). Para cargarlos, coloca el archivo **`dems_seed_data.sql`** (te lo entrega el
> equipo por separado) en esta misma carpeta antes de correr `setup-db.bat` — lo detecta y
> restaura solo. Sin ese archivo, la BD arranca vacía y puedes usar `seed-db.bat` para datos base.

## Requisito previo (descargar CON internet)

**PostgreSQL 16** para Windows x64. Recomendado el **ZIP portable** (sin instalar como admin):
<https://www.enterprisedb.com/download-postgresql-binaries> → extraer en p.ej. `C:\pgsql\`.

## Pasos

1. Edita `setup-db.bat` y pon la ruta real en `set "PGBIN=C:\pgsql\bin"`.
2. (Opcional) Copia `dems_seed_data.sql` a esta carpeta para tener los datos del concurso.
3. Doble clic en **`setup-db.bat`** (inicializa Postgres + crea BD + restaura datos si hay dump).
4. Doble clic en **`run-server.bat`** → debe decir `listening on http://0.0.0.0:8080`.
5. Prueba local: <http://localhost:8080/healthz> → `{"status":"ok"}`.
6. Firewall (PowerShell admin):
   ```powershell
   New-NetFirewallRule -DisplayName "DEMS API 8080" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow
   ```
7. IP de la PC: `ipconfig` → **IPv4** (ej. `192.168.1.10`). Asigna **IP estática** o reserva DHCP.
8. Desde un dispositivo: `http://192.168.1.10:8080/healthz`.

## ¿Proxy inverso?

**No es necesario.** `dems-api.exe` escucha en `0.0.0.0:8080`; los dispositivos van directo a
`http://<IP>:8080`. Un proxy inverso (Caddy/nginx) solo aporta si quieres puerto 80, HTTPS o un
nombre. Para una LAN cerrada offline, **HTTP directo al 8080 es lo recomendado**.

## ⚠️ La app móvil debe apuntar a esta PC

El APK que apunta a `https://dems.eddndev.work` **no sirve offline**. Hace falta un APK compilado
para `http://<IP>:8080` **con cleartext HTTP permitido** (release lo bloquea por defecto). Eso se
hace con `--dart-define=API_BASE_URL=http://<IP>:8080` + ajuste del `network-security-config` de
Android. Pídelo al equipo cuando la IP estática del servidor esté fijada (o se le agrega a la app
una pantalla para configurar la URL en sitio).

## Arranque automático (opcional)

Registrar `dems-api.exe` y Postgres como servicios con [NSSM](https://nssm.cc), o accesos directos
en la carpeta de Inicio / Programador de tareas.

## Credenciales

- BD restaurada del dump: admin `admin@dems.local` con la contraseña ya rotada por el equipo.
- BD desde `seed.exe`: admin `admin@dems.local` / `admin1234` (cámbiala).
