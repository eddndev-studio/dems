# Guía de Actualización y Despliegue del Servidor (IPN DEMS)

Esta guía documenta los pasos exactos que el responsable del servidor debe seguir para aplicar los últimos cambios de código y cargar la nueva información (prototipos, jurados, rúbricas y cuentas de administrador) en la base de datos de producción.

## 1. Descargar los últimos cambios

El primer paso es asegurar que el código fuente en el servidor esté actualizado con la rama `error-correddtion` (donde se resolvieron los problemas del Excel y el ordenamiento).

Desde la terminal del servidor, en la carpeta del repositorio:

```bash
git fetch origin
git checkout error-correddtion
git pull origin error-correddtion
```

## 2. Aplicar Migraciones de la Base de Datos

Si hay cambios en el esquema de Postgres, es importante asegurar que la base de datos esté alineada:

```bash
cd apps/api
cargo sqlx migrate run
```

> [!NOTE]
> Se requiere tener la variable de entorno `DATABASE_URL` configurada previamente en el servidor apuntando a su base de datos Postgres (ej. `postgres://user:pass@localhost:5432/dems`).

## 3. Poblar la Base de Datos (Seeder)

Este es el paso **más importante** para que aparezca la nueva información en la aplicación móvil. El "seeder" se encargará de leer los archivos Excel/CSV de los 70 prototipos y jurados, así como de establecer el correo de los jurados como su contraseña, y de inyectar las rúbricas extraídas.

Para ejecutarlo, corre el siguiente comando dentro de `apps/api`:

```bash
cargo run --release --bin dems-seed
```

> [!IMPORTANT]  
> Asegúrate de ejecutar este comando **después** de las migraciones y **antes** de reiniciar la API pública, para que los usuarios (jurados y administradores) ya puedan iniciar sesión.
> 
> **Usuarios Administradores generados:**
> - `admin1@dems.local`
> - `admin2@dems.local`
> - `admin3@dems.local`
> *(Contraseña por defecto para administradores: `admin1234`)*

## 4. Recompilar e Iniciar la API

Una vez que los datos han sido sembrados exitosamente, compila la última versión de la API (que incluye el parche del Excel exportable):

```bash
# Compilar para producción
cargo build --release --bin dems-api

# Levantar el servicio
./target/release/dems-api
```

*(Si usan Systemd, Docker, o PM2, simplemente reinicia el servicio correspondiente para que tome el nuevo binario compilado).*

---

### Resumen de Cambios Aplicados
- **Excel (`/api/admin/results/export`)**: Se refactorizó para exportar un archivo `.xlsx` real con dos hojas ("Ranking General" y "Desglose por Jurados").
- **Evaluaciones**: El sistema de ordenación prioriza las rúbricas no enviadas. Las vistas móviles fueron depuradas para eliminar cualquier mención al campo "plantel" (para mantener la imparcialidad de los jurados).
- **Móvil**: La aplicación ahora cuenta con SplashScreen y Logo oficial del IPN DEMS integrados.
