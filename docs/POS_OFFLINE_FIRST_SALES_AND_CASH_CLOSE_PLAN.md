# Plan por pasos — POS offline-first + sync en background + cierre de caja

**Estado:** propuesta para análisis / decisión de alcance (actualizado con matriz online/offline)  
**Relacionado:** [`POS_NEGATIVE_STOCK_FRONTEND_IMPLEMENTATION.md`](./POS_NEGATIVE_STOCK_FRONTEND_IMPLEMENTATION.md)  
**Contexto base:** [`FRONTEND_INTEGRATION_CONTEXT.md`](./FRONTEND_INTEGRATION_CONTEXT.md)

Este documento sirve para **decidir qué módulos se tocan y cuáles no**. No es contrato de API. Al cerrar decisiones, se actualiza el doc de implementación de stock negativo y el contexto de integración.

---

## 1. Objetivo de producto (una frase)

El cajero **cobra y busca** contra datos locales. La API **no interrumpe** la operación (sin spinners de red en POS). Inventario/stock administrativo es **solo online**. Sync y actualización de catálogo van **en trasfondo**. Al fin de turno: botón **Cerrar caja**.

```text
POS / Historial / Precios  →  100% cache local (lectura + cobro)
Inventario / Stock         →  solo con red (consultas y ajustes al server)
Sync / Pull catálogo       →  background silencioso (240s, reconectar, Inicio Sync, cierre)
Cerrar caja                →  acción de turno (conteo + flush forzado + resumen)
```

---

## 1.1 Matriz de modos (decisión de producto)

| Módulo / acción | Offline | Online | ¿Consulta API al abrir? | Notas |
|-----------------|---------|--------|-------------------------|--------|
| **POS (cobrar, carrito, escaneo)** | Sí | Sí (mismo flujo local) | **No** | Solo lee cache; nunca bloquea UI por red |
| **Búsqueda de precios** | Sí | Sí | **No** al abrir; usa catálogo cache | Refresh silencioso solo vía sync global |
| **Historial de tickets** | Sí | Sí | **No** para historial local del día | Listado server (si existe) = opcional / otra pestaña, no bloquea |
| **Tickets en espera** | Sí | Sí | No | Ya local |
| **Inventario / Stock / ajustes / movimientos** | **No** | **Sí** | Sí | Si no hay red → mensaje claro, no cache “falso” de movimientos |
| **Alta/edición producto con stock** | **No** | **Sí** | Sí | Alineado a “productos online-only” actual |
| **Sync push/pull** | Encola | Envía | Nunca en foreground del POS | Shell timer / reconectar / **botón Inicio** / cierre |
| **Sincronizar (Inicio)** | No (pide Online) | **Sí** | Al pulsar | Trae precios + tasa + vacía cola; feedback en snackbar |
| **Cerrar caja** | Sí (cierre local + pendiente transmitir) | Sí (flush + pull + resumen) | Solo al confirmar cierre, no al vender | Botón visible, no reemplaza Sync |

---

## 2. Qué ya tenemos vs qué falta

| Capacidad | Hoy en Flutter | Gap |
|-----------|----------------|-----|
| Catálogo / settings / FX cacheados | Sí (`LocalPrefs`) | POS debe **dejar de** re-fetch al entrar si hay cache fresco |
| Ticket activo persistente | Sí | Mantener |
| Cola de ventas `opId` + flush | Sí | Cobro **solo** por cola (sin POST como gate) |
| Auto-sync ~240s + reconectar | Sí (shell) | Debe ser **silencioso** (sin spinner/modal en POS); intervalo decidido Paso 0 |
| Historial tickets recientes local | Parcial | Garantizar offline-first + badges sync |
| Búsqueda de precios | Hoy suele pegarle a API al `_load` | Pasar a **solo cache** (+ sync background) |
| Inventario / stock | Mezcla cache + API | **Hecho Paso 3:** gate online-only en módulo |
| Decremento stock estimado en POS | Débil | Opcional: qty estimada local solo para chips/warn; inventario “real” solo online |
| Cierre de caja | **No** | **Incluir** en el epic (botón + flujo) |
| Barra: pendientes + última sync | Parcial | Completar sin molestar operación |

---

## 3. Arquitectura: cobro local + actualización barata

### 3.1 Un solo camino de cobro

```text
1. Validar ticket en dispositivo (pagos, FX, líneas) — sin API
2. Reglas de stock ESTIMADO local (warn / PIN / block) — sin API
3. Persistir venta + encolar SALE
4. (Opcional) ajustar qty estimada local para chips
5. Feedback inmediato “Venta registrada”
6. Sync background (shell) — no await en UI de cobro
```

