# Auditoría DEMS — 2026-06-17

Barrido de funcionalidades, gaps de configuración y errores a resolver.
Plataforma de evaluación de prototipos IPN-DEMS (Rust/Axum + Flutter offline-first).

**Método:** fan-out por subsistema (API + mobile) → diff de contrato front/back contra el
inventario de rutas → **verificación manual de cada hallazgo High/Med contra el código real**.
Un hallazgo del agente (mismatch de método en `/phase`) resultó falso al verificar y fue descartado.

Joya de la corona: **integridad de scores** y **correctitud de la sincronización offline** en el
evento LAN. Las severidades están ponderadas por ese contexto.

---

## Resumen ejecutivo

| # | Severidad | Hallazgo | Subsistema |
|---|-----------|----------|------------|
| 1 | 🔴 P0 | Sin refresh de token (401) en el cliente + access TTL de 15 min → el jurado no puede sincronizar tras 15 min, sin recuperación automática | mobile + config |
| 2 | 🔴 P0 | `submit` tras respuesta perdida envenena la fila (409 eterno, pending nunca llega a 0) | mobile sync |
| 3 | 🔴 P0 | Replay idempotente descarta ediciones de score (pérdida silenciosa) | mobile sync + API |
| 5 | 🟠 P1 | PATCH dirty contra fila ya enviada → 409 → fila atascada dirty para siempre | mobile sync |
| 6 | 🟡 P2 | Sin gate de fase de edición en create/submit/patch de evaluación | API |
| 7 | 🟡 P2 | Idempotencia no compara (prototipo, template) | API |
| 8 | 🟡 P2 | El cliente nunca reconcilia datos más nuevos del servidor (p.ej. reopen) | mobile |
| 9 | 🟡 P2 | "Rotación" de refresh sin denylist: token robado válido 30 días | API |
| 10 | 🟡 P2 | CORS no montado pese a tener el feature activo | API/config |
| 11 | 🟡 P2 | APK/AAB firmados con llave debug | CI |
| 19 | 🟡 P2 | Ranking mezcla versiones de rúbrica, pero `max_total` sólo de la activa | API |
| 20 | 🟡 P2 | No existe puntaje final combinado exhibición+memoria (pesos 60/50 sin aplicar) — confirmar reglamento | API/producto |
| 4 | 🟢 P3 | Limpiar un **text answer** diverge del servidor (NO afecta scores ni ranking) | mobile + API |
| 12-18 | 🟢 P3 | Endurecimiento (CHECK en DB, 500→422, Swagger público, CSV injection, timing login, SQLite sin cifrar, guard de JWT_SECRET) | varios |

> **Gradiente de certeza en los P0:** **#1 es determinista** — pasa a *todo* jurado, *cada* vez, a los 15 min de sesión. **#2 y #3 requieren la carrera de respuesta-perdida** (el servidor commitea pero la red cae antes de que el cliente reciba la respuesta): menos frecuentes, pero silenciosos y de alto impacto. Atacar #1 primero.

---

## P0 — Críticos (integridad de datos / disponibilidad en el evento)

### 1. Sin refresh de token en el cliente + access TTL de 15 min
**`apps/mobile/lib/data/api/api_client.dart:23-33` · `auth_repository.dart:31` · `evaluaciones_repository.dart:93-117` · `.env` / `deploy/windows/.env.example:18`**

- `api_client` sólo tiene un interceptor `onRequest` que adjunta el bearer. **No hay interceptor `onError`/401, no hay reintento, no hay llamada a refresh.**
- `AuthRepository.refresh()` (POST /auth/refresh) y `me()` (GET /me) **existen pero no se llaman desde ningún lado** (los `.refresh()` del código son métodos de controladores Riverpod, no del token). El comentario de `auth_storage.dart` que dice que `/me` se "re-valida en background" es falso.
- `JWT_ACCESS_TTL_SECS=900` (15 min) en **todos** los `.env`, incluido el del servidor Windows offline.
- En `evaluaciones_repository._map` el **401 no está contemplado** → cae a `EvaluacionUnexpected` → `onSyncError` → la fila queda `dirty` y reintenta para siempre sin recuperarse.

