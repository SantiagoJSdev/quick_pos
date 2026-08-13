# Capital operativo, SQL y estadísticas del dashboard — borrador Front

Documento **vivo** para definir juntos qué KPIs / consultas SQL sumamos al **dashboard operativo** y cómo se relacionan con facturas de proveedor, inventario y merma.

> Estado: **propuesta / selección pendiente**. No es contrato de API todavía.  
> Relacionado: [`FACTURA_PROVEEDOR_DEUDA_E_INVENTARIO_FRONTEND.md`](./FACTURA_PROVEEDOR_DEUDA_E_INVENTARIO_FRONTEND.md), dashboard actual (`lib/features/dashboard/`).

---

## 1. Objetivo de negocio

Poder ver, en moneda funcional (ej. USD), si el negocio:

- **mantiene el capital** (solo se “saca” la ganancia),
- **crece** (capital de trabajo sube),
- o **se erosiona** (caja/stock no cubren deuda + reposición).

Preguntas que debe responder el módulo (hoy o en fases):

| # | Pregunta | Dependencia |
|---|----------|-------------|
| A | ¿Cuánto debo a proveedores? | Facturas CREDIT/PARTIAL (`payables`) |
| B | ¿Cuánto tengo en inventario a costo? | `InventoryItem` + costo |
| C | ¿Cuánto vendí / gané hoy? | Ventas − COGS (− devoluciones) |
| D | ¿Cuánta merma / ajuste negativo hubo hoy? | Movimientos `ADJUST` / motivos |
| E | **KPI pedido:** inventario + ventas − ganancia − deuda − merma → “¿el capital se sostiene?” | A–D juntos |

---

## 2. Ecuación base (capital de trabajo diario)

Moneda **funcional** de la tienda:

```text
Inventario_a_costo     = Σ qty × costo_unitario_funcional
Deuda_proveedores      = Σ amountDueFunctional (CREDIT | PARTIAL, saldo > 0)
Caja_estimada          = (opcional) cierre de caja / efectivo contado del turno
                         — si no hay apertura de fondo, usar proxy o omitir en v1

Activos_operativos     ≈ Inventario_a_costo + Caja_estimada
Pasivos_operativos     ≈ Deuda_proveedores

Capital_trabajo        ≈ Activos_operativos − Pasivos_operativos

Ventas_netas_día       = grossSales − returns   (ya existe en dashboard summary)
COGS_día               = costo de mercancía vendida del día   (gap si API no lo da)
Merma_día              = |ajustes negativos| del día (motivo merma / spoilage)
Ganancia_bruta_día     ≈ Ventas_netas_día − COGS_día
Ganancia_neta_día      ≈ Ganancia_bruta_día − Merma_día (− otros gastos si se agregan)

Regla operativa:
  “Sacar del negocio” ≈ Ganancia_neta_acumulada (no el efectivo bruto del día)
```

### 2.1 KPI específico solicitado (v1 propuesta)

Nombre tentativo: **Salud de capital del día** (`capitalHealthToday`).

Interpretación sencilla en UI (un número + semáforo):

```text
Proxy_capital_día ≈
    Inventario_a_costo          // lo que tengo en góndola/depósito
  + Ventas_netas_día            // lo que entró por cobros (aprox. caja del día)
  − Deuda_proveedores           // lo que debo
  − Merma_día                   // pérdida de inventario del día
  − COGS_día                    // opcional: si ya está “dentro” de ganancia,
                                // no restar dos veces — ver nota abajo
```

**Nota de diseño (a decidir juntos):**

- Si mostramos **Ganancia_neta_día** aparte, el KPI de capital no debe restar otra vez el mismo COGS.
- Variante limpia recomendada para el dashboard:

```text
Capital_trabajo_snapshot = Inventario_a_costo + Caja_día − Deuda_proveedores

Ganancia_neta_día        = Ventas_netas_día − COGS_día − Merma_día

Delta_capital_vs_ayer    = Capital_trabajo_hoy − Capital_trabajo_ayer
```

Así el dueño ve:

1. **Capital** (stock + caja − deuda).  
2. **Ganancia del día** (después de merma).  
3. **Tendencia** (¿crece o se come el capital?).

