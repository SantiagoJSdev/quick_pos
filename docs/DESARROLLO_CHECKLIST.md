# Checklist de desarrollo — Quick POS (Flutter)

Seguimiento del avance frente a la documentación del backend (`FRONTEND_INTEGRATION_CONTEXT.md`, `IMPLEMENTACION_FLUTTER_ANDROID_GEMINI.md`, `SYNC_CONTRACTS.md`, `MULTI_CURRENCY_ARCHITECTURE.md`, políticas API). Puedes marcar `[x]` tú a mano; en sesiones con Cursor el asistente puede ir actualizando las casillas en este archivo al dar por cerrada cada tarea (con commit en el repo).

---

## Mapa de documentos de contrato (índice)

Según **`docs/DOCUMENTOS_A_COPIAR_AL_PROYECTO_FLUTTER.md`**, el backend puede aportar copias en `docs/backend/`; en este repo también están en **`docs/`** (raíz) para trabajo diario.

| Documento | Rol |
|-----------|-----|
| **`docs/FRONTEND_INTEGRATION_CONTEXT.md`** | Contexto general API, JSON por pantalla, FX, cabeceras. |
| **`docs/FRONT_INVENTORY_SUPPLIERS_MARGINS_SYNC.md`** | Inventario UX + proveedores + márgenes; **qué ya existe** vs **fase M7** (endpoint compuesto, márgenes). |
| **`docs/BACKEND_SUPPLIERS_API_PROPOSAL.md`** | Contrato `GET/POST/PATCH/DELETE /suppliers`, `taxId`, compras con proveedor activo. |
| **`docs/BACKEND_PRODUCT_SKU_BARCODE.md`** | SKU opcional / autogenerado, barcode, PATCH `barcode: null`. |
| **`docs/BACKEND_SALES_HISTORY_API.md`** | Listado histórico ventas (pestaña General en historial). |

Variable de build: **`API_BASE_URL`** (`--dart-define`, sin barra final duplicada). Default en código: `lib/core/config/app_config.dart` (emulador `10.0.2.2` + puerto del backend).

---

## Estado actual de la app (snapshot)

**Listo en código** (alineado a los docs anteriores, salvo donde se indica gap):

- **Tienda / FX / cliente HTTP:** enlace tienda, business settings, tasas, `ApiClient`, montos string, `deviceId` / `appVersion`.
- **Inventario:** `GET /inventory`, detalle, movimientos, ajustes + cola sync; **Stock** mezcla líneas API + productos de catálogo sin movimientos (0 disp.); búsqueda nombre/SKU/barcode; **`minStock`** + filtros sin stock / bajo mínimo; escáner B7.
- **Catálogo:** listado, alta/edición/baja producto con contrato **SKU/barcode**; tras alta, opción **cargar stock inicial** (B3).
- **Proveedores:** REST por tienda (`SuppliersApi`, lista con `q` + cursor, alta/edición/baja lógica, `taxId`); recepción compra con proveedor activo y mensaje si **400** por inactivo.
- **Venta:** POS, historial local + `GET /sales`, checkout `POST /sales`, offline + `sync/push`.
- **Compras / devoluciones / sync:** `POST /purchases`, cola; devoluciones; pull + invalidación catálogo.

**Huecos respecto a `FRONT_INVENTORY_SUPPLIERS_MARGINS_SYNC.md` §2–3 (integrables ya o UX):**

- [x] **`supplierId` en producto:** `CatalogProduct` + `toCreateBody` / `toPatchBody` + selector de proveedor activo en `ProductFormScreen` (carga `GET /suppliers` paginado).
- [x] **`minStock` y filtros:** `InventoryLine.minStock` + getters `isOutOfStock` / `isBelowMinimumStock`; chips **Todos / Sin stock / Bajo mínimo** en `InventoryStockTab`; detalle B2 muestra stock mínimo si viene del API.
- [x] **Alta “producto + stock inicial”:** tras **crear** producto, diálogo opcional → **B3** `IN_ADJUST` con motivo sugerido «Inventario inicial» (`ProductFormScreen` + `InventoryAdjustmentScreen.suggestedReason`). Sigue vigente **`POST /products-with-stock` (M7)** para una sola llamada cuando exista.

