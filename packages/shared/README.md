# shared — OpenAPI spec

Spec OpenAPI 3.1 de la API REST de DEMS, generado a partir de las
anotaciones `#[utoipa::path]` en `apps/api/crates/api/src/routes/`.

## Regenerar

```bash
just openapi-export
```

equivalente a:

```bash
cd apps/api && cargo run --bin openapi-export -- ../../packages/shared/openapi.json
```

## Verificar en CI

```bash
just openapi-check
```

Falla si el JSON committeado diverge de lo que produciría el código actual.
Si esto falla en CI, regenera localmente y commitea.

## Consumir desde Flutter

```bash
# desde apps/mobile
dart run openapi_generator generate \
    --input ../../packages/shared/openapi.json \
    --output lib/data/api/generated
```

(o cualquier otro generador que prefieras — el spec es 3.1 estándar).
