# Checklist de desarrollo — Quick POS (Flutter)

Seguimiento del avance frente a la documentación del backend (`FRONTEND_INTEGRATION_CONTEXT.md`, `IMPLEMENTACION_FLUTTER_ANDROID_GEMINI.md`, `SYNC_CONTRACTS.md`, `MULTI_CURRENCY_ARCHITECTURE.md`, políticas API). Puedes marcar `[x]` tú a mano; en sesiones con Cursor el asistente puede ir actualizando las casillas en este archivo al dar por cerrada cada tarea (con commit en el repo).

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

- `localhost` del PC = `http://10.0.2.2:<puerto>` desde el emulador (ej. backend en `3000` → `http://10.0.2.2:3000`).
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

## 1) Sprint 1 — Configuración tienda, tasas, inventario, productos, proveedores locales

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
  - [x] Opcional `X-Request-Id` (UUID o string ≤128) — soportado en `ApiClient`; aún no se genera automático en pantallas.
  - [x] Parseo de errores `{ statusCode, error, message[], requestId }` y mensaje usable en UI.
- [ ] Montos enviados al API como **string** decimal (no `double` en JSON) *(pendiente: formularios venta/producto)*.
- [x] Tema Material 3 con primary **#FF6D00** y secundarios según guía (§6 implementación Flutter).

### 1.2 Módulo configuración (empresa / tienda)

- [x] **A1** Pantalla enlazar tienda: campo UUID + guardar + flujo hacia validación.
- [x] **A1b** Crear tienda desde el dispositivo: UUID, nombre, tipo sucursal, monedas, confirmación y tasa inicial opcional; backend con **`STORE_ONBOARDING_ENABLED=1`**, contrato **`docs/BACKEND_STORE_ONBOARDING.md`** + **§13.0** en `FRONTEND_INTEGRATION_CONTEXT.md`, Swagger `/api/docs`.
- [x] **A2** Resumen tienda: `GET /api/v1/stores/{storeId}/business-settings` con `X-Store-Id` = `storeId`; mostrar nombre tienda, moneda funcional, moneda documento por defecto; manejar **404** (sin BusinessSettings / seed).
- [x] **A3** Tasa del día: `GET /api/v1/exchange-rates/latest?baseCurrencyCode=...&quoteCurrencyCode=...` (+ `effectiveOn` opcional); mostrar `rateQuotePerBase`, `effectiveDate`, `convention`; refrescar (`ExchangeRateTodayScreen`).
- [x] **A4** Registrar tasa: `POST /api/v1/exchange-rates` — pantalla `RegisterExchangeRateScreen` (desde Inicio o icono en Tasa del día).

### 1.3 Módulo inventario y productos