**Bloqueado por backend M7** (ver §4 del mismo doc + tracker backend): `defaultMarginPercent`, `pricingMode`, `marginPercentOverride`, `effectiveMarginPercent` / precio sugerido, `POST /products-with-stock`, política post-compra sobre precio. La app puede añadir **calculadora local** de margen sin persistir hasta que exista API.

---

## Plan paso a paso sugerido (siguiente trabajo Flutter)

Orden recomendado; marcar en las secciones inferiores del checklist al cerrar cada ítem.

1. **Mantener docs** al día: al cambiar el backend, recopiar según `DOCUMENTOS_A_COPIAR_AL_PROYECTO_FLUTTER.md` (o `docs/backend/` solo lectura).
2. ~~**`supplierId` en catálogo**~~ — hecho.
3. ~~**Inventario `minStock` + filtros**~~ — hecho.
4. ~~**Flujo post-crear → stock inicial**~~ — hecho (diálogo + B3).
5. **Cuando M7 exista en API:** `products-with-stock`, settings de margen, campos de pricing en producto — integrar y actualizar este checklist + `FRONTEND_INTEGRATION_CONTEXT`.

---

## 0) Entorno y emulador (antes de codificar features)

### 0.1 Emulador Android (teléfono virtual)

**Opción A — Terminal (recomendado si ya existe un AVD)**

1. Listar emuladores: `flutter emulators`
2. Arrancar el que elijas (en este PC el id es `Medium_Phone_API_36.1`):

   ```bash
   flutter emulators --launch Medium_Phone_API_36.1
   ```

3. Esperar a que abra la ventana del emulador.
4. Comprobar que Flutter lo ve: `flutter devices` (debe aparecer un dispositivo `android`).
5. Ejecutar la app desde la raíz del proyecto:

   ```bash
   cd C:\Users\GUEST\AndroidStudioProjects\quick_pos
   flutter pub get
   flutter run -d android
   ```

   Si hay varios dispositivos, usa el id que muestre `flutter devices` (ej. `flutter run -d emulator-5554`).

**Opción B — Android Studio**

1. Abrir Android Studio → **More Actions** → **Virtual Device Manager** (o **Tools → Device Manager**).
2. Play ▶ en el AVD deseado (o **Create Device** si no tienes ninguno: teléfono + imagen del sistema con API recomendada por Flutter).
3. Con el emulador encendido, en terminal: `flutter devices` y `flutter run -d android`.

**Dispositivo físico (opcional)**

- Activar **Opciones de desarrollador** y **Depuración USB**.
- Cable USB; instalar drivers si Windows no reconoce el teléfono.
- `flutter devices` debe listar el modelo → `flutter run -d <id>`.

**Red hacia el backend en emulador**

- `localhost` del PC = `http://10.0.2.2:<puerto>` desde el emulador (puerto = el del Nest; en proyecto el default en `app_config.dart` suele coincidir, ej. `3002` → `http://10.0.2.2:3002/api/v1`).

- Solo **debug**: en `AndroidManifest.xml`, `android:usesCleartextTraffic="true"` en `<application>` si usas HTTP. En producción, HTTPS.

**Checklist emulador**

- [x] AVD arrancado y visible en `flutter devices` (ej. `sdk gphone64 x86 64` / `emulator-5554`).

### 0.2 Cursor / VS Code

- [x] Extensiones **Dart** y **Flutter** (Dart Code) instaladas.
- [x] `flutter doctor` sin errores bloqueantes (ya verificado en este entorno).
- [x] Proyecto abierto en la carpeta que contiene `pubspec.yaml`.

### 0.3 Contrato API en el repo

