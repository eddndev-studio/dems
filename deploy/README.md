# DEMS — Despliegue a producción (VPS2)

API: **https://dems.eddndev.work** · host: VPS2 (`212.56.47.243`) · dir: `/opt/dems`

Stack: Docker Compose (`api` + `postgres` dedicado) detrás de nginx + Let's Encrypt.
La API corre migraciones al arrancar (`sqlx::migrate!`); el `seed` base se corre una vez.

## Primer despliegue

```bash
# 1. Sincronizar el repo a /opt/dems (desde la máquina de desarrollo)
rsync -az --exclude target --exclude apps/mobile/build \
  ./ vps2:/opt/dems/

# 2. Secrets (en VPS2)
cd /opt/dems/deploy
cp .env.prod.example .env
#   POSTGRES_PASSWORD=$(openssl rand -hex 24)
#   JWT_SECRET=$(openssl rand -hex 32)

# 3. Levantar el stack (build del API + postgres)
docker compose -f docker-compose.prod.yml --env-file .env up -d --build

# 4. Seed base (categorías + admin + plantillas) — una sola vez
docker compose -f docker-compose.prod.yml --env-file .env run --rm api seed

# 5. nginx + TLS
cp nginx/dems.eddndev.work.conf /etc/nginx/sites-available/
ln -s /etc/nginx/sites-available/dems.eddndev.work.conf /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx
certbot --nginx -d dems.eddndev.work
```

## Redespliegue

```bash
rsync -az --exclude target --exclude apps/mobile/build ./ vps2:/opt/dems/
ssh vps2 'cd /opt/dems/deploy && docker compose -f docker-compose.prod.yml --env-file .env up -d --build'
```

## Operación

```bash
# Logs
docker compose -f docker-compose.prod.yml logs -f api
# Salud
curl -s https://dems.eddndev.work/healthz   # liveness
curl -s https://dems.eddndev.work/readyz    # readiness (DB)
# Swagger / OpenAPI
#   https://dems.eddndev.work/docs
```

## Notas

- **Admin por defecto**: `admin@dems.local` / `admin1234` — **cambiar tras el primer login**.
- `deploy/.env` vive solo en el VPS, nunca se commitea.
- El API solo escucha en `127.0.0.1:8090`; el acceso público es vía nginx.
- DNS `dems.eddndev.work` en modo *DNS only* para emitir el cert; pasar a *proxied*
  (Cloudflare) una vez verificado el TLS de origen.