**Impacto:** en el evento LAN, a los 15 min de sesión el access token expira; toda request 401ea, ninguna se refresca. El jurado sigue evaluando offline (los datos locales están a salvo) pero **nada vuelve a sincronizar** hasta logout/login manual — y puede no darse cuenta. Combinación tóxica de un valor de config + una feature a medio cablear.
**Fix:** interceptor Dio `onError` que en 401 llame `refresh`, reintente y, si falla, haga logout. Subir el access TTL para el evento (p.ej. 8 h) es mitigación parcial pero no sustituye el wiring.
**Confianza: Alta** (verificado: api_client sin onError; refresh sin callers; _map sin 401).

### 2. `submit` tras respuesta perdida envenena la fila
**`apps/mobile/lib/data/sync/sync_worker.dart:164-170` · `evaluacion_routes.rs:438-442` · `evaluaciones_repository.dart:102-107`**

Si el `submit` se ejecuta en el servidor pero la respuesta se pierde, local queda `submittedAt==null, submitRequested==true`. La siguiente sync re-llama `submitEvaluacion` → el servidor responde **409 "already submitted"** → mapeado a `EvaluacionConflict` (subtipo de `EvaluacionFailure`) → `onSyncError`. La fila conserva `submitRequested==true` **para siempre**: re-submite y 409ea en cada sync; el contador `pending` nunca baja a 0.
**Impacto:** en el evento se lee como "mi evaluación no se guardó" aunque sí está registrada.
**Fix:** tratar el 409 "already submitted" como éxito — hacer GET y llamar `onSubmittedRemote` con el `submitted_at` del servidor.
**Confianza: Alta** (mecanismo verificado en ambos lados).

### 3. Replay idempotente descarta ediciones de score
**`apps/api/crates/api/src/routes/evaluacion_routes.rs:105-120` · `sync_worker.dart:141-152` · `evaluaciones_dao.dart:144-156`**

El handler `create`, ante un replay con el mismo `(jurado_id, client_id)`, hace `load_evaluacion` y devuelve la evaluación **existente** con 200 — **ignora por completo `req.scores`**. El cliente (`createEvaluacion`) descarta el status code y `sync_worker:152` llama `onCreatedRemote` que pone `serverId` y limpia `dirty` **incondicionalmente**.
**Impacto:** si el 201 original se perdió (red cae tras el commit), la fila queda `serverId==null, dirty`; el jurado sigue puntuando; la siguiente sync re-POSTea los scores **nuevos** con el mismo `client_id` → el servidor devuelve los **viejos** y descarta los nuevos → el cliente limpia `dirty` → **los scores nuevos nunca llegan al servidor**. Pérdida silenciosa, indetectable por el cliente.
**Fix:** que `createEvaluacion` exponga el status; en un replay (200) con datos locales más nuevos, no limpiar `dirty` — forzar un `patchEvaluacion` de seguimiento.
**Confianza: Alta** en el mecanismo; el disparo requiere la ventana de respuesta perdida.

---

## P1 — Altos (integridad de scores)

### 5. PATCH dirty contra fila ya enviada → fila atascada
**`apps/mobile/lib/features/evaluaciones/data/evaluaciones_repository.dart:59-80` · `evaluacion_routes.rs:336-340`**

Un PATCH dirty que corre contra un submit del servidor (o tras un submit con respuesta perdida) recibe **409 "already submitted; cannot edit"** → `EvaluacionConflict` → `onSyncError` → la fila queda `dirty` para siempre, re-PATCHeando y 409eando en cada sync. Misma clase que #2.
**Fix:** ante 409 de fila ya enviada, reconciliar vía GET y limpiar `dirty` en vez de registrar error fatal.
**Confianza: Media.**