- [x] **B1** Lista inventario: `GET /api/v1/inventory`; pull-to-refresh; búsqueda local por nombre/SKU/**barcode** (`InventoryStockTab` dentro de `InventoryModuleScreen`).
- [x] **B2** Detalle stock: `GET /api/v1/inventory/{productId}` (404 → sin ficha aún; se muestra línea de la lista); `GET /api/v1/inventory/movements?productId=&limit=` — pantalla al tocar un ítem en **Stock** (`InventoryProductDetailScreen`).
- [x] **B3** Ajuste stock: `POST /api/v1/inventory/adjustments` — `InventoryAdjustmentScreen` desde detalle B2 (`IN_ADJUST` / `OUT_ADJUST`, `quantity` string, `reason` obligatorio en UI, `unitCostFunctional` solo en entradas, **`opId`** vía `ClientMutationId` — reintento con mismo id; al editar el formulario tras fallo, nuevo `opId`). Payload sync alineado: `InventoryAdjustPayloadBuilder` (`lib/core/sync/inventory_adjust_payload_builder.dart`). **Sin red / cola:** checklist explícita en `docs/CLIENT_IDEMPOTENCY_AND_OFFLINE.md` § “Punto de implementación: guardar sin red en B3”.
- [x] **B4** Lista catálogo: `GET /api/v1/products?includeInactive=false` (opcional `source=auto|mongo|postgres`); cabecera `X-Catalog-Source` en UI debug opcional *(no implementada aún)*.
- [x] **B5** Alta/edición producto: `POST /api/v1/products`, `PATCH /api/v1/products/{id}` — `ProductFormScreen` (sku, name, price, currency, cost, type, unit, description; **barcode** con switch “Permitir sin código de barras” para excepción solo-teclado; montos como **string** en JSON).
- [x] **B6** Desactivar producto: `DELETE /api/v1/products/{id}` (menú del ítem en catálogo; política `PRODUCT_SOFT_DELETE_POLICY`).
- [ ] **B7** Inventario + **cámara** (tras o junto a **P1**, mismo paquete de escaneo): (1) botón **Escanear** en **Stock** y **Catálogo** junto al buscador — rellenar filtro por código leído / `product.barcode`; si no hay coincidencia, ofrecir **crear producto** con barcode precargado. (2) En **ProductFormScreen** (alta/edición), **Escanear** junto al campo código de barras para no cargar manual. Ver `docs/UX_INVENTARIO_PRODUCTOS.md` § “Cámara / QR en Inventario”.
- [x] **UX inventario — contador**: texto guía del módulo muestra **N líneas** (Stock) / **N productos** (Catálogo) tras cada carga (`onLoadedCount` en tabs).

### 1.4 Proveedores (sin API)

- [x] **C1** Lista proveedores **solo local** (`LocalPrefs` JSON `local_suppliers_v1`): nombre + UUID — `SuppliersListScreen`.
- [x] **C2** Añadir/editar proveedor local: `SupplierFormScreen` (UUID formato estándar, pegar desde seed/Postman); ayuda de compras futuras; quitar de lista desde menú.

### 1.5 Criterios de cierre Sprint 1

- [ ] Ningún endpoint inventado; todo alineado a `FRONTEND_INTEGRATION_CONTEXT.md`.
- [ ] Errores API muestran `message` y se puede copiar o ver `requestId` para soporte.
- [ ] Documentos de contrato actualizados en repo si el backend cambia (copiar de nuevo a `docs/backend/` si usas esa carpeta).

---

## 2) Sprint 2 — POS (venta en tienda)

### 2.1 Catálogo y carrito

- [x] **P1** Catálogo venta: lista + pull; búsqueda nombre/SKU/barcode; **`mobile_scanner`** — `BarcodeScannerScreen` + `PosSaleScreen` matchea `product.barcode`; carrito mínimo y “Cobrar” stub (P3). Android/iOS: permiso cámara. **Reutilizar** `BarcodeScannerScreen` en **B7**.
- [ ] **P2** Línea carrito: precio en **moneda documento**; referencia VES/funcional con tasa de `GET .../exchange-rates/latest` (solo UI hasta confirmar).
- [ ] **P3** Ticket: subtotales/totales en moneda documento; línea referencia en VES (o según settings); al confirmar `POST /api/v1/sales` con `documentCurrencyCode`, `lines[]`, `fxSnapshot`, `deviceId`.
- [ ] **P4** Selector moneda documento coherente con `defaultSaleDocCurrency` y pares existentes en backend (sin asumir cruces no soportados — ver tabla FX en contexto §14).

### 2.2 Multi-moneda en POS

- [ ] `fxSnapshot`: `baseCurrencyCode`, `quoteCurrencyCode`, `rateQuotePerBase`, `effectiveDate` (`YYYY-MM-DD`), `fxSource` opcional (`POS_OFFLINE` solo cuando aplique offline).
- [ ] No recalcular ticket ya cerrado con tasa nueva; no usar `double` para dinero.

### 2.3 Offline (opcional en Sprint 2 o inicio Sprint 3)

- **Orden de implementación** y continuidad “reintento en pantalla ↔ cola offline”: `docs/CLIENT_IDEMPOTENCY_AND_OFFLINE.md` (fases 0–7 y checklist de huecos a evitar).
- **Decisión cerrada:** operaciones **desde cola persistente** = **solo** `POST /sync/push` (no drenar cola con REST). Online inmediato puede seguir en REST (B3, P3) hasta optar por cola+flush unificado.
- Patrón **`opId` / reintentos** en cliente: **fase 0** — B3 hecho; **fase 1** — ventas (P3); cola + worker — fases 2–5.
- [ ] Cola local de ventas pendientes con misma forma FX que REST.
- [ ] `POST /api/v1/sync/push` con `opType: SALE` y `payload.sale` según `SYNC_CONTRACTS.md`.
- [ ] Reintentos: mismo `opId` → `skipped` sin duplicar stock; misma `sale.id` ya persistida → idempotente.

---

## 3) Sprint 3+ — Compras, devoluciones, sync completo

### 3.1 Compras / recepción

- [ ] `POST /api/v1/purchases` con `supplierId`, `documentCurrencyCode`, `lines[]`, `fxSnapshot`; `GET /api/v1/purchases/{id}`.
- [ ] Proveedor: UUID válido (seed o lista local); no asumir `GET /suppliers` hasta que exista.

### 3.2 Devoluciones de venta

- [ ] `POST /api/v1/sale-returns` con `originalSaleId`, `lines[]` (`saleLineId`, `quantity` string), opcional `fxPolicy` (`INHERIT_ORIGINAL_SALE` | `SPOT_ON_RETURN`), `fxSnapshot` si `SPOT_ON_RETURN`.
- [ ] `GET /api/v1/sale-returns/{id}`.
- [ ] Sync: `SALE_RETURN` en `sync/push` según `RETURNS_POLICY.md` y `SYNC_CONTRACTS.md`.

### 3.3 Sync offline completo

- Cola offline / rehidratación: **solo** `sync/push` — `docs/CLIENT_IDEMPOTENCY_AND_OFFLINE.md` (decisión de arquitectura cerrada).
- [ ] `POST /api/v1/sync/push`: batch ≤200 ops; `deviceId` obligatorio; `opId` UUID v4 por op; manejar `acked` / `skipped` / `failed`.
- [ ] Ops: `INVENTORY_ADJUST`, `PURCHASE_RECEIVE`, `SALE`, `SALE_RETURN`, `NOOP` (pruebas).
- [ ] `GET /api/v1/sync/pull?since=&limit=`: aplicar ops en orden; guardar `toVersion` como siguiente `since`; `hasMore` en bucle.
- [ ] **Importante:** `serverVersion` del **pull** (log global) es distinto del `serverVersion` en `acked` del **push** (por tienda) — llevar watermarks separados si hace falta.
- [ ] Pull: `PRODUCT_CREATED` | `PRODUCT_UPDATED` | `PRODUCT_DEACTIVATED` → actualizar catálogo local; productos desactivados no vendibles (`PRODUCT_SOFT_DELETE_POLICY`).

### 3.4 Lectura catálogo / Mongo (referencia)

- [ ] Entender eventual consistency `products_read` vs Postgres (`MONGO_PRODUCTS_READ.md`); no reinterpretar ventas cerradas con tasa del día.

---

## 4) Integración y calidad (transversal)

- [ ] Checklist §7 `FRONTEND_INTEGRATION_CONTEXT.md`: selector moneda documento, pantalla tasa, ticket dual, offline FX en SQLite si aplica.
- [ ] Multi-dispositivo misma tienda: mismo `X-Store-Id`, distintos `deviceId` por instalación.
- [ ] No usar `GET /api/v1/ops/metrics` en la app POS salvo necesidad operativa y credenciales correctas.
- [ ] Pruebas manuales o `flutter test` en flujos críticos (cliente API mockeado si aplica).

---

## Referencias rápidas

| Tema | Archivo |
|------|---------|
| UX Stock vs catálogo + `getJsonList` + cámara/contador (B7) | `docs/UX_INVENTARIO_PRODUCTOS.md` |
| Idempotencia cliente (`opId`) y offline futuro | `docs/CLIENT_IDEMPOTENCY_AND_OFFLINE.md` (§ checklist B3 sin red + `InventoryAdjustPayloadBuilder`) |
| API + JSON por pantalla + FX | `FRONTEND_INTEGRATION_CONTEXT.md` |
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