Online y offline = **mismo código**.

### 3.2 Regla de oro en POS: cero red en el camino crítico

Mientras el cajero está en POS:

| Permitido | Prohibido |
|-----------|-----------|
| Leer catálogo/FX/settings/stock estimado desde cache | `listProducts` / `getBusinessSettings` / stock API en `initState` o cada cobro |
| Encolar venta en prefs | Esperar `POST /sales` para vaciar el ticket |
| Mostrar “pendientes: N” desde contador local | Overlay de carga por sync |
| Sync del shell en background | Bloquear teclado/cobro porque “está sincronizando” |

Si al abrir POS **no hay cache**: mostrar “Sin catálogo local — conectá una vez para sincronizar”, no un spinner eterno pegándole a la API en bucle.

### 3.3 Cómo se actualiza un producto sin gastar recursos

Cuando en otra caja/admin cambia precio o se desactiva un producto:

```text
Shell (background, cada 240s o al reconectar)
  → sync/push (cola ventas, etc.)
  → sync/pull (cambios desde watermark)
  → si hay ops de catálogo/precio: actualizar cache local
  → invalidar bus (CatalogInvalidationBus) SOLO si cambió algo
  → POS, si está abierto: refresca lista en memoria SIN spinner
     y SIN tocar líneas ya en el carrito (precio congelado)
```

Principios de eficiencia:

1. **Pull incremental** (watermark `since`) — no re-descargar todo el catálogo cada ciclo.
2. **No pull al tocar cada producto** en POS.
3. **Debounce** invalidación: un solo `setState` si llegaron N cambios juntos.
4. **TTL / “última sync OK”** en barra: el cajero ve frescura sin forzar refresh.
5. **Cierre de caja** es el único momento operativo donde un sync “fuerte” (push+pull) puede mostrar progreso, porque el turno ya paró de vender.

### 3.4 Stock: dos capas (importante)

| Capa | Dónde | Modo | Uso |
|------|-------|------|-----|
| **A — Stock estimado POS** | Cache local (qty tras ventas del dispositivo) | Offline OK | Chips Exacto/Estimado/Negativo, warnings al cobrar |
| **B — Inventario administrativo** | Módulo Inventario | **Solo online** | Ajustes, movimientos, cantidades “oficiales”, conciliación |

Decisión alineada a tu pedido:

- **Inventario y stock (módulo) = solo online.** Sin red → no se opera; mensaje “Necesitás conexión”.
- El POS **no** abre pantallas de inventario ni consulta movimientos al vender.
- El pull de background puede **refrescar qty estimada** en cache para chips, sin abrir Inventario.

Así no mezclamos “estoy vendiendo offline” con “estoy ajustando inventario como si fuera offline”.

### 3.5 Sync continuo vs cierre

| Mecanismo | Rol |
|-----------|-----|
| Auto-sync **240s** + reconectar | Transmitir ventas y traer precios **sin molestar** |
| **Botón Sincronizar en Inicio** | Cuando el cajero sabe que cambió un precio o la tasa y no quiere esperar el ciclo |
| Botón Sync en POS (opcional) | Misma idea, sin salir de venta |
| **Cerrar caja** | Fin de turno: conteo efectivo + flush forzado + pull + resumen + confirmar |

El cierre **no reemplaza** el sync continuo.

### 3.6 Cierre offline + marca “pendiente transmitir”

**Qué significa:** el cajero **sí puede cerrar el turno** aunque no haya red y queden ventas (u ops) en cola. El cierre queda guardado en el dispositivo; al volver online se transmite la cola y, cuando exista API B2, también el cierre remoto.

**Dónde se marca (UI + datos locales):**

| Dónde | Qué ve / qué guarda |
|-------|---------------------|
| Modelo local `cash_session` | Campo tipo `transmitStatus`: `synced` \| `pending_transmit` \| `failed` |
| Pantalla al confirmar cierre sin red | Mensaje: “Caja cerrada · pendiente transmitir” |
| Inicio / barra shell | Badge o chip: “Cierre pendiente de enviar” (hasta sync OK) |
| Resumen del cierre (reabrir historial del turno) | Lista: ventas synced vs aún en cola; estado de la sesión |
| Tras sync exitoso | La marca pasa a `synced` y el badge desaparece |

**Flujo corto:**