---

## P2 — Medios

### 6. Sin gate de fase de edición al evaluar
**`evaluacion_routes.rs:95 / :313 / :419` · `migrations/20260605000001_edition_phase.sql`**
Sólo la **estructura** de la rúbrica se congela por fase; `create`, `patch` (draft) y `submit` de evaluación **no** verifican que la edición esté en fase `evaluacion`. Un jurado asignado puede crear/enviar scores con la edición en `preparacion` o `cerrada`. (Los scores ya enviados sí son inmutables — patch/submit dan 409 sobre `submitted_at`.) → es un gap de ventana/ciclo de vida, no edición arbitraria.
**Fix:** gatear create/submit/patch-draft sobre `edition.phase = 'evaluacion'`. **Confianza: Alta** en comportamiento, Media en si `cerrada` debe bloquear.

### 7. Idempotencia no compara la terna
**`evaluacion_routes.rs:105-120`** — el replay sólo busca por `(jurado_id, client_id)`, sin comparar `prototipo_id`/`template_id`. Reusar un `client_id` para otra terna devuelve la evaluación vieja con 200 y descarta la nueva. **Fix:** incluir la terna en el lookup o devolver 409 si difiere. **Confianza: Alta.**

### 8. El cliente nunca reconcilia datos más nuevos del servidor
**`apps/mobile/lib/features/evaluaciones/application/evaluacion_controller.dart:129`** — `build()` sólo hidrata desde remoto cuando no hay `serverId`; después la copia local es autoritativa. Un `reopen` del admin (`submitted_at → NULL`) nunca se refleja en el dispositivo. Radio pequeño en el modelo per-jurado, pero el reopen no funciona end-to-end. **Confianza: Media.**

### 9. "Rotación" de refresh sin denylist
**`evaluacion_routes`/`auth_routes.rs:179-187`** — los tokens son stateless, sin `jti` ni tabla denylist (no existe en migraciones). El comentario afirma que la rotación "limita el impacto si un refresh se filtra" — **falso**: un refresh robado es válido sus 30 días completos aunque el usuario legítimo refresque; sólo se revoca rotando `JWT_SECRET` (que desloguea a todos). **Fix:** tabla de denylist/`jti` o versión de token por usuario. **Confianza: Alta.**

### 10. CORS no montado
**`main.rs` / `routes.rs:24-115`** — el feature `cors` está activo en `Cargo.toml:20` pero **no se monta ninguna capa CORS**. No es el riesgo de `Any` permisivo — es lo contrario: cero acceso cross-origin de navegador. Confirmar que el build web se sirve same-origin (tras el mismo nginx); si la web vive en otro origen, fallará el preflight. **Fix:** allow-list explícita si hace falta (nunca `Any`). **Confianza: Alta** en que no hay capa.

### 11. APK/AAB firmados con llave debug
**`.github/workflows/release.yml`** (documentado en la cabecera) — instalables por sideload, pero **no aptos para Play Store ni para actualizar in-place** sobre una versión firmada con otra llave. Secrets de keystore no configurados. Limitación conocida; planificar keystore propio si se distribuye.

### 19. El ranking mezcla versiones de rúbrica, pero `max_total` es sólo de la activa
**`apps/api/crates/api/src/routes/admin_results.rs:119-139` (max_total, `AND activo`) vs `:168-171` y `:326-329` (totales, sólo filtro `tipo`)**
El cálculo de `total`/`promedio` incluye evaluaciones submitted de **cualquier** versión de rúbrica del tipo (el filtro es `tipo` sin `activo`), pero `max_total` se calcula sólo de la rúbrica **activa**. Si una rúbrica se reemplaza a mitad de edición (segunda versión con distinto `max_score`), los promedios mezclan escalas de versiones distintas y se comparan contra un `max_total` de otra versión → ranking inconsistente, e incluso `promedio > max_total` posible.
**Mitigación actual:** si la estructura se congela por fase y nunca se crea una segunda rúbrica activa por (edición, tipo), no se dispara. Pero la asimetría activo/no-activo es real y frágil.
**Fix:** decidir una política — o sólo contar evaluaciones de la rúbrica activa, o versionar `max_total` por template. **Confianza: Alta** en la asimetría; Media en si se dispara en la práctica.

