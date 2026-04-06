# Sincronización Front ↔ Backend — Inventario, proveedores y márgenes

Documento único para el equipo **Flutter (quick_pos)** tras revisar:

- `quickmarket_backend_proveedores_inventario_margenes.pdf`
- `quickmarket_front_ux_proveedores_inventario.pdf`

y el estado real del API Nest en este repo. Sustituye o complementa copias sueltas de esos PDFs: aquí están **nombres de API**, **qué ya existe** y **qué vendrá por fases** (ver `docs/IMPLEMENTATION_TRACKER.md` sección **M7**).

---

## 1) Principios (sin cambiar el modelo mental)

| Concepto | Backend | UX (PDF front) |
|----------|---------|----------------|
| Producto / catálogo | `Product` | Pantalla **Productos** — “qué vendemos” |
| Existencias | `InventoryItem` | Pantalla **Existencias** — cantidad actual |
| Movimientos | `StockMovement` | Pantalla **Movimientos** — trazabilidad |
| Proveedores | `Supplier` + `storeId` | Pantalla **Proveedores** |
| Compras | `Purchase` | Recepción / “Comprar” |

**No** fusionar entidades en el servidor: el PDF de backend pide **flujo compuesto** (una llamada o dos) para que el usuario **sienta** un solo asistente, no un solo modelo de datos.

---

## 2) Ya implementado hoy (podéis integrar ya)

| Necesidad UX | API / comportamiento |
|--------------|----------------------|
| CRUD proveedores por tienda | `GET/POST/PATCH/DELETE /api/v1/suppliers` (ver `docs/BACKEND_SUPPLIERS_API_PROPOSAL.md`). **DELETE** = soft (`active: false`). |
| Identificador fiscal en JSON | Campo **`taxId`** (no `rif`; en BD la columna legada sigue siendo `rif`). |
| `POST /purchases` con proveedor | `supplierId` debe ser de la **misma tienda** (`X-Store-Id`) y proveedor **activo**. |
| SKU vs barcode | `POST /products`: `sku` opcional (autogenerado `SKU-000001`…); `barcode` opcional único si informado. **No** copiar barcode → SKU sin confirmación del usuario. Ver `docs/BACKEND_PRODUCT_SKU_BARCODE.md`. |
| Proveedor principal en ficha producto | `Product.supplierId` ya existe en schema; enviarlo en create/update si la UI lo tiene. |
| Lista / ajuste / historial stock | `GET /inventory`, `GET /inventory/:productId`, `GET /inventory/movements`, `POST /inventory/adjustments`. |
| Filtros “bajo stock” / “sin stock” | Derivables en cliente: `GET /inventory` trae `quantity`, `reserved`, **`minStock`**. Ej.: sin stock → `quantity <= 0`; bajo stock → `quantity > 0` y `quantity <= minStock` (ajustar regla en UI si queréis buffer). |
| Histórico ventas | `GET /api/v1/sales` con filtros y paginación — `docs/BACKEND_SALES_HISTORY_API.md`. |

---

## 3) Ajustes al PDF de UX (para no desalinearos)

1. **RIF / fiscal:** en API usar siempre **`taxId`** en JSON (el PDF dice “taxId o RIF” en lista de proveedores — mapear a `taxId`).
2. **Alta “un solo flujo” con stock inicial:** hasta que exista **`POST /api/v1/products-with-stock`** (plan M7), el front debe hacer **dos llamadas** en secuencia (mismo flujo que hoy):  
   `POST /products` → `POST /inventory/adjustments` (`IN_ADJUST`, `quantity`, `unitCostFunctional` si aplica, `reason`: “Inventario inicial”). Idempotencia: `opId` en el ajuste si usáis sync después.
3. **Navegación “Productos / Existencias / Movimientos / Proveedores”:** es solo **copy y rutas Flutter**; el backend no expone un menú.
4. **Márgenes:** `defaultMarginPercent`, `pricingMode`, `marginPercentOverride`, `effectiveMarginPercent` / precio sugerido **aún no están en el API** — ver fase M7 en el tracker. La UI puede mostrar calculadora **local** con margen tecleado hasta que el servidor persista reglas.

---

## 4) Lo que hará el backend (por fases — M7)

Resumen alineado al PDF de backend; detalle y checkboxes en **`IMPLEMENTATION_TRACKER.md`**.

| Fase | Contenido |
|------|-----------|
| **P1** | `BusinessSettings.defaultMarginPercent` (opcional, %). |
| **P2** | `Product.pricingMode` (`USE_STORE_DEFAULT` \| `USE_PRODUCT_OVERRIDE` \| `MANUAL_PRICE`) + `marginPercentOverride` opcional. |
| **P3** | Respuestas de producto enriquecidas: `effectiveMarginPercent`, y si aplica `suggestedPrice` / `marginComputedPercent` (solo informativo; `MANUAL_PRICE` no sobrescribe `price` en servidor sin decisión explícita). |
| **P4** | `PATCH` (o ampliación) de **business-settings** para editar margen global de tienda (además de monedas existentes). |
| **P5** | **`POST /api/v1/products-with-stock`**: una transacción — crear producto (outbox igual que hoy) + `IN_ADJUST` stock inicial; respuesta `{ product, inventory }`. |
| **P6** | Tras **compra** (`IN_PURCHASE`): política documentada para **sugerir** nuevo precio según `pricingMode` (MVP: sin cambiar `price` en silencio si `MANUAL_PRICE`). |
| **P7** | Proyección **Mongo `products_read`** + payload outbox/sync con los nuevos campos para no depender siempre de Postgres en listado. |

---

## 5) Contratos sugeridos (cuando M7 esté listo)

### Business settings (ampliación)

```json
{
  "defaultMarginPercent": "15.00"
}
```

### Product (create / response — borrador)

```json
{
  "pricingMode": "USE_STORE_DEFAULT",
  "marginPercentOverride": null,
  "supplierId": "uuid-opcional"
}
```

Respuesta puede incluir:

```json
{
  "effectiveMarginPercent": "15.00",
  "marginComputedPercent": "12.50"
}
```

(Valores exactos y reglas de redondeo se fijarán en la implementación y en `FRONTEND_INTEGRATION_CONTEXT.md`.)

### Products + stock (futuro)

`POST /api/v1/products-with-stock` con cuerpo tipo el PDF backend; respuesta `{ "product": {...}, "inventory": { "status": "applied", "quantity": "24" } }`.

---

## 6) Documentos a copiar al repo Flutter

| Origen (backend) | Uso en app |
|------------------|------------|
| Este archivo | Contrato y fases |
| `docs/BACKEND_SUPPLIERS_API_PROPOSAL.md` | Proveedores |
| `docs/BACKEND_PRODUCT_SKU_BARCODE.md` | SKU / barcode |
| `docs/BACKEND_SALES_HISTORY_API.md` | Historial ventas |
| `docs/FRONTEND_INTEGRATION_CONTEXT.md` | Contexto general API |

---

## 7) Resumen una línea para el equipo mobile

**Hoy:** integrad proveedores REST, inventario, productos con SKU autogénico y `taxId`; stock inicial = 2 llamadas hasta el endpoint compuesto. **Próximo:** márgenes y `products-with-stock` llegan en **M7** por pasos; seguid el tracker y este doc.
