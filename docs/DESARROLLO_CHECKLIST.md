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

### 1.1 Fundaciones de app

- [x] `deviceId`: UUID generado una vez y persistido (`shared_preferences` u otro).
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
- [ ] **A3** Tasa del día: `GET /api/v1/exchange-rates/latest?baseCurrencyCode=...&quoteCurrencyCode=...` (+ `effectiveOn` opcional); mostrar `rateQuotePerBase`, `effectiveDate`, `convention`; refrescar.
- [ ] **A4** (Opcional) Registrar tasa: `POST /api/v1/exchange-rates` para admin en campo.

### 1.3 Módulo inventario y productos

- [ ] **B1** Lista inventario: `GET /api/v1/inventory`; pull-to-refresh; búsqueda local por nombre/SKU sobre datos cargados.
- [ ] **B2** Detalle stock: `GET /api/v1/inventory/{productId}`; `GET /api/v1/inventory/movements?productId=&limit=`.
- [ ] **B3** Ajuste stock: `POST /api/v1/inventory/adjustments` (`IN_ADJUST` / `OUT_ADJUST`, `quantity` string, `reason`, `unitCostFunctional` si aplica, `opId` opcional para idempotencia).
- [ ] **B4** Lista catálogo: `GET /api/v1/products?includeInactive=false` (opcional `source=auto|mongo|postgres`); leer cabecera `X-Catalog-Source` si se muestra en debug.
- [ ] **B5** Alta/edición producto: `POST /api/v1/products`, `PATCH /api/v1/products/{id}` alineados al DTO (sku, name, price, currency, cost, barcode, type, etc.).
- [ ] **B6** Desactivar producto: `DELETE /api/v1/products/{id}` (soft delete; política `PRODUCT_SOFT_DELETE_POLICY`).

### 1.4 Proveedores (sin API)

- [ ] **C1** Lista proveedores **solo local** (SharedPreferences JSON o SQLite): nombre + UUID.
- [ ] **C2** Añadir/editar proveedor local: pegar UUID (seed / Postman / admin); texto de ayuda de que compras usarán ese UUID en sprint posterior.

### 1.5 Criterios de cierre Sprint 1

- [ ] Ningún endpoint inventado; todo alineado a `FRONTEND_INTEGRATION_CONTEXT.md`.
- [ ] Errores API muestran `message` y se puede copiar o ver `requestId` para soporte.
- [ ] Documentos de contrato actualizados en repo si el backend cambia (copiar de nuevo a `docs/backend/` si usas esa carpeta).

---

## 2) Sprint 2 — POS (venta en tienda)

### 2.1 Catálogo y carrito

- [ ] **P1** Catálogo venta: grid/lista; búsqueda nombre/SKU; escaneo QR/código (paquete tipo `mobile_scanner` o ML Kit) resolviendo `productId` vía catálogo en memoria/cache.
- [ ] **P2** Línea carrito: precio en **moneda documento**; referencia VES/funcional con tasa de `GET .../exchange-rates/latest` (solo UI hasta confirmar).
- [ ] **P3** Ticket: subtotales/totales en moneda documento; línea referencia en VES (o según settings); al confirmar `POST /api/v1/sales` con `documentCurrencyCode`, `lines[]`, `fxSnapshot`, `deviceId`.
- [ ] **P4** Selector moneda documento coherente con `defaultSaleDocCurrency` y pares existentes en backend (sin asumir cruces no soportados — ver tabla FX en contexto §14).

### 2.2 Multi-moneda en POS

- [ ] `fxSnapshot`: `baseCurrencyCode`, `quoteCurrencyCode`, `rateQuotePerBase`, `effectiveDate` (`YYYY-MM-DD`), `fxSource` opcional (`POS_OFFLINE` solo cuando aplique offline).
- [ ] No recalcular ticket ya cerrado con tasa nueva; no usar `double` para dinero.

### 2.3 Offline (opcional en Sprint 2 o inicio Sprint 3)

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
