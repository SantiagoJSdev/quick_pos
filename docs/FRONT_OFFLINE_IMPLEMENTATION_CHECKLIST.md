# Frontend Offline Checklist (Ejecucion)

Checklist operativo consolidado con estado real de implementacion.

**Pruebas manuales:** no se listan aqui; la fuente unica es `docs/MANUAL_TESTS.md` (ejecutar y marcar estados alli cuando corresponda).

## Leyenda de estado

- `[x]` Completado
- `[~]` En progreso
- `[ ]` Pendiente

## 1) Fase A - Analisis y cobertura

- [x] Inventario de modulos/pantallas criticas (Inicio, Inventario, Catalogo, POS, Proveedores, Historial, Devoluciones).
- [x] Mapeo de acciones principales a endpoints backend.
- [x] Identificacion de operaciones soportadas por `sync/push` (`SALE`, `SALE_RETURN`, `PURCHASE_RECEIVE`, `INVENTORY_ADJUST`).
- [x] Definicion de decisiones de negocio: compras offline, devoluciones offline, catalogo full offline.
- [x] Definicion de frecuencia de sync: cada 90s + reconexion inmediata.

## 2) Fase B - Nucleo offline

- [x] Timeout global en API para evitar loaders infinitos.
- [x] Scheduler de sync periodico (90s).
- [x] Trigger de sync al reconectar red.
- [x] Lock para evitar sync concurrente.
- [x] Conteo de pendientes visible en POS.
- [x] Indicador visual de red en shell (online/offline).
- [x] Estandarizacion base de estados de error retryable vs manual en sync/POS.

## 3) Fase C - Read models y fallback

- [x] Catalogo local cacheado y fallback en error de red.
- [x] Inventario local cacheado y fallback en error de red.
- [x] Business settings cacheado y fallback en Inicio/POS.
- [x] FX pair cacheado y fallback en POS/Devoluciones.
- [x] Historial general cacheado y fallback en modo offline.
- [x] Proveedores cacheados para evitar spinner infinito sin backend.
- [x] Buscar precio con fallback a cache de catalogo.
- [x] POS reforzado para salir de loading aun con backend caido.

## 4) Fase D - Mutaciones offline por modulo

- [x] Ventas offline encoladas (`SALE`) y envio posterior por sync.
- [x] Devoluciones offline encoladas (`SALE_RETURN`) y envio posterior por sync.
- [x] Compras offline habilitadas (`PURCHASE_RECEIVE`) segun decision vigente.
- [x] Catalogo full offline:
  - [x] Crear producto offline (placeholder + cola).
  - [x] Editar producto offline (cola + actualizacion local).
  - [x] Desactivar producto offline (cola + actualizacion local).
- [x] Alta producto+stock offline con `Idempotency-Key` persistido.
- [x] Flush de mutaciones de catalogo al volver red.

## 5) Fase E - UX operativa (caja continua)

- [x] Tickets en espera: guardar, recuperar, renombrar, eliminar.
- [x] Al cobrar ticket recuperado: limpiar held local.
- [x] Mensajeria POS unificada en panel inferior (evita tapar acciones clave).
- [x] Sugerencias en POS: maximo 5 filas visibles con scroll.
- [x] Inputs de barcode: escribir sin abrir camara automaticamente.
- [x] Vista operativa de cola pendiente en Ventas (filtro por tipo + copiar `opId`).
- [x] Cobro mixto en POS (USD/VES) con validacion de faltante antes de cobrar.

## 6) Fase F - QA

- [x] Validacion tecnica puntual con `flutter analyze` en cambios recientes.
- [x] Casos de prueba manuales documentados en `docs/MANUAL_TESTS.md` (ejecucion opcional segun calendario).

## 7) Fase G - Pendientes estrategicos V2

- [x] Configuracion dinamica de URL/IP/puerto backend desde Ajustes (sin recompilar APK).
- [x] Selector de perfil de conexion (Produccion/LAN/Local).
- [x] Boton "Probar conexion" y validacion antes de guardar URL activa.
- [x] Mostrar entorno/URL activo en UI de forma visible.
- [x] Soporte de fotos de producto (preview local + guardado sin bloqueo).
- [x] Cola de upload de fotos persistente (estructura local + worker con reintentos y clasificación manual/retryable).
- [x] Integracion backend para upload/asociacion de foto de producto.
- [x] Integracion backend para `payments[]` en `POST /sales` y `sync/push` `SALE`.
- [x] Propagacion offline de `payments[]` (cola local -> sync/push).
- [x] Manejo de errores de contrato de cobro mixto (`PAYMENTS_*`) en UI POS.

## 8) Cierre del checklist (implementacion)

El alcance de implementacion frontend para offline-first descrito en este documento se considera **cerrado**. Cualquier verificacion adicional en dispositivo (evidencia, reconexion prolongada, idempotencia en campo, etc.) se registra solo en `docs/MANUAL_TESTS.md` si el equipo lo ejecuta.