```text
Cerrar caja (sin red o con cola que no pudo salir)
  → guardar cash_session closed + transmitStatus=pending_transmit
  → ventas siguen en pending_sales (igual que siempre)
  → al reconectar / Sincronizar / auto-sync 240s:
       flush cola → (luego) enviar cierre remoto si B2
       → transmitStatus=synced
```

No es una marca en cada producto: es de la **sesión de caja** + el contador de pendientes de siempre.

---

## 4. Módulos: tocar / no tocar

### 4.1 Backend (coordinación)

| Cambio | ¿Tocar? | Notas |
|--------|---------|--------|
| Políticas negativo / warnings / restringidos | B1 | Necesario para que la cola no falle por stock |
| `sync/push` SALE tolera negativo según política | B1 | |
| API cash-sessions | B2 | FE puede cerrar **solo local** primero |
| PIN supervisor server | No | Solo app |

### 4.2 Flutter — por módulo

| Módulo | ¿Tocar? | Cambio clave |
|--------|---------|--------------|
| `pos_sale_screen.dart` | **Sí** | Cobro solo local; **quitar** loads de red en camino crítico; aplicar invalidación silenciosa |
| Shell auto-sync | **Sí** | Silencioso; persistir `lastSuccessfulSyncAt`; no UI bloqueante |
| `product_price_lookup_screen.dart` | **Sí** | Leer cache; no `listProducts` al abrir |
| Historial tickets (recent / UI venta) | **Sí** | Offline-first local; sync badge en background |
| Inventario / stock tabs | **Sí** | Gate online-only; sin operar en offline |
| `local_prefs` + cache catálogo/FX | **Sí** | Watermark, last sync, sesión caja |
| Feature **Cerrar caja** | **Sí (incluir)** | Botón + flujo resumen |
| Dashboard | No (este epic) | |
| Proveedores | No | |

### 4.3 Explicitamente no hacer

| Tema | Motivo |
|------|--------|
| Re-fetch catálogo cada vez que entras a POS | Gasta red y muestra carga innecesaria |
| Spinner de sync encima del cobro | Molesta la operación |
| Inventario offline “a medias” | Pedido: stock/inventario solo online |
| SQLite rewrite ahora | Prefs + cola alcanzan para este epic |

---

## 5. Plan por pasos

### Paso 0 — Decisiones (cerrar en reunión)

- [x] Cobro contra local; API no autoriza cobro *(propuesta adoptada)*
- [x] Inventario/stock administrativo **solo online**
- [x] Historial tickets + búsqueda precios **offline**
- [x] Sync **trasfondo**, no molesta POS
- [x] Incluir **botón Cerrar caja** en el epic
- [x] Incluir **botón Sincronizar** en Inicio (manual: precios + tasa + cola)
- [x] Intervalo auto-sync: **240s** (4 min)
- [x] Cierre offline con pendientes: **sí**, permitir y marcar sesión **“pendiente transmitir”** (ver §3.6)
- [x] Este epic: **solo cierre** de caja (sin apertura/fondo todavía)
- [x] Stock estimado en POS: mostrar qty **real** (ej. `-2`), no solo warning

**Paso 0 cerrado → siguiente: Paso 1 (cobro local + POS sin red en foreground).**

---

### Paso 1 — F1: Cobro local + POS sin red en foreground

1. [x] Checkout siempre → persistir + cola (mismo online/offline).
2. [x] Eliminar await de `POST /sales` como condición para vaciar ticket.
3. [x] Al abrir POS: si hay cache → pintar ya; **no** spinner de red.
4. [x] Sync solo vía shell / post-cobro `unawaited` silencioso.
5. [x] Pull/invalidación: actualizar `_all` sin `_loading = true`.
6. [x] Decremento stock estimado local al confirmar (`applyLocalInventoryDecrements`).

**Listo:** modo avión, entrar a POS, cobrar, sin “cargando…” de API.

---

### Paso 2 — F1b: Precios + historial offline

1. [x] `product_price_lookup_screen`: bootstrap desde `loadCatalogProductsCache`.
2. [x] Historial: listar `recent_sales` / tickets locales sin red (sin sondear `GET /sales`).
3. [x] Indicador “puede estar desactualizado” si última sync &gt; umbral (30 min).
4. [x] Pestaña General: cache primero; red solo si online.

**Listo:** avión → consultar precio y ver tickets del día.

---

### Paso 3 — F1c: Inventario solo online

1. [x] Al entrar a Inventario/Stock sin red → pantalla bloqueo amable + reintentar.
2. [x] No operar inventario offline (gate a nivel módulo; stock estimado del POS aparte).
3. [x] Copy: qty oficial = Inventario online; POS usa estimado local.

