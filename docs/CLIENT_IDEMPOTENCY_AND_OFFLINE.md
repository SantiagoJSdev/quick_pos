# Idempotencia en cliente y camino a offline

## Objetivo

- Con **red inestable**, reintentar sin **duplicar** efectos en servidor (doble ajuste, doble venta, etc.).
- Con **offline** (fases posteriores), persistir la operación y **reenviar el mismo `opId` y el mismo payload de sync** al volver la conectividad, para que el backend responda `acked` / `skipped` sin doble efecto.

---

## Decisión de arquitectura (cerrada)

**Todo lo que salga de cola persistente** (offline, app cerrada antes de confirmación en servidor, rehidratación tras crash) se envía **únicamente** por **`POST /api/v1/sync/push`**, en la forma de batch y `opType` definidos en **`SYNC_CONTRACTS.md`**.

- **No** se reenvía desde la cola `POST /inventory/adjustments`, `POST /sales`, etc. de forma directa: evita dos implementaciones del mismo negocio (REST vs sync) y un solo lugar para `opId`, `deviceId`, watermarks y manejo `acked`/`skipped`/`failed`.
- **Con red y sesión normal (hoy):** la app puede seguir usando **REST** para respuesta inmediata (p. ej. B3 `InventoryAdjustmentScreen` → `POST /inventory/adjustments`). Eso no contradice la decisión: **la cola aún no existe**; cuando exista, sus filas son **solo** ops de sync listas para batch.
- **Unificación futura opcional:** encolar también el envío “online” y vaciar con `sync/push` inmediato (un solo camino de código); no es requisito para adoptar la regla de cola.

**Ejemplo de forma en cola para un ajuste:** `opType: INVENTORY_ADJUST`, `opId` en la **operación** del batch, `payload` con `inventoryAdjust` (o equivalente en raíz según `SYNC_CONTRACTS.md` § `INVENTORY_ADJUST`). El mismo `opId` lógico debe coincidir con el que ya usa el movimiento en servidor si hubo retry idempotente.

---

## Continuidad: reintento en pantalla (hoy) ↔ cola offline (después)

Es **la misma regla de negocio** en dos almacenes temporales del cliente:

| Situación | Dónde vive el intento | `opId` | Cuerpo enviado al servidor |
|-----------|------------------------|--------|----------------------------|
| Fallo de red / 5xx con el formulario abierto | Memoria en `InventoryAdjustmentScreen` | Se **conserva** entre “Reintentar envío” | **Idéntico** al intento anterior (mismos campos) |
| Usuario sin red o app pasa a segundo plano antes de confirmar envío | **Cola persistente** (SQLite u otro) | `opId` en la **operación** del batch sync; **no** regenerar al reabrir la app | **Payload `sync/push`** (`opType` + `payload` según `SYNC_CONTRACTS.md`), no body REST |

**Qué no debe pasar:** encolar o reintentar con un **nuevo** `opId` para la **misma** decisión de negocio (“sumar 5 por inventario físico”), salvo que el usuario haya **cambiado** el formulario (nueva intención).

**Qué sí debe pasar al implementar cola offline (acorde a la decisión anterior):**

1. Con red caída, al “confirmar”: generar `opId` de operación, construir **un ítem de batch** listo para `sync/push` (`opType`, `payload` con forma `INVENTORY_ADJUST` / `SALE` / … según `SYNC_CONTRACTS.md`), **serializar y guardar** (incluido `opId` a nivel de op).
2. Al recuperar red: el worker arma batch(es) ≤200 ops y llama **solo** `POST /api/v1/sync/push` con `deviceId` y demás cabeceras del contrato.
3. Interpretar **`acked` / `skipped` / `failed`** por op; `skipped` idempotente → marcar fila como sincronizada.

**Reintento en pantalla (B3 con REST)** sigue siendo válido **mientras** el usuario no cerró la pantalla: mismo `opId` y mismo body REST. Si en el futuro el ajuste offline se guarda **solo** en cola sync, al abrir de nuevo la app el reenvío será **solo** por `sync/push` (no mezclar ese registro con un segundo envío REST con otro formato).

---

## REST en línea vs cola (referencia rápida)

| Contexto | Vía |
|----------|-----|
| Online, formulario abierto, `InventoryAdjustmentScreen` | `POST /inventory/adjustments` + `opId` en body (implementado) |
| Cualquier operación **persistida en cola** | **Solo** `POST /sync/push` |

El `opId` de idempotencia debe ser **el mismo concepto** que el servidor asocia al movimiento (p. ej. `StockMovement.opId` en ajustes vía sync, ver `SYNC_CONTRACTS.md`).

---

## Orden de implementación recomendado

Orden para **no dejar huecos** entre idempotencia en UI y offline:

