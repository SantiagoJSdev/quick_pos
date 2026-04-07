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
3. Cobro: `POST /sales`.
4. Si no hay red, venta a cola local y luego `sync/push`.

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
- Pull invalida catalogo y refresca pantallas.

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

- Mantener **solo este archivo** como fuente de verdad en `docs/`.
- Evitar crear docs paralelos; todo nuevo contexto va aqui.
- Si se necesita detalle tecnico temporal, incorporarlo y resumirlo aqui antes de cerrar la tarea.