- [x] Documentación de backend accesible en el proyecto (raíz o `docs/backend/` según convenga).
- [ ] Postman: `QuickMarket_API.postman_collection.json` importado y variables `baseUrl` / `storeId` probadas contra un servidor real *(pendiente a propósito: se validará al ir desarrollando e integrando)*.

---

## 1) Sprint 1 — Configuración tienda, tasas, inventario, productos, proveedores

### 1.0 Navegación principal (`MainShell`)

- [x] Menú inferior **NavigationBar**: **Inicio** (tienda + tasas), **Inventario** (`InventoryModuleScreen`: **Stock** B1 + **Catálogo** B4–B6 con `SegmentedButton`), **Venta** (POS), **Proveedores** — `IndexedStack`; POS y proveedores siguen como placeholders en `lib/features/shell/`. UX inventario: `docs/UX_INVENTARIO_PRODUCTOS.md`.

### 1.1 Fundaciones de app

- [x] `deviceId`: UUID generado una vez y persistido (`shared_preferences` u otro).
- [x] `appVersion` + `deviceId` para ventas/sync: `PosTerminalInfo.load(LocalPrefs)` (`package_info_plus` + mismo UUID); contrato backend `FRONTEND_INTEGRATION_CONTEXT.md` (§2, §8, §13.9, §13.12) — usar al implementar `POST /sales` y `sync/push`.
- [x] `storeId` configurable (campo / pegar UUID) y guardado en preferencias.
- [x] Constante o `--dart-define` para `API_BASE_URL` (sin barra final duplicada en paths).
- [x] Cliente HTTP central (`dio` o `http`) con:
  - [x] Header `X-Store-Id` en (casi) todas las peticiones a `/api/v1/...`.
  - [x] `Content-Type: application/json` en POST/PATCH.
  - [x] `X-Request-Id` (UUID v4) — generado **automáticamente** en cada petición en `ApiClient` si no se pasa uno explícito; override opcional por parámetro.
  - [x] Parseo de errores `{ statusCode, error, message[], requestId }` y mensaje usable en UI (`ApiError.userMessageForSupport` incluye `requestId` del cuerpo M0 cuando existe).
- [x] Montos enviados al API como **string** decimal (no `double` en JSON) — verificado en producto (`CatalogProduct`), POS (`PosCartLine` + `SaleCheckoutPayload`), ajustes, compras, devoluciones y colas sync.
- [x] Tema Material 3 con primary **#FF6D00** y secundarios según guía (§6 implementación Flutter).

### 1.2 Módulo configuración (empresa / tienda)

- [x] **A1** Pantalla enlazar tienda: campo UUID + guardar + flujo hacia validación.
- [x] **A1b** Crear tienda desde el dispositivo: UUID, nombre, tipo sucursal, monedas, confirmación y tasa inicial opcional; backend con **`STORE_ONBOARDING_ENABLED=1`**, contrato **`docs/BACKEND_STORE_ONBOARDING.md`** + **§13.0** en `FRONTEND_INTEGRATION_CONTEXT.md`, Swagger `/api/docs`.
- [x] **A2** Resumen tienda: `GET /api/v1/stores/{storeId}/business-settings` con `X-Store-Id` = `storeId`; mostrar nombre tienda, moneda funcional, moneda documento por defecto; manejar **404** (sin BusinessSettings / seed).
- [x] **A3** Tasa del día: `GET /api/v1/exchange-rates/latest?baseCurrencyCode=...&quoteCurrencyCode=...` (+ `effectiveOn` opcional); mostrar `rateQuotePerBase`, `effectiveDate`, `convention`; refrescar (`ExchangeRateTodayScreen`).
- [x] **A4** Registrar tasa: `POST /api/v1/exchange-rates` — pantalla `RegisterExchangeRateScreen` (desde Inicio o icono en Tasa del día).

### 1.3 Módulo inventario y productos

