# Quick POS - Contexto Unico de Proyecto

Documento unico para trabajar en este repo. Reemplaza y consolida el resto de archivos de `docs/`.

## 1) Objetivo y alcance

Este documento sirve para:

- Entender rapido el flujo funcional de la app.
- Tener el contrato minimo de integracion con backend.
- Recordar reglas clave (offline, idempotencia, multi-moneda, POS).
- Facilitar que nuevas funcionalidades se agreguen sin perder contexto.

## 2) Arquitectura resumida

- **App:** Flutter.
- **API base:** `/api/v1`.
- **Header principal:** `X-Store-Id` en casi todas las llamadas.
- **Errores API:** `{ statusCode, error, message[], requestId }`.
- **Monetario:** montos como `String` decimal.
- **Offline:** cola local + `sync/push`; `opId` idempotente.

## 3) Configuracion local importante

- Archivo: `lib/core/config/app_config.dart`.
- `API_BASE_URL` se toma de `--dart-define` o del `defaultValue`.
- **Emulador Android:** usar `10.0.2.2`.
- **Dispositivo real:** usar IP LAN de la PC (`192.168.x.x`), no `10.0.2.2`.
- `CONFIG_ADMIN_PIN`: clave para configuracion de tienda.

## 4) Flujos funcionales actuales

### 4.1 Inicio / tienda / tasa

1. Guardar o crear `storeId`.
2. Cargar `business-settings`.
3. Mostrar moneda funcional + moneda documento por defecto.
4. Consultar tasa (`exchange-rates/latest`) cuando aplica.

### 4.2 Inventario

1. Listar inventario (`GET /inventory`).
2. Ver detalle + movimientos por producto.
3. Ajustar stock (`POST /inventory/adjustments`) con `opId`.
4. Si no hay red, encolar y sincronizar luego.

### 4.3 Catalogo de productos

1. Listar productos activos (`GET /products`).
2. Crear/editar/desactivar producto.
3. Alta opcional con stock inicial (`POST /products-with-stock`) con `Idempotency-Key`.
4. Soporta SKU/barcode, proveedor, pricingMode y margenes.

### 4.4 Proveedores

1. CRUD de proveedores por tienda.
2. Usar proveedor activo en compras.

### 4.5 POS venta

1. Buscar producto (nombre, SKU, barcode) y agregar al carrito.
2. Manejo de moneda documento + conversion a funcional.
3. Cobro **local**: persiste ticket + cola `sync/push` (`opType: SALE`); no depende de `POST /sales` para autorizar.
4. Cobro mixto: `payments[]` opcional (ej. USD + VES) con validacion de restante antes de confirmar.
5. Si un pago viene en moneda distinta a la moneda documento, se envia `fxSnapshot` en la linea de pago.
6. Precio de linea **congelado** al agregar: pull de catalogo no reprecia el ticket abierto.
7. Producto desactivado: no se agrega desde busqueda; si ya estaba en el ticket, se puede editar qty y cobrar.
8. Stock estimado local (B1): chips + modal/PIN segun `business-settings` y `blockSaleWithoutStock`.
9. Cerrar caja (B2): pantalla dedicada + `cash-sessions` API; cierre offline con pendiente transmitir.
10. **Avance de efectivo:** producto `type=SERVICE` + `pricingMode=MANUAL_PRICE` abre sheet "Monto avance"; el ticket cobra **avance + comisión 10%** (`qty=1`, `price=total`).

### 4.6 Tickets en espera (held)

1. Guardar carrito localmente (no crea venta).
2. Recuperar/renombrar/eliminar ticket guardado.
3. Solo al cobrar se crea la venta real.
4. Al cobrar, si venia de held, ese held se elimina.

### 4.7 Historial y devoluciones

- Historial de ventas (`GET /sales`, `GET /sales/:id`).
- Devoluciones (`POST /sale-returns`).

## 5) Reglas criticas de negocio

### 5.1 Multi-moneda

- Cada tienda tiene moneda funcional.
- Venta/compra puede ir en moneda documento.
- Al confirmar documento, persistir snapshot FX usado.
- No recalcular historicos con tasa nueva.

### 5.2 Idempotencia

- Ajustes/cola: `opId` UUID.
- Ventas: `id` cliente para evitar duplicados por reintento.
- Alta producto+stock: `Idempotency-Key` HTTP obligatorio.

### 5.3 Offline y sync