**Listo:** offline no permite ajustar stock; online sí.

---

### Paso 4 — F2: Política stock estimado en POS (UI)

1. [x] Chips Exacto / Estimado / Sin verificar / Puede quedar negativo (sobre cache).
2. [x] Modal negativo + PIN restringido (app).
3. [x] Flags B1 en settings/producto + payload (`stockConflictDetected`, `inventoryValidationMode`).
4. [x] Depende de B1 para que sync no falle *(backend listo)*.

**Listo:** cobro local con política de stock estimado alineada a B1.

---

### Paso 5 — F3: Botón Cerrar caja (incluir)

1. [x] Entrada visible (Inicio y menú Venta): **Cerrar caja**.
2. [x] Flujo: conteo efectivo → sync push+pull → resumen → confirmar.
3. [x] Offline: cerrar local + “pendiente transmitir”; sync reintenta envío.
4. [x] Apertura automática (`openingCash: 0`) al cobrar / al abrir cierre (sin UI de fondo).
5. [x] API `docs/CASH_SESSIONS.md` (`CashSessionsApi` + `CashSessionService`).

**Listo:** fin de jornada con botón operativo de supervisor/cajero.

---

### Paso 6 — F4: Pulido

1. [x] Precio congelado en carrito ante pull de precios (`_rebuildCartDocumentPrices` solo FX/moneda).
2. [x] Producto desactivado: cobrar si ya estaba en ticket; no agregar nuevos; editar peso sin catálogo.
3. [x] Tests en `MANUAL_TESTS.md` (`MT-POS-013`, `MT-POS-014`).
4. [x] Actualizar `FRONTEND_INTEGRATION_CONTEXT.md` (§4.5 / §5.3).

**Listo:** epic offline-first + stock + cierre + pulido de ticket.

---

## 6. UX consolidada

### Barra / shell (no intrusiva)
- Online / Offline  
- Pendientes  
- Última sync OK (hora)  
- Catálogo desactualizado (texto discreto, no modal)

### Inicio
- Botón **Sincronizar** (manual): cola + precios + tasa, con feedback  
- No sustituye el auto-sync ni el cobro local

### POS
- Sin spinners de red  
- Cobro instantáneo local  
- Sync invisible salvo badge de pendientes

### Precios e historial
- Funcionan sin red sobre cache/cola local

### Inventario
- Requiere conexión; no se finge offline

### Cerrar caja
- Visible, formal, al final del turno  
- Único momento donde sync “se siente” a propósito

---

## 7. Qué más contemplar

1. **Apertura de caja** (fondo) — sin ella el diff de efectivo es débil.  
2. Una sesión por dispositivo.  
3. Devoluciones/anulaciones en el resumen del turno.  
4. Pagos mixtos: solo efectivo en el conteo físico.  
5. Held tickets al cerrar: listar o exigir vaciar.  
6. Ops `failed`: no reenviar mismo `opId`.  
7. Feature flag si B1 aún no está (vende local, sync puede fallar con mensaje claro).  
8. **No** invalidar carrito abierto con precios nuevos del pull.  
9. Throttle de pull: si el POS está cobrando intenso, el shell no debe pelear el isolate/UI (prioridad a input del cajero).

---

## 8. Orden de PRs sugerido

| PR | Contenido | Molesta al cajero? |
|----|-----------|--------------------|
| **PR1** | Cobro solo cola + POS sin fetch bloqueante | No — mejora |
| **PR2** | Precios + historial offline-first | No |
| **PR3** | Inventario gate online-only | No en POS |
| **PR4** | Cerrar caja (local) | Solo al cerrar turno |
| **PR5** | Chips/modales stock + B1 | Warns controlados |
| **PR6** | cash-sessions API cuando B2 exista | — |

---

## 9. Criterios de aceptación

- [x] En POS, con o sin red: no hay spinner de `listProducts` / settings al vender.
- [x] Cambio de precio en server llega por pull background; carrito abierto no se reprecia solo.
- [ ] Avión: cobro OK, precios OK, historial local OK.
- [x] Avión: Inventario **no** operable.
- [x] Sync no muestra modal ni bloquea cobro.
- [x] Existe **Cerrar caja** con conteo + flush + resumen.
- [ ] Tras cierre con red: cola vacía o errores explícitos en resumen.

---

## 10. Próximo paso

**Pasos 0–6 listos.** Criterios de aceptación §9: ejecutar QA con `MANUAL_TESTS.md` (incl. `MT-POS-013`/`014`).