---

## 3. Qué ya tiene el dashboard hoy (Flutter)

Hoy el dashboard operativo consume reportes de **ventas**:

- `GET /reports/sales/summary` → `grossSales`, `returns`, `netSales`, `tickets`, `avgTicket`
- Timeseries / payments breakdown
- Config por dispositivo (TV / kiosk)

**No tiene aún:** inventario valorizado, deuda proveedores, COGS, merma, capital de trabajo.

Por eso este módulo se implementará **por fases**: primero front contra APIs/SQL que backend exponga; mientras, documentamos las consultas.

---

## 4. Catálogo de estadísticas candidatas

Marcar con `[ ]` / `[x]` al elegir juntos. Prioridad sugerida: **P0** primero.

### P0 — Capital y control diario (pedido del negocio)

| ID | Nombre UI | Descripción | Fuente sugerida |
|----|-----------|-------------|-----------------|
| **S01** | Inventario a costo | Valor del stock activo en funcional | SQL §5.1 doc facturas / API nueva |
| **S02** | Deuda proveedores | Suma saldos OPEN | `GET /purchases/payables` |
| **S03** | Ventas netas del día | Ya existe | `sales/summary` |
| **S04** | Merma del día | Ajustes negativos (filtro motivo) | movimientos inventario / API |
| **S05** | Ganancia neta del día | Ventas − COGS − merma | API report o cálculo server |
| **S06** | Capital de trabajo | Inventario + caja − deuda | composición S01+caja−S02 |
| **S07** | Delta capital vs ayer | Tendencia | snapshot diario persistido |

### P1 — Operación útil

| ID | Nombre UI | Descripción |
|----|-----------|-------------|
| S10 | Top productos por margen | qué conviene reponer |
| S11 | Facturas por vencer (7 días) | `dueDate` |
| S12 | Ticket promedio / # tickets | ya parcial |
| S13 | Mix de pagos (efectivo vs digital) | ya parcial |
| S14 | Compras del día (contado vs crédito) | `GET /purchases` |

### P2 — Proyección / pedidos

| ID | Nombre UI | Descripción |
|----|-----------|-------------|
| S20 | Split caja: ganancia / reposición / abono | doc proyección pedidos |
| S21 | Pedido sugerido por proveedor | stock bajo + lead time |

---

## 5. SQL de referencia (borrador)

> Ejecutar en entorno de análisis / BI. El dashboard de la app preferirá **endpoints** agregados (montos string, `X-Store-Id`), no SQL crudo desde el móvil.

### 5.1 Inventario valorizado (S01)

```sql
SELECT
  ROUND(
    SUM(
      i.quantity * COALESCE(NULLIF(i."averageUnitCostFunctional", 0), p.cost)
    )::numeric,
    2
  ) AS valor_inventario_funcional
FROM "InventoryItem" i
JOIN "Product" p ON p.id = i."productId"
WHERE i."storeId" = :storeId
  AND p.active = true;
```

### 5.2 Deuda proveedores (S02)

```sql
SELECT
  ROUND(SUM(pu."amountDueFunctional")::numeric, 2) AS deuda_total_funcional
FROM "Purchase" pu
WHERE pu."storeId" = :storeId
  AND pu."paymentStatus" IN ('CREDIT', 'PARTIAL')
  AND pu."amountDueFunctional" > 0;
```

### 5.3 Merma del día (S04) — **a validar con schema real de movimientos**

```sql
-- BORRADOR: ajustar nombres de tabla/campos según StockMovement
SELECT
  ROUND(SUM(ABS(m.quantity * COALESCE(m."unitCostFunctional", p.cost)))::numeric, 2)
    AS merma_funcional
FROM "StockMovement" m
JOIN "Product" p ON p.id = m."productId"
WHERE m."storeId" = :storeId
  AND m."createdAt" >= :dayStart
  AND m."createdAt" < :dayEnd
  AND m.type IN ('ADJUST', 'OUT_ADJUST')  -- confirmar enums
  AND m.quantity < 0
  AND (
    LOWER(COALESCE(m.reason, '')) LIKE '%merma%'
    OR LOWER(COALESCE(m.reason, '')) LIKE '%spoil%'
    OR LOWER(COALESCE(m.reason, '')) LIKE '%vencid%'
  );
```

