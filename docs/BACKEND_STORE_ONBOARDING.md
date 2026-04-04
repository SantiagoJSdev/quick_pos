# Onboarding de tienda desde la app (backend)

Ya podéis **crear la tienda y los `BusinessSettings`** sin flujo admin previo, con dos **`PUT`** bajo `/api/v1`. La app Flutter (`StoresApi.registerNewStore`) sigue este contrato.

**Documentación relacionada**

- Ejemplos JSON y flujo: **`FRONTEND_INTEGRATION_CONTEXT.md`** — **§13.0** (onboarding).
- Contrato general API: mismo archivo, sección 2 (cabeceras, onboarding).
- **Swagger:** `/api/docs` en el servidor Nest.

---

## Activación en servidor

| Variable `.env` | Efecto |
|-----------------|--------|
| `STORE_ONBOARDING_ENABLED=1` o `true` | Los dos `PUT` de abajo están **habilitados**. |
| Ausente u otro valor | Esos `PUT` responden **403 Forbidden** (evita que cualquiera en LAN cree tiendas). |

El cliente debe tratar **403** en onboarding como “feature desactivada en servidor”; ver mensaje M0 en cuerpo JSON.

---

## Contrato HTTP

### 1) Upsert tienda

**`PUT /api/v1/stores/:storeId`**

| Requisito | Valor |
|-----------|--------|
| Cabecera `X-Store-Id` | **Obligatoria**, igual al UUID de `:storeId` (el UUID lo genera el cliente, p. ej. v4). |
| Cuerpo JSON | `{ "name": string, "type": "main" \| "branch" }` |

**Efecto:** upsert de `Store` con `id = :storeId`.

**Respuesta 200:** objeto `Store` (`id`, `name`, `type`, `createdAt`, `updatedAt`, … — según Prisma/Swagger).

---

### 2) Crear o actualizar BusinessSettings

**`PUT /api/v1/stores/:storeId/business-settings`**

| Requisito | Valor |
|-----------|--------|
| Cabecera `X-Store-Id` | Igual a `:storeId`. |
| Cuerpo JSON | `{ "functionalCurrencyCode": "USD", "defaultSaleDocCurrencyCode": "VES" }` |

Los códigos deben existir en la tabla **`Currency`** (p. ej. seed). Si no existen → **400** con mensaje claro.

**Efecto:** crea o actualiza `BusinessSettings` para esa tienda.

**Respuesta 200:** **mismo shape** que **`GET /api/v1/stores/:storeId/business-settings`** (incluye `functionalCurrency`, `defaultSaleDocCurrency`, `store` anidados — ver **§13.2** del contexto front).

---

## Orden recomendado (app / Postman)

1. **`PUT`** `/stores/:storeId` (nombre + tipo).
2. **`PUT`** `/stores/:storeId/business-settings` (monedas por código).
3. *(Opcional)* **`POST`** `/api/v1/exchange-rates` — primera tasa para la tienda (`X-Store-Id` ya válido).
4. Verificar con **`GET`** `/api/v1/stores/:storeId/business-settings` (la app Flutter hace este paso al final de `registerNewStore`).

---

## Seguridad

- Sin `STORE_ONBOARDING_ENABLED`, los `PUT` de onboarding no deben exponer creación de tiendas en redes no confiables.
- En producción, combinar con red privada, VPN o políticas adicionales según el despliegue.

---

## App Flutter

| Pieza | Ubicación |
|-------|-----------|
| Llamadas `PUT` + `GET` de verificación | `lib/core/api/stores_api.dart` → `registerNewStore` |
| Tasa inicial opcional | `lib/core/api/exchange_rates_api.dart` → `createRate` |
| UI | `lib/features/settings/create_store_screen.dart` |

Si el backend cambiara método o rutas, ajustar solo `ApiClient` / `StoresApi`.