### 20. No existe puntaje final combinado exhibición + memoria
**`admin_results.rs` (todo el módulo)** — los endpoints devuelven ranking **por tipo de rúbrica por separado** (`exhibicion` *o* `memoria`). Los pesos del reglamento (exhibición 60% / memoria 50%, por tu memoria) **no se aplican en ningún lado del backend**; no hay un endpoint que combine ambos en un puntaje final ponderado por prototipo.
**Impacto:** si el concurso exige un ranking final combinado, esa lógica no existe (ni en API ni en la app, que llama el mismo endpoint por tipo). Si los dos rankings separados son por diseño, no es un bug.
**Acción:** confirmar con el reglamento si se requiere puntaje final combinado. **Confianza: Alta** en que no existe; pendiente confirmar si se necesita.

---

## P3 — Bajos (endurecimiento)

- **4.** Limpiar una **respuesta de texto** (criterio `text_key`) diverge del servidor: `setText` con texto vacío → `dao.setScore(…, null, null)` borra la fila local (`evaluaciones_dao.dart:85-90`), pero el PATCH del servidor es upsert puro y nunca borra (`evaluacion_routes.rs:367-393`) → el texto viejo permanece en el servidor. **No afecta scores ni ranking** (los `text_key` no se puntúan ni cuentan en totales). Los scores `scale`/`boolean` **no** son vulnerables: `setScore` recibe un `int` no-nullable desde la UI, así que nunca se borran. **Confianza: Alta** en mecanismo; impacto Bajo (sólo texto cualitativo).

- **12.** Sin `CHECK` en BD para rango de score ni para `boolean ∈ {0, max}` — sólo validación en app (`validate_scores_against_template`). Cualquier write futuro que evite ese helper persiste scores fuera de rango. `migrations/20260416000001_init.sql` (tabla `evaluacion_scores`).
- **13.** `create` devuelve **500** ante un `criterion_id` duplicado en `scores[]` (unique violation no mapeada; sólo se mapea `is_check_violation`) — debería ser 422 por convención. `evaluacion_routes.rs:207-216`.
- **14.** `/docs` (Swagger) y `/openapi.json` **públicos** en prod → disclosure del esquema completo. `routes.rs:112`.
- **15.** CSV export no escapa `= + - @` iniciales → formula injection al abrir en Excel. `admin_results.rs` (`csv_escape`).
- **16.** Enumeración de usuarios por timing en login (argon2 sólo corre para email conocido). `auth_routes.rs:57-75`.
- **17.** SQLite local (`dems.sqlite`) sin cifrar — scores offline y rúbrica en claro en el dispositivo (los tokens sí están en `FlutterSecureStorage`). `data/db/connection/native.dart`.
- **18.** `config.rs` acepta `JWT_SECRET` placeholder sin validar (no rechaza el default ni exige longitud mínima). Mitigado en prod (rotado) y en el bundle Windows (CI genera aleatorio); riesgo sólo si alguien corre con el `.env` de dev. `config.rs:21`.

---

## Gaps de configuración (resumen)

