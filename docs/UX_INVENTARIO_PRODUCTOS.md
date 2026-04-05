# UX — Inventario: Stock vs catálogo

## Roles en la app

| Área | Qué muestra / hace | Endpoints (referencia) |
|------|--------------------|-------------------------|
| **Stock** (B1) | Cantidades disponibles por producto (líneas de inventario). | `GET /api/v1/inventory` |
| **Detalle stock** (B2) | Al tocar una fila en Stock: cantidad, reservado, costos si vienen, últimos movimientos. | `GET /api/v1/inventory/{productId}`, `GET /api/v1/inventory/movements?productId=&limit=` |
| **Ajuste stock** (B3) | `InventoryAdjustPayloadBuilder`: REST (`toRestBody`) + payload sync (`toSyncPayload`). Cola offline: § “guardar sin red” en `CLIENT_IDEMPOTENCY_AND_OFFLINE.md`. | REST + `sync/push` |
| **Catálogo** (B4) | Fichas de producto: nombre, SKU, precio, moneda, costo, código de barras, etc. | `GET /api/v1/products` |
| **Formulario** (B5) | Crear o editar una ficha desde el catálogo. | `POST /api/v1/products`, `PATCH /api/v1/products/{id}` |
| **Desactivar** (B6) | Soft delete desde el menú del ítem. | `DELETE /api/v1/products/{id}` |

Stock responde a “¿cuánto hay?”. El catálogo responde a “¿qué vendemos y a qué precio / con qué SKU y barcode?”.

## Navegación implementada

En la pestaña inferior **Inventario**, un **SegmentedButton** arriba del contenido:

- **Stock** — lista con búsqueda y pull-to-refresh (`InventoryStockTab`); **tocar un producto** abre detalle B2 (`InventoryProductDetailScreen`); desde ahí **Ajustar stock** → B3 (`InventoryAdjustmentScreen`).
- **Catálogo** — lista con búsqueda; tocar un producto o **⋮ → Editar** abre el formulario; **FAB “Nuevo producto”** abre el mismo formulario en modo alta (`ProductCatalogTab` + `ProductFormScreen`).

Alternativas descartadas en esta iteración (válidas si más adelante se prefiere): botón que navega a otra ruta solo para catálogo, o FAB global en el `Scaffold` del módulo en lugar del FAB dentro del tab Catálogo.

## Código de barras (B5 / P1)

Para venta con cámara en Sprint 2 conviene barcode cargado. El formulario exige barcode **salvo** que el usuario active **“Permitir sin código de barras”** (venta solo por búsqueda manual).

---

## Contador (líneas / productos)

Tras cada carga de API, el texto bajo **Stock | Catálogo** añade **· N líneas** o **· N productos** (total de la lista, no del filtro de búsqueda). Implementado vía `onLoadedCount` en `InventoryStockTab` y `ProductCatalogTab`.

---

## Cámara / QR en Inventario (pendiente — diseño acordado)

Tiene sentido **sí**: escanear acelera mucho el trabajo en depósito y en alta de productos. No reemplaza al 100 % el teclado (nombre, precio, etc. siguen editables), pero evita errores al tipear códigos largos.

### 1) Buscar con cámara (Stock y Catálogo)

- Un botón **Escanear** junto al campo de búsqueda abre la cámara (mismo stack que **P1** Venta: p. ej. `mobile_scanner` / ML Kit).
- El valor leído (EAN/QR que resuelva a **texto**) se usa como **filtro**: equivalente a pegar el código en el buscador actual (ya filtra por `barcode` / SKU / nombre).
- Si el código **no existe** en catálogo: mensaje claro *“No hay producto con este código”* y atajo *“Crear producto con este código de barras”* → abre `ProductFormScreen` con el campo **código de barras** ya rellenado.

### 2) Alta de producto con cámara (`ProductFormScreen`)

- Botón **Escanear** al lado del campo **Código de barras**: rellena solo ese campo; el usuario completa nombre, SKU, precio, etc.
- Es el flujo **correcto y habitual** en retail (rápido y alineado con B5/P1).
- Antes de **Guardar**, conviene comprobar **duplicado de barcode** en lista local o dejar que el API devuelva error de unicidad y mostrarlo.

### Relación con Venta (P1)

- **Un solo componente/servicio de escaneo** reutilizable: Inventario (buscar + formulario) y POS (añadir al carrito) comparten lectura y normalización del string leído.

Implementación: ver checklist **B7** en `docs/DESARROLLO_CHECKLIST.md`. Escáner compartido: `lib/features/sale/barcode_scanner_screen.dart` (ya usado en **Venta** P1).

## `ApiClient.getJsonList` y formas de respuesta

Algunos `GET` devuelven un **array** en la raíz; otros un **objeto** con la lista anidada. `getJsonList` acepta:

1. Raíz: `List` de objetos.
2. Raíz: `Map` con una de estas claves apuntando a un `List` de objetos: `data`, `items`, `results`, **`lines`**.

Para **`GET /api/v1/inventory/movements`**, el API Nest Quick Market devuelve **array en la raíz** sin envelope (`§13.8.1` en `FRONTEND_INTEGRATION_CONTEXT.md`). `getJsonList` parsea ese caso como `List` directo.

Si el backend usa **otra** clave (por ejemplo solo `{ "products": [...] }`), hay que **añadir esa clave** al bucle en `lib/core/api/api_client.dart` **o** pegar aquí un ejemplo JSON real del endpoint y alinear el cliente.

No hace falta tener el backend en este repo para documentar: cuando tengas una respuesta real de `GET /inventory` o `GET /products`, compárala con la lista anterior y extiende `getJsonList` si falta alguna variante.