- Operaciones definitivas van por `sync/push`.
- `held tickets` no son `SALE` ni van a `sync/push` hasta cobrar.
- Pull invalida catalogo y refresca pantallas **sin** repreciar lineas del carrito abierto.
- Auto-sync shell ~240s (silencioso); boton **Sincronizar** en Inicio.
- Inventario administrativo: **online-only** (gate en modulo).
- Modulo Inventario/Stock: no operable sin red (a diferencia del stock estimado del POS).

## 6) Endpoints clave (minimo operativo)

### Configuracion

- `GET /stores/:storeId/business-settings`
- `PATCH /stores/:storeId/business-settings`
- `GET /exchange-rates/latest`
- `POST /exchange-rates`

### Catalogo e inventario

- `GET /products`
- `POST /products`
- `PATCH /products/:id`
- `DELETE /products/:id`
- `POST /products-with-stock`
- `GET /inventory`
- `GET /inventory/:productId`
- `GET /inventory/movements`
- `POST /inventory/adjustments`

### Venta, compras, devoluciones, sync

- `POST /sales`
- `GET /sales`
- `GET /sales/:id`
- `GET /suppliers`
- `POST /suppliers`
- `PATCH /suppliers/:id`
- `DELETE /suppliers/:id`
- `POST /purchases`
- `GET /purchases/:id`
- `POST /sale-returns`
- `GET /sale-returns/:id`
- `POST /sync/push`
- `GET /sync/pull`

### Dashboard (online; por dispositivo)

- `GET /reports/sales/summary`
- `GET /reports/sales/timeseries`
- `GET /reports/sales/payments`
- `GET /pos-devices/:deviceId/dashboard-config`
- `PATCH /pos-devices/:deviceId/dashboard-config`
- `GET /dashboard/device/:deviceId` (kiosk; header `X-Device-Token`)

Notas de contrato vigentes para ventas:

- `POST /sales` acepta `payments[]` opcional.
- `GET /sales/:id` devuelve `payments` + resumen (`paymentsCount`, `paidDocumentTotal`, `changeDocument`).
- `sync/push` (`opType: SALE`) acepta `payload.sale.payments`.
- Codigos de error esperados para cobro mixto:
  - `PAYMENTS_INVALID_AMOUNT`
  - `PAYMENTS_MISSING_FX_SNAPSHOT`
  - `PAYMENTS_FX_PAIR_MISMATCH`
  - `PAYMENTS_TOTAL_MISMATCH`

### Productos `PATCH /api/v1/products/:id` — costo, precio de lista y sugerido (M7)

- **`suggestedPrice`**: valor **derivado** en la **respuesta** (`GET` / `PATCH`): reglas M7 (costo × (1 + margen efectivo/100) cuando aplica), junto con `effectiveMarginPercent`, `marginComputedPercent`, etc. El cliente **no** inventa este campo.

#### Un solo request: costo + alinear `price` al sugerido (soportado en backend)

**Opción A (recomendada)** — body JSON:

```json
{
  "cost": "12.50",
  "applySuggestedListPrice": true
}
```

**Opción B** — misma semántica por query:  
`PATCH /api/v1/products/:id?syncListPriceFromMargin=1` (o `=true`).

**Qué hace el servidor**

1. Aplica primero los campos del body habituales (`cost`, `pricingMode`, `marginPercentOverride`, etc.).
2. Calcula `suggestedPrice` M7 con la misma regla que ya exponen en GET/PATCH.
3. Si ese cálculo arroja un sugerido, **persiste `price`** con ese valor en la **misma** petición.
4. Si **no** hay sugerido (`MANUAL_PRICE`, costo 0, sin margen en tienda/override, etc.), el flag/query **no** cambia `price`; solo aplica el resto del body. Caso borde: único cambio el flag y nada que aplicar ni sugerido → **400** con mensaje claro.

**Restricciones**

- **No** enviar `price` en el body si usan `applySuggestedListPrice: true` o `syncListPriceFromMargin` → **400**.
- Lista blanca estricta: no propiedades fuera del DTO.

**Respuesta**

- Siguen recibiendo `suggestedPrice`, `effectiveMarginPercent`, `marginComputedPercent` coherentes con lo guardado tras el PATCH.

**Cliente Quick POS (recepción / compra):** un solo `PATCH` con `cost` + `applySuggestedListPrice: true` tras registrar la compra (no hace falta segundo PATCH solo con `price`).

### Compras `POST /purchases` y sync `PURCHASE_RECEIVE`