| Fase | Qué | Estado |
|------|-----|--------|
| **0** | Mutaciones con `opId` / `id` en **pantalla**: generar al confirmar, reutilizar en reintento, invalidar si el usuario cambia el payload tras fallo | **B3 hecho** (`InventoryAdjustmentScreen` + `ClientMutationId`) |
| **1** | **Venta POS:** `POST /sales` con `id` (UUID) de cliente + mismo patrón de reintento / mensaje si `skipped` o idempotente | Pendiente (P3) |
| **2** | **Detección de conectividad** (p. ej. `connectivity_plus`) + mensajes UX “sin red” / no bloquear cierre de ticket sin persistir decisión | Pendiente |
| **3** | **Cola persistente:** SQLite (u otro); cada fila = op de sync (`opType`, `opId`, `payload` JSON alineado a `SYNC_CONTRACTS.md`), estado, timestamps, errores | Pendiente |
| **4** | **Worker al volver online:** **solo** `POST /sync/push` en batch(es); **no** drenar con REST directo | Pendiente |
| **5** | **UI “Pendientes / errores”** para reintentar manual o descartar (con política clara: descartar solo si negocio lo permite) | Pendiente |
| **6** | **`sync/push` completo** (batch, `deviceId`, watermarks) y alinear ops de inventario/venta con `SYNC_CONTRACTS.md` | Pendiente (Sprint 3 §3.3) |
| **7** | **`sync/pull`**, catálogo local, conflictos de lectura | Pendiente |

Las fases **2–5** pueden arrancar después de tener **P3** con `id` de venta, o en paralelo si el equipo divide trabajo. La **3** modela filas **ya** como ops de sync (no como “REST congelado”).

---

## Checklist: cosas que no deben faltarse al cerrar offline + sync

- [ ] **Un `opId` por intención** — no regenerar al leer de disco ni al reiniciar app para el mismo registro de cola.
- [ ] **Cola = solo sync** — el worker **no** llama `postAdjustment` / `postSale` REST para vaciar cola.
- [ ] **Payload estable** — el JSON guardado es el `payload` de la op en batch; cambios de negocio ⇒ nueva op / nuevo `opId`.
- [ ] **Tratar `skipped` en respuesta de sync** como éxito para esa op (idempotencia).
- [ ] **`deviceId`** obligatorio en `sync/push` cuando se use batch (ya documentado en contrato).
- [ ] **No duplicar filas locales** con el mismo `opId` para la misma tienda.
- [ ] **Errores 4xx** distintos de idempotencia: no reintentar en bucle infinito; marcar `error` y mostrar al usuario.
- [ ] **Ventas offline:** `fxSnapshot` y moneda documento coherentes con lo cobrado (misma obligación que online).

---

## Regla general (resumen)

1. Cada **mutación** idempotente en API lleva **UUID en cliente** por **intención de operación**.
2. **Reintento** (pantalla o cola): **mismo** `opId` y **mismo** payload.
3. **Cambio de payload** después de fallo (solo en pantalla hoy): **nuevo** `opId`.
4. Tras **éxito** en servidor (`applied`, venta creada, cola marcada synced): ese flujo termina; la siguiente operación es **nueva**.

---

## Estado en la app (por módulo)

| Módulo | Endpoint / flujo | Campo idempotencia | Estado |
|--------|------------------|--------------------|--------|
| Ajuste inventario (B3) en línea | `POST /inventory/adjustments` | `opId` en body | Implementado |
| Ajuste / venta / … **desde cola** | `POST /sync/push` | `opId` por operación en batch | Pendiente (diseño cerrado: solo esta vía) |
| Venta POS (Sprint 2) en línea | `POST /sales` | `id` opcional (venta) | Pendiente (P3) |

---

## Código reutilizable

- `lib/core/idempotency/client_mutation_id.dart` — `ClientMutationId.newId()`.
- `lib/core/sync/inventory_adjust_payload_builder.dart` — `InventoryAdjustPayloadBuilder.fromForm(...)` → `toRestBody(opId:)` (online) y `toSyncPayload()` (cola / `INVENTORY_ADJUST`). **Una sola fuente** de verdad para campos del ajuste.

Al añadir pantallas que posteen con idempotencia, seguir el patrón de B3: asignar id la primera vez que pasa validación y se va a red; invalidar si el usuario altera el payload tras un fallo **en esa pantalla**.

---

## Punto de implementación: “guardar sin red” en B3 (checklist para no perderse)

Cuando implementes cola offline para ajustes, **no** serializar el body REST tal cual. Seguir:

1. **Usar** `InventoryAdjustPayloadBuilder.fromForm(...).toSyncPayload()` como JSON a guardar en la fila de cola (es el `payload` de la op `INVENTORY_ADJUST`).
2. **`opId`** de la operación: mismo UUID que usarías en línea (`ClientMutationId.newId()`), almacenado en el **ítem del batch**, no dentro de `inventoryAdjust`.
3. **Contrato** mínimo del payload: `SYNC_CONTRACTS.md` (~líneas 219–231); el servidor también acepta el objeto en raíz del `payload` — el builder usa envoltorio `inventoryAdjust` como en el ejemplo del doc.
4. **Al drenar:** solo `POST /sync/push` con `opType: INVENTORY_ADJUST` (decisión de arquitectura cerrada arriba).

- [ ] Conectividad: si no hay red, persistir op + `opId` + `toSyncPayload()` (no llamar REST).
- [ ] Worker: batch con ops construidas como arriba.
- [ ] Si más adelante unificás envío online por sync, reutilizar el **mismo** `toSyncPayload()` + `opId` en batch (sin duplicar lógica de campos).

---

## Referencias

- `FRONTEND_INTEGRATION_CONTEXT.md` §13.7 (ajustes + `opId`).
- `SYNC_CONTRACTS.md` — `sync/push`, `INVENTORY_ADJUST`, `SALE`, `opId`.
- `docs/DESARROLLO_CHECKLIST.md` — §2.3 Offline, §3.3 Sync.