| Gap | Dónde | Riesgo |
|-----|-------|--------|
| `JWT_ACCESS_TTL_SECS=900` (15 min) + sin refresh en cliente | todos los `.env` | 🔴 corta la sync en el evento (ver #1) |
| Sin guard de arranque que rechace `JWT_SECRET` por defecto / exija longitud | `config.rs` | 🟢 prod ya rotado; bundle genera aleatorio |
| Capa CORS no montada pese a feature activo | `main.rs` | 🟡 confirmar topología web |
| Swagger `/docs` + `/openapi.json` públicos | `routes.rs:112` | 🟢 disclosure de esquema |
| Android sin keystore propio (secrets no configurados) | `release.yml` | 🟡 no Play Store / no update in-place |
| `.env` dev y `.env.example` idénticos con secreto débil | raíz | 🟢 `.env` **no** trackeado (correcto) |

---

## Diff de contrato front/back

- **Todas** las llamadas del mobile mapean a una ruta real del backend. (El inventario del agente etiquetó `/admin/editions/:id/phase` como PATCH; al verificar, el cliente usa **POST** — coincide con el backend. Falso positivo descartado.)
- **Huérfano en backend:** `POST /admin/evaluaciones/:id/reopen` existe y **ningún consumidor lo llama** desde la app → los admins **no pueden reabrir** una evaluación enviada desde la app (gap funcional; ¿intencional/futuro?).
- **Código muerto en cliente:** `AuthRepository.refresh` y `me` definidos sin llamadas → ligado al gap de refresh (#1).

---

## Lo que está BIEN (balance)

- Todas las rutas `/admin/*` llevan `RequireAdmin`; **ninguna** ruta admin sin guard.
- El rol se lee **fresco de la BD** en cada request (`extractors.rs`), no se confía en el claim del JWT; usuarios inactivos rechazados al instante.
- Ownership de evaluaciones enforced (owner-or-admin en read, owner-only en patch/submit); `refresh` rechaza access tokens (sin confusión de tipo).
- Escrituras multi-fila en transacción; `ON DELETE RESTRICT` protege los scores capturados.
- argon2id con salt por hash y verify constante.
- **Matemática de resultados sólida en lo esencial:** sólo cuenta evaluaciones `submitted_at IS NOT NULL` (los borradores NO se filtran al ranking), división en punto flotante (sin truncamiento entero), jurado parcial manejado (media sobre lo entregado + `n_jurados` expuesto), orden determinista (sort estable + desempate por folio). Las salvedades están en #19/#20.
- `error.rs` mapea status codes correctamente (400/422/409) y **no filtra internals**.
- Runtime server config correcto: `api_client` usa `serverConfigProvider`, no `Env` directo; cambiar de servidor **preserva** los datos locales no sincronizados (sólo limpia tokens).
- `.env` no trackeado; secreto prod rotado; el bundle Windows genera `JWT_SECRET` aleatorio en CI.
- `openapi.json` verificado en CI (gate de sincronización front/back).

---

## Alcance / no auditado a fondo

La cobertura es **desigual a propósito**: se priorizó la ruta de captura/sync de scores, auth/admin
y la matemática de resultados (joyas de la corona). Recibieron sólo **inventario o lectura superficial**,
y podrían esconder hallazgos no listados aquí:

- **Editor de rúbricas** (`admin_rubrics::replace_structure` y `rubric_editor_page.dart`) — sólo se confirmó que escribe en transacción; no se auditó la lógica de validación de estructura ni el editor del cliente.
- **CRUD admin** (users, prototipos, editions, categorias, assignments) — se verificó que todos llevan `RequireAdmin`; no se auditó cada validación de negocio.
- **Migraciones / esquema** — leídas para constraints de scores; no se auditó a fondo (índices, cascadas, tipos).
- **Tema/UI, widgets, router, splash** — fuera de alcance (no afectan integridad de datos).
- **Tests** — se inventariaron (existe `evaluacion_idempotent`, `seed_dev_idempotent`, etc.); no se ejecutaron ni se evaluó su cobertura real.

## Orden de ataque sugerido

1. **#1 (refresh 401)** — el único P0 *determinista* y de máximo impacto en el evento; feature acotada. Mitigación inmediata: subir el access TTL del evento (p.ej. 8 h) mientras se cablea el refresh.
2. **#2, #5 (filas envenenadas por 409)** — tratar 409 como reconciliación, no como error fatal.
3. **#3, #7 (pérdida/divergencia de scores en la carrera)** — exponer status en `create`, comparar terna en idempotencia.
4. **#6 (gate de fase)** — cerrar la ventana de scoring fuera de fase.
5. **#20** — confirmar con el reglamento si hace falta puntaje final combinado (puede ser trabajo de producto, no bug).
6. P3 — endurecimiento BD (CHECK de score), #19, y los demás según tiempo.

---

## Estado de implementación (2026-06-17)

Implementado en la rama `fix/auditoria-2026-06-17` (API 226 tests verdes, mobile 34 verdes,
`openapi.json` en sync). Verificado con dos rondas de implementación + revisión adversarial
multi-agente que **atrapó una regresión** (el 409 del gate de fase reenvenaba el sync) — corregida
y cubierta con test antes de cerrar.

| # | Estado | Cómo |
|---|--------|------|
| 1 | ✅ | Interceptor Dio de refresh 401 (single-flight) en `api_client.dart`; TTL access → 1h |
| 2 | ✅ | submit 409 `already_submitted` se reconcilia (no envenena) |
| 3 | ✅ | `createEvaluacion` expone replay (200); encadena PATCH conservando dirty |
| 4 | ✅ | PATCH del servidor reemplaza el set completo (borra ausentes en tx) |
| 5 | ✅ | PATCH 409 reconcilia vía GET; **preserva trabajo local si el remoto sigue borrador** |
| 6 | ✅ | Gate de fase en create/submit/patch (sólo `evaluacion`); `submitted_at` se chequea antes |
| 7 | ✅ | Idempotencia compara la terna (prototipo, template) → 409 `client_id_reused` |
| 8 | ✅ | Reconcile al abrir (gated por dirty/submit-pendiente para no pisar trabajo local) |
| 9 | ✅ | `token_version` por usuario: revoca **access** (extractor) **y refresh**; comentario falso corregido |
| 10 | ✅ | CorsLayer (permisivo seguro: auth Bearer sin cookies → sin CSRF) |
| 11 | ✅ | `signingConfig` release condicional (key.properties / secrets) con fallback a debug; `release.yml` materializa el keystore |
| 12 | 🟡 parcial | CHECK `score >= 0`; la cota superior/`boolean∈{0,max}` requiere trigger cross-tabla (queda en validación de app, documentado) |
| 13 | ✅ | Dedup de `criterion_id` → 422 |
| 14 | ✅ | `ENABLE_DOCS` (default **false** fail-safe; prod no expone Swagger salvo opt-in) |
| 15 | ✅ | CSV: prefija `= + - @` (anti formula-injection) |
| 16 | ✅ | Login: verify contra hash dummy para email inexistente (anti-timing) |
| 17 | ✅ | SQLite cifrado con SQLCipher (clave en SecureStorage) + recuperación ante llave perdida; desktop puede degradar (no es target de release) |
| 18 | ✅ | `warn_if_weak_jwt_secret` (no falla arranque) |
| 19 | ✅ | Resultados cuentan sólo la rúbrica **activa** (cierra la asimetría con `max_total`) |
| 20 | ✅ | **`peso` por rúbrica** configurable en el CRUD (migración + modelo + UI + seed 60/50) + nuevo `GET /admin/results/edition/{id}/final` con puntaje ponderado |

**Pendiente de operación (no es código):** poner `ENABLE_DOCS=false` en el `.env` de prod (`/opt/dems`)
— con el default fail-safe ya queda apagado si no se setea. Para firma real de Android (#11), subir los
secrets `ANDROID_KEYSTORE_*` en GitHub. #20 combinado: el reglamento define el `peso` por rúbrica.