- Lista blanca estricta: no enviar propiedades no definidas (p. ej. `reference` en REST → 400).
- Factura / guia / nota del proveedor: campo **`supplierInvoiceReference`** (string opcional, max **120** en REST; sync puede truncar).
- **`id`** opcional en body: idempotencia (UUID cliente).
- **`documentCurrencyCode`** opcional; si falta, el servidor usa reglas de settings.
- **`fxSnapshot`** opcional; misma forma que en sync (puede incluir `fxSource`).
- **`GET /purchases/:id`**: respuesta incluye `supplierInvoiceReference` opcional.
- Sync `payload.purchase`: mismos conceptos; preferido **`supplierInvoiceReference`**; alias **`reference`** solo en sync (si vienen ambos, gana `supplierInvoiceReference`). Alias **`fx`** = mismo contenido que `fxSnapshot`.

### Sync `POST /sync/push` — ventas `SALE`

- **`GET /ops/metrics`** es solo diagnóstico operativo; el POS **no** necesita `OPS_API_KEY` para sincronizar. Sync usa **`POST /api/v1/sync/push`** con `X-Store-Id` y body `deviceId` + `ops[]`.
- En `payload.sale.lines[]`, **`productId`**, **`quantity`** y **`price`** deben ir como **strings** en el JSON (ej. `"quantity": "2"`). Si Dart serializa números nativos, el backend puede rechazar la validación.
- Si hay **`payments[]`**: `method`, `amount`, `currencyCode` como strings; `fxSnapshot` anidado con campos requeridos también como strings.
- Respuesta puede incluir **`failed[]`** con **`details`** por operación: conviene loguear/mostrar para depuración.
- Si una **`opId`** ya quedó registrada como fallida en servidor, no se re-ejecuta con el mismo id: hace falta **nueva `opId`** (UUID v4) para reenviar la venta corregida.

## 7) Componentes Flutter relevantes

### Core

- `lib/core/config/app_config.dart`
- `lib/core/api/*`
- `lib/core/storage/local_prefs.dart`
- `lib/core/catalog/catalog_invalidation_bus.dart`
- `lib/core/sync/*`
- `lib/core/models/*`

### Features

- `lib/features/inventory/*`
- `lib/features/sale/*`
- `lib/features/suppliers/*`
- `lib/features/dashboard/*` — reportes operativos + kiosk TV
- `lib/features/settings/*` — inicio tienda, config, tasas
- `lib/features/shell/*`

## 8) Checklist para nuevas funcionalidades

Cuando se agregue o cambie una funcionalidad:

1. Definir flujo UX (entrada, validaciones, salida).
2. Confirmar contrato API real (sin inventar campos/endpoints).
3. Aplicar reglas de dinero en string + idempotencia.
4. Definir comportamiento online/offline.
5. Actualizar invalidaciones/refresco de UI.
6. Agregar o ajustar pruebas y correr `flutter analyze`.
7. Actualizar esta seccion con cambios relevantes.

## 9) Convencion de mantenimiento documental

- Mantener **`docs/FRONTEND_INTEGRATION_CONTEXT.md`** como fuente de verdad funcional/técnica.
- Índice: **`docs/README.md`**.
- Excepcion operativa: pruebas manuales en **`docs/MANUAL_TESTS.md`**.
- No crear archivos extra en `docs/` (sprints, contratos duplicados, checklists paralelos).
- Contratos backend completos: Swagger del repo API; aquí solo lo que consume el front.

## 10) Estado Offline (decision vigente)

- Objetivo: app operativa offline en Inicio, Inventario, Catalogo, POS, Compras y Devoluciones.
- Compras: habilitadas offline via cola y `PURCHASE_RECEIVE`.
- Devoluciones: habilitadas offline via cola y `SALE_RETURN`.
- Catalogo: full offline para crear/editar/borrar con sincronizacion posterior.
- Frecuencia de auto-sync: cada 90 segundos + disparo inmediato al reconectar.
- UX de conectividad: indicador visible verde (online) / rojo (offline).
- Regla UX: sync en segundo plano, sin bloquear navegacion ni uso normal.

## 11) Plan V2 integrado (offline + compras + fotos + config URL)

Se integra como referencia ejecutiva el plan `FRONT_OFFLINE_EXECUTION_PLAN_V2.md` recibido desde backend.

### 11.1 Alcance alineado

- Compras proveedor con entrada de stock: usar `POST /purchases` online y `PURCHASE_RECEIVE` offline.
- Offline-first transversal: cola local, `sync/push`, `sync/pull`, lock anti-concurrencia y scheduler.
- Fotos de producto: propuesta en dos fases (preview local + upload background) sujeta a endpoints backend.
- Configuracion dinamica de URL backend: implementada en frontend (Ajustes + perfiles + prueba de conexion).

### 11.2 Estado de ejecucion consolidado

Ver **seccion 15** (backlog y estado). Pruebas manuales: `docs/MANUAL_TESTS.md`.