### 5.4 COGS del día (S05) — **gap típico**

Ideal: el backend expone `cogsFunctional` en un reporte diario (desde líneas de venta × costo al momento).  
Si no existe, **no inventar COGS en el móvil** (diverge del ledger). Pedir endpoint.

### 5.5 Snapshot diario de capital (S06/S07)

```sql
-- Tabla sugerida (backend futuro): DailyCapitalSnapshot
-- storeId, date, inventoryValue, cashProxy, payablesDue, capitalWork, netProfit, shrinkage
```

Sin esa tabla, el front solo puede mostrar **snapshot en vivo** (sin “vs ayer” fiable).

---

## 6. Gaps de backend a pedir (para el dashboard)

| Necesidad | ¿Existe hoy? | Pedido |
|-----------|--------------|--------|
| Inventario valorizado | SQL sí / API app no | `GET /reports/inventory/valuation` |
| Deuda total + por proveedor | `GET /purchases/payables` | Usar tal cual |
| COGS del período | ¿? | `GET /reports/sales/summary` + `cogsFunctional` o reporte nuevo |
| Merma del período | parcial (movimientos) | `GET /reports/inventory/shrinkage?from&to` o filtro en movements |
| Caja del día | cierre de caja B2 | Integrar `cash-sessions` summary cuando haya turno |
| Snapshot histórico capital | no | tabla + job diario (P1) |

---

## 7. UI propuesta en el dashboard (sin romper lo actual)

**No reemplazar** el dashboard de ventas. **Agregar** una sección o pestaña:

```text
Dashboard operativo
├── Ventas (actual: summary + chart + pagos)
└── Capital (nuevo)
    ├── KPI: Capital de trabajo
    ├── KPI: Ganancia neta del día
    ├── KPI: Deuda proveedores
    ├── KPI: Inventario a costo
    ├── KPI: Merma del día
    └── (luego) Delta vs ayer / tendencia 7 días
```

Reglas UX:

- Montos **string** + moneda funcional.
- Si falta un dato (ej. COGS): mostrar “—” y chip “pendiente de API”, no inventar.
- Online-first para reportes (como inventario admin); cache opcional después.

---

## 8. Relación con el módulo Facturas (otra entrega)

El KPI de capital **depende** de que el front implemente facturas CREDIT + payables + abonos  
(ver análisis en chat / §6–7 de `FACTURA_PROVEEDOR_DEUDA_E_INVENTARIO_FRONTEND.md`).

Orden recomendado de entregas:

1. **Facturas + deuda** (UI sobre API ya lista).  
2. **Capital P0** en dashboard (S01–S07 con lo que backend dé).  
3. Elegir juntos P1/P2 y cerrar endpoints faltantes.

---

## 9. Decisiones abiertas (elegir juntos)

- [ ] ¿KPI capital usa **caja real** del cierre o solo inventario − deuda en v1?  
- [ ] ¿Merma = solo motivos “merma*” o todos los ajustes negativos?  
- [ ] ¿Ganancia muestra bruta y neta, o solo neta?  
- [ ] ¿Una sola tarjeta “Salud del día” o fila de 4–5 KPIs?  
- [ ] ¿Necesitamos histórico diario (tabla snapshot) desde el día 1?

### Selección inicial sugerida (editable)

| Fase | Estadísticas |
|------|----------------|
| **v1** | S01, S02, S03, S04 (si API/motivo), S06 (sin caja o con proxy), S05 si hay COGS |
| **v1.1** | S07 delta vs ayer |
| **v2** | S10–S14, S20 |

---

## 10. Próximo paso

1. Revisar este doc y marcar §9.  
2. Confirmar qué endpoints backend puede agregar esta semana.  
3. Implementar **Facturas** en Proveedores (UI).  
4. Wire KPIs Capital en dashboard cuando haya datos.

---

*Última actualización: borrador inicial Front — capital + SQL + stats dashboard.*