- [x] **B1** Lista inventario: `GET /api/v1/inventory`; pull-to-refresh; búsqueda local por nombre/SKU/**barcode**; campo **`minStock`** en modelo + filtros **Todos / Sin stock / Bajo mínimo** (`InventoryStockTab`). `FRONT_INVENTORY_SUPPLIERS_MARGINS_SYNC.md` §2.
- [x] **B2** Detalle stock: `GET /api/v1/inventory/{productId}` (404 → sin ficha aún; se muestra línea de la lista); `GET /api/v1/inventory/movements?productId=&limit=` — pantalla al tocar un ítem en **Stock** (`InventoryProductDetailScreen`).
- [x] **B3** Ajuste stock: `POST /api/v1/inventory/adjustments` — `InventoryAdjustmentScreen` desde detalle B2 (`IN_ADJUST` / `OUT_ADJUST`, `quantity` string, `reason` obligatorio en UI, `unitCostFunctional` solo en entradas, **`opId`** vía `ClientMutationId` — reintento con mismo id; al editar el formulario tras fallo, nuevo `opId`). Payload sync alineado: `InventoryAdjustPayloadBuilder` (`lib/core/sync/inventory_adjust_payload_builder.dart`). **Sin red / cola:** checklist explícita en `docs/CLIENT_IDEMPOTENCY_AND_OFFLINE.md` § “Punto de implementación: guardar sin red en B3”.
- [x] **B4** Lista catálogo: `GET /api/v1/products?includeInactive=false` (opcional `source=auto|mongo|postgres`); cabecera `X-Catalog-Source` en UI debug opcional *(no implementada aún)*.
- [x] **B5** Alta/edición producto: `POST /api/v1/products`, `PATCH /api/v1/products/{id}` — `ProductFormScreen` (sku opcional en alta → backend `SKU-000xxx` si se omite; **barcode** opcional/único; sin copiar barras→SKU salvo botón explícito; PATCH con `barcode: null` para quitar; **`supplierId`** opcional; tras **crear**, diálogo opcional → B3 stock inicial). Contrato: `docs/BACKEND_PRODUCT_SKU_BARCODE.md` + `FRONT_INVENTORY_SUPPLIERS_MARGINS_SYNC.md` §2–3.
- [x] **B6** Desactivar producto: `DELETE /api/v1/products/{id}` (menú del ítem en catálogo; política `PRODUCT_SOFT_DELETE_POLICY`).
- [x] **B7** Inventario + **cámara** (tras o junto a **P1**, mismo paquete de escaneo): (1) botón **Escanear** en **Stock** y **Catálogo** junto al buscador — rellenar filtro por código leído / `product.barcode`; si no hay coincidencia, ofrecir **crear producto** con barcode precargado. (2) En **ProductFormScreen** (alta/edición), **Escanear** junto al campo código de barras para no cargar manual. Ver `docs/UX_INVENTARIO_PRODUCTOS.md` § “Cámara / QR en Inventario”.
- [x] **UX inventario — contador**: texto guía del módulo muestra **N líneas** (Stock) / **N productos** (Catálogo) tras cada carga (`onLoadedCount` en tabs).

### 1.4 Proveedores (REST por tienda)

- [x] **C1** Lista `GET /suppliers` con búsqueda `q`, paginación `nextCursor`, filtro activos / incluir dados de baja — `SuppliersListScreen` + `SuppliersApi`.
- [x] **C2** Alta `POST /suppliers` y edición `PATCH` (campos opcionales, `taxId`, reactivar con `active: true`); baja `DELETE` (soft) — `SupplierFormScreen`.

### 1.5 Criterios de cierre Sprint 1

- [ ] Ningún endpoint inventado; todo alineado a `FRONTEND_INTEGRATION_CONTEXT.md`.
- [x] Errores API: `ApiError.userMessage` + `requestId` en pie vía `userMessageForSupport`; cabecera `X-Request-Id` en cada request para correlación en logs.
- [ ] Documentos de contrato actualizados en repo si el backend cambia (copiar de nuevo a `docs/backend/` si usas esa carpeta).

---

## 2) Sprint 2 — POS (venta en tienda)

### 2.0 UX móvil (referencia diseño)

- [x] Layout tipo **`docs/quickmarket-pos.html`** (bosquejo HTML): tema oscuro en pestaña Venta, barra **QuickMarket** + badge de tasa (`convention` / `source` API + par funcional→documento), buscador fijo con resultados desplegables (nombre/SKU/barcode), carrito como lista principal con precio dual (funcional + documento), **Dismissible** para quitar línea, **numpad** bottom sheet para cantidad decimal, overlay escaneo con línea animada + **Simular escaneo** + **Usar cámara** (`BarcodeScannerScreen`), panel totales dual (documento en **dorado** `#E8C34A`), **Cobrar** con monto inline, limpiar ticket y placeholder descuentos. Implementación: `pos_sale_ui_tokens.dart`, `pos_sale_widgets.dart`, `pos_sale_sheets.dart`, `PosCartLine.quantity` como `String` decimal (`pos_cart_quantity.dart`). **Referencia visual:** `docs/pos_imagen.png` (mock alta fidelidad; alinear detalles de copy/UI con este archivo y con `docs/quickmarket-pos.html`).
- [x] **Menú Ventas** (`SalesModuleScreen` en `MainShell`): al tocar pestaña **Venta** se abre hub (POS / historial / buscar precio); **POS** = `PosSaleScreen` con **atrás** al menú. **Historial** = `TicketHistoryScreen`: pestaña **Este dispositivo** (`recent_sales_v1`, solo día actual local) + **General** (`SalesApi.listSales` → `GET /sales` con `dateFrom`/`dateTo`/opcional `deviceId`, `limit`, `cursor`, respuesta `items`/`nextCursor`/`meta` según `docs/BACKEND_SALES_HISTORY_API.md`); detalle `GET /sales/:id`. Ventas offline en cola como “pendiente”. Consulta precios: `ProductPriceLookupScreen`.
- [x] **Backend listado `GET /sales`:** implementado; app integrada (`SalesListPage`, paginación “Cargar más” con `nextCursor`).

### 2.1 Catálogo y carrito

- [x] **P1** Catálogo venta: lista + pull; búsqueda nombre/SKU/barcode; **`mobile_scanner`** — `BarcodeScannerScreen` + `PosSaleScreen` matchea `product.barcode`; carrito mínimo y “Cobrar” stub (P3). Android/iOS: permiso cámara. **Reutilizar** `BarcodeScannerScreen` en **B7**. *(Flujo principal: búsqueda en barra superior + resultados compactos, no lista full-screen de catálogo.)*
- [x] **P2** Línea carrito: precio en **moneda documento**; referencia funcional→documento con tasa de `GET .../exchange-rates/latest` (directa o inversa); UI en `PosSaleScreen` + `PosCartLine` (`documentUnitPrice`).
- [x] **P3** Ticket: total en moneda documento; al confirmar `POST /api/v1/sales` con `documentCurrencyCode`, `lines[]` (`price`/`quantity` string), `fxSnapshot` canónico (funcional→documento), `deviceId`, `appVersion`, `id` cliente para idempotencia (`ClientMutationId`, mismo valor al reintentar hasta éxito).
- [x] **P4** Selector moneda documento entre `defaultSaleDocCurrency` y moneda funcional cuando difieren (`DropdownButton` en venta); conversión solo catálogo en moneda documento o funcional (sin cruces arbitrarios).

### 2.2 Multi-moneda en POS

- [x] `fxSnapshot` en `POST /sales`: `baseCurrencyCode`, `quoteCurrencyCode`, `rateQuotePerBase`, `effectiveDate` (`YYYY-MM-DD`) vía `SaleCheckoutPayload`; `fxSource` opcional reservado (`POS_OFFLINE` cuando haya flujo offline).
- [x] Ticket abierto: tasa al cargar / al cambiar moneda documento; no se reescribe venta cerrada. JSON sin `double` en montos (`MoneyStringMath` → string).

### 2.3 Offline (opcional en Sprint 2 o inicio Sprint 3)

- **Orden de implementación** y continuidad “reintento en pantalla ↔ cola offline”: `docs/CLIENT_IDEMPOTENCY_AND_OFFLINE.md` (fases 0–7 y checklist de huecos a evitar).
- **Decisión cerrada:** operaciones **desde cola persistente** = **solo** `POST /sync/push` (no drenar cola con REST). Online inmediato puede seguir en REST (B3, P3) hasta optar por cola+flush unificado.
- Patrón **`opId` / reintentos** en cliente: **fase 0** — B3 hecho; **fase 1** — ventas (P3); cola + worker — fases 2–5.
- [x] Cola local: ventas (`pending_sales_v1`) + ajustes stock (`pending_inventory_adjusts_v1`); mismo `opId` que REST en ajustes; ventas con `fxSource: POS_OFFLINE` al encolar.
- [x] `POST /api/v1/sync/push` vía `SyncApi` + `flushPendingSyncOpsForStore` (≤200 ops, orden por timestamp): `SALE` + `INVENTORY_ADJUST`; `lastServerVersion` = watermark real post-`pull` (`sync_pull_since_v1`).
- [x] `acked`/`skipped` sacan de ambas colas; `MainShell` al iniciar: `runSyncCycle` (pull + flush). Venta: **Sincronizar** = pull+flush. B3 sin red → cola + `sync/push` (no REST desde cola).

---

## 3) Sprint 3+ — Compras, devoluciones, sync completo

### 3.1 Compras / recepción

- [x] `POST /api/v1/purchases` con `supplierId`, `documentCurrencyCode`, `lines[]`, `fxSnapshot` — `PurchasesApi` + `PurchaseReceiveScreen` (Proveedores → recepción); sin red → cola `PURCHASE_RECEIVE` + `sync/push`.
- [x] `GET /api/v1/purchases/{id}` — `PurchasesApi.getPurchase` *(pantalla de detalle dedicada pendiente si se desea)*.
- [x] Proveedor: `supplierId` de `GET/POST /suppliers` de la misma tienda y activo; 400 si inactivo en `POST /purchases` — mensaje en UI. Ver `docs/BACKEND_SUPPLIERS_API_PROPOSAL.md`.

### 3.2 Devoluciones de venta

- [x] `POST /api/v1/sale-returns` con `originalSaleId`, `lines[]` (`saleLineId`, `quantity` string), opcional `fxPolicy` (`INHERIT_ORIGINAL_SALE` | `SPOT_ON_RETURN`), `fxSnapshot` si `SPOT_ON_RETURN` — `SaleReturnsApi` + `SaleReturnScreen` (Ventas → devolución); carga `GET /sales/:id` para líneas; sin red → cola `pending_sale_return_v1` + `sync/push`.
- [x] `GET /api/v1/sale-returns/{id}` — `SaleReturnsApi.getSaleReturn` *(UI detalle opcional)*.
- [x] Sync: `SALE_RETURN` en `flushPendingSyncOpsForStore` (`payload.saleReturn`) según `RETURNS_POLICY.md` / `SYNC_CONTRACTS.md`.

### 3.3 Sync offline completo

- Cola offline / rehidratación: **solo** `sync/push` — `docs/CLIENT_IDEMPOTENCY_AND_OFFLINE.md` (decisión de arquitectura cerrada).
- [x] `POST /api/v1/sync/push`: batch ≤200 ops; `deviceId`; `opId` por op; `acked` / `skipped` / errores vía `SyncFlushResult` (ops `failed` siguen en cola).
- [x] Ops desde app: hecho `SALE` + `INVENTORY_ADJUST` + **`PURCHASE_RECEIVE`** + **`SALE_RETURN`** en cola (`flushPendingSyncOpsForStore`). `NOOP` directo: `submitSyncNoop` (`lib/core/sync/sync_noop.dart`) sin cola.
- [x] `GET /api/v1/sync/pull`: `pullSyncAdvanceWatermark` — bucle `hasMore`, guarda `toVersion` en `sync_pull_since_v1`.
- [x] Watermark pull ≠ `acked.serverVersion` del push: solo se usa el primero en `lastServerVersion` del body de push (`LocalPrefs.getSyncPullLastVersion`).
- [x] Pull `PRODUCT_*`: `summarizePullOpsProductChanges` + `CatalogInvalidationBus` → refetch REST en **Venta**, **Stock** y **Catálogo** (invalidación agresiva; sin SQLite). Ver `lib/core/catalog/catalog_invalidation_bus.dart`.

### 3.4 Lectura catálogo / Mongo (referencia)

- [x] Criterio app: **no** se recalculan ventas cerradas con la tasa del día; listados de catálogo/stock vienen de REST y pueden eventualmente diferir de Postgres si el backend usa lectura Mongo (`MONGO_PRODUCTS_READ.md` — lectura obligatoria para equipo).

---

## 4) Integración y calidad (transversal)

- [ ] Checklist §7 `FRONTEND_INTEGRATION_CONTEXT.md`: selector moneda documento, pantalla tasa, ticket dual, offline FX en SQLite si aplica.
- [ ] Multi-dispositivo misma tienda: mismo `X-Store-Id`, distintos `deviceId` por instalación.
- [ ] No usar `GET /api/v1/ops/metrics` en la app POS salvo necesidad operativa y credenciales correctas.
- [ ] Pruebas manuales o `flutter test` en flujos críticos (cliente API mockeado si aplica).

---

## M7 — Márgenes y endpoint compuesto (solo planificación en app)

Seguimiento de **backend** en tracker del repo Nest; cuando existan endpoints, añadir tareas aquí.

- [ ] **M7-P1–P4** Settings / producto: `defaultMarginPercent`, `pricingMode`, overrides — modelo + UI según `FRONTEND_INTEGRATION_CONTEXT` actualizado.
- [ ] **M7-P5** `POST /api/v1/products-with-stock` — sustituir o complementar flujo dos llamadas en alta de producto.
- [ ] **M7-P6–P7** Post-compra / proyección Mongo — solo si la app consume esos campos en listados.

---

## Referencias rápidas

| Tema | Archivo |
|------|---------|
| UX Stock vs catálogo + `getJsonList` + cámara/contador (B7) | `docs/UX_INVENTARIO_PRODUCTOS.md` |
| Inventario, proveedores, márgenes, fases M7 | `docs/FRONT_INVENTORY_SUPPLIERS_MARGINS_SYNC.md` |
| Proveedores API | `docs/BACKEND_SUPPLIERS_API_PROPOSAL.md` |
| SKU / barcode | `docs/BACKEND_PRODUCT_SKU_BARCODE.md` |
| Índice copia docs backend → Flutter | `docs/DOCUMENTOS_A_COPIAR_AL_PROYECTO_FLUTTER.md` |
| Idempotencia cliente (`opId`) y offline futuro | `docs/CLIENT_IDEMPOTENCY_AND_OFFLINE.md` (§ checklist B3 sin red + `InventoryAdjustPayloadBuilder`) |
| API + JSON por pantalla + FX | `docs/FRONTEND_INTEGRATION_CONTEXT.md` |
| Sprints, pantallas, paquetes, UI | `IMPLEMENTACION_FLUTTER_ANDROID_GEMINI.md` |
| Índice docs → Flutter | `DOCUMENTOS_A_COPIAR_AL_PROYECTO_FLUTTER.md` |
| Sync push/pull | `SYNC_CONTRACTS.md` |
| Multi-moneda dominio | `MULTI_CURRENCY_ARCHITECTURE.md` |
| Devoluciones | `RETURNS_POLICY.md` |
| Mongo catálogo | `MONGO_PRODUCTS_READ.md` |
| Soft delete productos | `PRODUCT_SOFT_DELETE_POLICY.md` |
| Postman | `QuickMarket_API.postman_collection.json` |

---

*Última organización del checklist según documentación del repositorio. Actualizar filas si el backend añade endpoints o cambia contratos.*