## 12) QA rapido de validacion offline (movil)

Ejecutar este bloque en Android fisico para validar comportamiento base:

1. Abrir `Inicio -> Configuracion (clave)`.
2. En `Conexion backend`, elegir perfil `LAN`, cargar IP LAN real y tocar `Probar conexion`.
3. Guardar URL y verificar badge global de entorno (`LAN`).
4. Apagar backend y entrar a `POS`, `Buscar precio`, `Inventario`, `Historial`: no debe haber loading infinito.
5. Con backend caido, crear una operacion offline (venta o devolucion) y confirmar que queda en cola.
6. Encender backend, esperar reconexion (o tocar `Sincronizar`) y validar que pendientes bajan.
7. Cambiar a `Produccion` o `Local` desde perfiles y confirmar que badge cambia (`PROD` o `LOCAL`).
8. Registrar evidencia minima (captura + resultado) por escenario para cerrar Fase F.

## 13) Bitacora de cambios recientes

- 2026-04-07:
  - Main shell ajustado a auto-sync cada 90s.
  - Trigger de sync por reconexion mantenido.
  - Lock en auto-sync para evitar ejecuciones concurrentes.
  - Indicador de estado de red agregado en barra inferior (online/offline).
  - Catalogo offline inicial implementado:
    - cache local de productos en `LocalPrefs`,
    - cola local `pending_catalog_mutations_v1` (create/update/deactivate),
    - flush automatico en segundo plano desde `MainShell`,
    - fallback de lectura a cache cuando falla red/API en lista de catalogo.
  - POS offline reforzado:
    - `PosSaleScreen` ahora usa cache local de catalogo si falla `GET /products`,
    - carga `business-settings` desde cache local si falla red,
    - usa cache local de par FX para seguir cobrando en modo offline,
    - al volver red, sync y pull mantienen consistencia.
  - `products-with-stock` offline:
    - en `ProductInitialStockBottomSheet`, si no hay red se encola mutacion local
      tipo `CREATE_PRODUCT_WITH_STOCK` con `Idempotency-Key` persistido,
    - se crea placeholder local en cache de catalogo,
    - `flushPendingCatalogMutations` reintenta esa mutacion al reconectar y
      reemplaza placeholder por producto real del servidor.
  - Read models locales (Inicio/Inventario/Historial):
    - Inicio (`StoreDashboardScreen`) usa cache de `business-settings` si falla red,
    - Inventario (`InventoryStockTab`) guarda y usa cache local de líneas (`inventory_cache_v1`),
    - Historial General (`TicketHistoryScreen`) guarda última consulta y la muestra sin red
      (`sales_general_cache_v1`) cuando no hay respuesta del API.
  - Refuerzo de visibilidad de cache/offline:
    - Tasa del día (`ExchangeRateTodayScreen`) con cache local por par/fecha
      (`latest_rate_cache_v1_*`) y fallback sin red,
    - badge de “mostrando datos cacheados” en Inicio, Inventario y Historial General
      cuando los datos vienen de fallback offline.
- 2026-06-04:
  - Modulo `lib/features/dashboard/*`: dashboard operativo, control por dispositivo (`dashboardEnabled`), kiosk TV.
  - Documentacion consolidada en este archivo + `MANUAL_TESTS.md`.

## 14) Dashboard operativo y kiosk

**Codigo:** `lib/features/dashboard/` (data / domain / presentation).

### 14.1 Dos modos

| Modo | Cuando | Pantalla |
|------|--------|----------|
| **Operativo** | `dashboardEnabled: true` y `deviceMode` ≠ `DASHBOARD` | Boton en Inicio → `DashboardHomeScreen` (online-first) |
| **TV / kiosk** | `deviceMode: DASHBOARD` + token | Arranque → `DeviceDashboardScreen` (refresh ~45s) |

**Control por dispositivo:** `GET/PATCH /pos-devices/:deviceId/dashboard-config` con `X-Store-Id`. El boton operativo **no** aparece en todos los equipos: solo si el servidor devuelve `dashboardEnabled: true` (o se activa con PIN / Postman).

### 14.2 Endpoints (reportes)

Headers habituales: `X-Store-Id`. Montos en JSON como **String**. KPIs **no** recalcular en cliente.

| Uso | Metodo | Ruta |
|-----|--------|------|
| KPIs | GET | `/reports/sales/summary` |
| Serie diaria | GET | `/reports/sales/timeseries` |
| Pagos | GET | `/reports/sales/payments` |
| Por caja (v2) | GET | `/reports/sales/by-device` |
| Kiosk agregado | GET | `/dashboard/device/:deviceId` + header `X-Device-Token` (sin `X-Store-Id`) |
| Config dispositivo | GET | `/pos-devices/:deviceId/dashboard-config` |
| Activar / desactivar | PATCH | `/pos-devices/:deviceId/dashboard-config` |

**Query fechas:** `preset=today|yesterday|week|month` **o** `dateFrom` + `dateTo` (`YYYY-MM-DD`, max 31 dias).

**PATCH admin:** headers `X-Dashboard-Admin-Pin` (y opcional `X-Config-Admin-Pin`, `X-Ops-Api-Key`) = mismos secretos que en el `.env` del Nest (`DASHBOARD_ADMIN_PIN`, `CONFIG_ADMIN_PIN`, `OPS_API_KEY`).

**App:** PIN local en `AppConfig` (default `1200Mia`, override `--dart-define=CONFIG_ADMIN_PIN=...`).

Body ejemplo habilitar solo operativo:

```json
{ "dashboardEnabled": true }
```

Modo TV adicional: `"deviceMode": "DASHBOARD", "regenerateToken": true` → respuesta incluye `dashboardAccessToken` **una vez** (guardar en prefs del kiosk).

### 14.3 Flujo recomendado (operador)

1. Registrar el terminal (venta o `sync/push`).
2. `PATCH dashboard-config` con `dashboardEnabled: true` (Postman o Inicio → “Habilitar dashboard en este dispositivo”).
3. Hot restart → Inicio → **Dashboard operativo**.

### 14.4 Errores frecuentes

| HTTP | Causa |
|------|--------|
| 401 en PATCH | PIN servidor ≠ PIN app |
| 404 en config | `deviceId` aun no registrado en servidor |
| 403 en kiosk | `dashboardEnabled: false` o modo POS |

## 15) Estado de implementacion y pendientes

### 15.1 Offline-first — **cerrado** (salvo auditoria)

Implementado: cola `sync/push`, scheduler 90s, reconexion, caches (catalogo, inventario, settings, FX, historial), ventas/devoluciones/compras/catalogo offline, tickets en espera, cobro mixto `payments[]`, fotos + upload, URL backend configurable (LAN/Local/Prod).

**Pendiente**

- [ ] Auditoria: confirmar que con `shellOnline == false` ninguna mutacion hace HTTP directo sin cola (devoluciones, compras, inventario, catalogo).
- [ ] Ejecutar y marcar casos en `docs/MANUAL_TESTS.md` (seccion offline/conectividad).

### 15.2 Dashboard — **v1 implementado**

Implementado: `DashboardHomeScreen` (3 APIs paralelo), presets fecha, KPIs, grafico, pagos; gating por `dashboardEnabled`; habilitar/deshabilitar con PIN; kiosk + setup TV; cache kiosk 5 min; bootstrap modo `DASHBOARD`.

**Pendiente (v1.1 / v2)**

- [ ] QA manual dashboard → `MANUAL_TESTS.md` seccion 5.
- [ ] `GET /reports/sales/by-device` (comparar cajas).
- [ ] Pull-to-refresh en dashboard operativo.
- [ ] Widget compacto “Hoy: X netas” en Inicio.
- [ ] Comparativo vs semana anterior en KPIs.
- [ ] Modo oscuro dedicado TV.
- [ ] Sincronizar `deviceMode` tras cada `sync/push` (fase 2 backend).

### 15.3 Otros modulos — sin gaps criticos documentados

POS, inventario, proveedores, tasas, onboarding tienda: operativos segun secciones 4–6. Nuevas features: seguir checklist seccion 8.

## 16) Sync push — proveedores (`SUPPLIER_*`)

Referencia minima para cola offline de proveedores (`lib/core/sync/pending_supplier_mutation_entry.dart`).

**`POST /sync/push`** — body: `deviceId`, `ops[]` (1–200). Cada op: `opId` (UUID v4), `opType`, `timestamp`, `payload`.

**opTypes proveedor:** `SUPPLIER_CREATE`, `SUPPLIER_UPDATE`, `SUPPLIER_DEACTIVATE`.

**Payload:** `{ "supplier": { ... } }`.

| opType | Campos clave en `supplier` |
|--------|---------------------------|
| CREATE | `clientSupplierId` (UUID v4 provisional), `name` (1–200), opcionales phone/email/address/taxId/notes |
| UPDATE | id servidor o `clientSupplierId` + campos a cambiar |
| DEACTIVATE | id a desactivar |

Tras ack, remapear ids provisionales (`supplier_sync_remap.dart`). Orden del array `ops` = orden de aplicacion en servidor.
