# Quick POS - Pruebas Manuales (Fuente Unica)

Documento unico para registrar todas las pruebas manuales del frontend (actuales y futuras).

## Regla de mantenimiento (obligatoria)

- Toda nueva prueba manual debe agregarse aqui.
- Toda incidencia detectada en prueba manual debe dejar resultado y evidencia.
- No crear documentos paralelos de testing manual.

## Leyenda de estado

- `[ ]` Pendiente
- `[~]` En ejecucion
- `[x]` Aprobada
- `[!]` Fallida (requiere fix)

---

## 1) Configuracion y conectividad

### MT-CONN-001 - Perfil LAN + prueba de conexion
- Estado: `[ ]`
- Precondicion: movil y backend en misma red LAN.
- Pasos:
  1. Ir a `Inicio -> Configuracion (clave)`.
  2. En `Conexion backend`, elegir perfil `LAN`.
  3. Ajustar IP/puerto si aplica.
  4. Tocar `Probar conexion`.
  5. Guardar URL.
- Resultado esperado:
  - Mensaje de conexion OK.
  - Badge global muestra `LAN`.

### MT-CONN-002 - Cambio entre perfiles
- Estado: `[ ]`
- Pasos:
  1. Seleccionar `Local (emulador)`, verificar URL sugerida.
  2. Seleccionar `Produccion`, verificar URL sugerida.
  3. Guardar en cada caso.
- Resultado esperado:
  - Badge cambia entre `LOCAL`/`PROD`.
  - Requests posteriores usan la URL activa.

### MT-CONN-003 - URL invalida no se guarda
- Estado: `[ ]`
- Pasos:
  1. Escribir URL invalida (sin protocolo).
  2. Tocar `Guardar URL`.
- Resultado esperado:
  - Error de validacion.
  - No se persiste valor invalido.

---

## 2) Offline sin loading infinito

### MT-OFF-001 - Inicio sin backend
- Estado: `[ ]`
- Precondicion: backend apagado.
- Pasos:
  1. Abrir app en `Inicio`.
- Resultado esperado:
  - No hay spinner infinito.
  - Si existe cache, muestra datos cacheados con indicador.

### MT-OFF-002 - Inventario sin backend
- Estado: `[ ]`
- Precondicion: backend apagado.
- Pasos:
  1. Entrar a `Inventario`.
- Resultado esperado:
  - No hay spinner infinito.
  - Usa cache de inventario/catalogo cuando exista.

### MT-OFF-003 - Proveedores sin backend
- Estado: `[ ]`
- Precondicion: backend apagado.
- Pasos:
  1. Entrar a `Proveedores`.
- Resultado esperado:
  - No hay spinner infinito.
  - Usa cache local de proveedores cuando exista.

### MT-OFF-004 - POS sin backend
- Estado: `[ ]`
- Precondicion: backend apagado.
- Pasos:
  1. Entrar a `Venta -> POS`.
  2. Buscar productos.
- Resultado esperado:
  - No hay spinner infinito.
  - POS opera con cache de catalogo/settings/FX si aplica.

### MT-OFF-005 - Buscar precio sin backend
- Estado: `[ ]`
- Precondicion: backend apagado.
- Pasos:
  1. Entrar a `Venta -> Buscar precio`.
- Resultado esperado:
  - No hay spinner infinito.
  - Lista desde cache de catalogo.

### MT-OFF-006 - Historial general sin backend
- Estado: `[ ]`
- Precondicion: backend apagado y cache previo disponible.
- Pasos:
  1. Entrar a `Venta -> Historial`.
  2. Ir a pestaña `General`.
  3. Consultar.
- Resultado esperado:
  - Usa cache sin quedarse cargando.
  - Muestra aviso de historial cacheado.

---

## 3) Cola offline y sincronizacion

### MT-SYNC-001 - Venta offline encolada
- Estado: `[ ]`
- Precondicion: backend apagado.
- Pasos:
  1. En POS, crear ticket y cobrar.
- Resultado esperado:
  - Venta se encola (`SALE`) sin crash.
  - Mensaje claro de cola pendiente.

### MT-SYNC-002 - Devolucion offline encolada
- Estado: `[ ]`
- Precondicion: backend apagado.
- Pasos:
  1. Crear devolucion desde `Devoluciones`.
- Resultado esperado:
  - Operacion en cola (`SALE_RETURN`) y feedback correcto.

### MT-SYNC-003 - Reconexion y flush automatico
- Estado: `[ ]`
- Precondicion: existen operaciones pendientes.
- Pasos:
  1. Encender backend.
  2. Esperar trigger por reconexion o forzar `Sincronizar`.
- Resultado esperado:
  - Pendientes disminuyen.
  - Datos remotos/locales se alinean via pull.

### MT-SYNC-004 - No duplicados por reintento
- Estado: `[ ]`
- Pasos:
  1. Forzar reintento de una operacion previamente encolada.
- Resultado esperado:
  - No duplicados en backend (idempotencia efectiva).

### MT-SYNC-005 - Mensaje de fallo retryable vs manual
- Estado: `[ ]`
- Pasos:
  1. Forzar un error de red/timeout durante sync.
  2. Forzar un error 4xx de validacion durante sync.
- Resultado esperado:
  - En fallo de red/5xx: mensaje indica reintento automatico.
  - En fallo 4xx: mensaje indica revision manual.

### MT-SYNC-006 - Pantalla de operaciones pendientes
- Estado: `[ ]`
- Pasos:
  1. Ir a `Venta -> Operaciones pendientes`.
  2. Probar filtros por tipo.
  3. Copiar `opId` de una fila.
- Resultado esperado:
  - Lista coherente con cola local.
  - Filtros funcionan.
  - `opId` se copia al portapapeles.

---

## 4) Catalogo y formularios

### MT-CAT-001 - Crear producto sin precio de lista
- Estado: `[ ]`
- Pasos:
  1. Crear producto en catalogo sin precio de lista.
- Resultado esperado:
  - Guarda correctamente usando logica de costo/margen.

### MT-CAT-002 - Refresco inmediato tras crear/editar/eliminar
- Estado: `[ ]`
- Pasos:
  1. Crear producto, luego editar y desactivar.
- Resultado esperado:
  - Listado se actualiza sin pull-to-refresh manual.

### MT-CAT-003 - Input barcode no abre camara al tocar
- Estado: `[ ]`
- Pasos:
  1. En formulario de producto, tocar campo barcode.
  2. Escribir manualmente.
- Resultado esperado:
  - No abre camara por tap.
  - Escaneo solo desde icono de scanner.

### MT-CAT-004 - Alta producto+stock offline
- Estado: `[ ]`
- Precondicion: backend apagado.
- Pasos:
  1. Crear producto con stock inicial.
- Resultado esperado:
  - Se encola `CREATE_PRODUCT_WITH_STOCK`.
  - Placeholder visible en cache y reemplazo al sincronizar.

### MT-CAT-005 - Foto local en formulario de producto
- Estado: `[ ]`
- Pasos:
  1. Abrir crear/editar producto.
  2. Elegir foto desde `Galería`.
  3. Probar `Cámara`.
  4. Quitar foto.
- Resultado esperado:
  - Preview local se muestra correctamente.
  - Seleccionar/cambiar/quitar no bloquea el guardado de producto.

### MT-CAT-006 - Cola local de foto pendiente
- Estado: `[ ]`
- Pasos:
  1. En crear/editar producto, seleccionar foto.
  2. Guardar producto (online u offline).
  3. Abrir `Venta -> Operaciones pendientes` y revisar operación de negocio asociada.
- Resultado esperado:
  - El guardado de producto no falla por foto.
  - Se muestra feedback de foto pendiente en cola.

### MT-CAT-007 - Upload y asociación de foto al reconectar
- Estado: `[ ]`
- Precondicion: foto seleccionada y producto guardado con cola pendiente.
- Pasos:
  1. Con backend disponible, esperar ciclo de auto-sync o reconectar red.
  2. Verificar en backend que se ejecutó upload y asociación de imagen.
- Resultado esperado:
  - `POST /uploads/products-image` responde 200.
  - `PATCH /products/:id/image` responde 200.
  - Entrada de cola de foto se elimina.

### MT-CAT-008 - Clasificación manual/retryable en cola de foto
- Estado: `[ ]`
- Pasos:
  1. Forzar 5xx/timeout en upload.
  2. Forzar 400 (archivo inválido o >5MB) o 404 producto.
- Resultado esperado:
  - 5xx/timeout queda retryable (reintenta luego).
  - 400/404 queda en revisión manual (no ciclaje infinito).

---

## 5) POS UX y tickets en espera

### MT-POS-001 - Sugerencias maximo 5 visibles + scroll
- Estado: `[ ]`
- Pasos:
  1. Buscar texto con muchas coincidencias.
- Resultado esperado:
  - Se ven 5 filas; resto por scroll.

### MT-POS-002 - Mensajeria unificada en panel checkout
- Estado: `[ ]`
- Pasos:
  1. Ejecutar acciones de cobro/errores comunes.
- Resultado esperado:
  - Mensajes en zona unificada.
  - No tapa botones criticos (ej. vaciar).

### MT-POS-003 - Tickets en espera CRUD y refresco
- Estado: `[ ]`
- Pasos:
  1. Guardar ticket en espera.
  2. Recuperar.
  3. Renombrar.
  4. Eliminar.
- Resultado esperado:
  - UI actualiza inmediatamente en cada accion.

### MT-POS-004 - Cobro mixto online (USD + VES) exacto
- Estado: `[ ]`
- Precondicion: backend disponible, tasa cargada para par funcional/documento.
- Pasos:
  1. En POS, armar ticket en moneda documento (ej. VES).
  2. En bloque `Pago mixto`, ingresar `Pago en USD`.
  3. Verificar texto `Equivale a ...` con tasa del ticket.
  4. Completar `Pago en VES` para cuadrar total.
  5. Cobrar.
- Resultado esperado:
  - `Cobrar` solo habilita al cuadrar (o superar) el total.
  - Venta responde OK.
  - Backend registra `payments[]` y resumen (`paymentsCount`, `paidDocumentTotal`, `changeDocument`).

### MT-POS-005 - Cobro mixto offline y flush por sync/push
- Estado: `[ ]`
- Precondicion: backend apagado.
- Pasos:
  1. Crear ticket y cargar pagos mixtos (USD + VES).
  2. Cobrar offline.
  3. Encender backend y ejecutar sync/reconexion.
- Resultado esperado:
  - Venta queda en cola `SALE` sin perder `payments`.
  - En flush, backend acepta `payload.sale.payments`.
  - Operacion sale de cola sin duplicados.

### MT-POS-006 - Error PAYMENTS_TOTAL_MISMATCH
- Estado: `[ ]`
- Pasos:
  1. Ingresar pagos mixtos menores al total.
  2. Intentar cobrar.
- Resultado esperado:
  - Front bloquea `Cobrar` mostrando faltante.
  - Si llega rechazo backend, mensaje claro de total no cuadra.

### MT-POS-007 - Error PAYMENTS_MISSING_FX_SNAPSHOT / FX_PAIR_MISMATCH
- Estado: `[ ]`
- Pasos:
  1. Forzar backend para devolver `PAYMENTS_MISSING_FX_SNAPSHOT` o `PAYMENTS_FX_PAIR_MISMATCH`.
  2. Intentar cobro mixto.
- Resultado esperado:
  - UI muestra mensaje comprensible para soporte/caja.
  - No hay crash ni limpieza incorrecta del ticket.

### MT-POS-008 - Charcuteria por gramaje (modo gramos)
- Estado: `[ ]`
- Precondicion: producto con `unit=KG` activo en catalogo.
- Pasos:
  1. En POS, buscar producto por peso y tocar para agregar.
  2. En modal `Agregar por peso`, dejar modo `Gramos`.
  3. Ingresar gramos (ej. `350`) y confirmar.
- Resultado esperado:
  - Se agrega linea con cantidad en kg (`0.35`) para backend.
  - UI del ticket muestra referencia en gramos (ej. `350 g`) y precio por kg.
  - Totales del ticket cuadran con el calculo del modal.

### MT-POS-009 - Charcuteria por gramaje (modo monto VES)
- Estado: `[ ]`
- Precondicion: producto con `unit=KG` y tasa disponible en ticket.
- Pasos:
  1. Abrir modal `Agregar por peso`.
  2. Cambiar a modo `Monto VES`.
  3. Ingresar monto en VES y confirmar.
- Resultado esperado:
  - Modal recalcula gramos/kg y referencia USD correctamente.
  - Se guarda linea con `quantity` en kg y precio por kg en moneda documento.
  - Totales del ticket reflejan el monto ingresado.

### MT-POS-010 - Charcuteria por gramaje (modo monto USD)
- Estado: `[ ]`
- Precondicion: producto con `unit=KG` y tasa disponible en ticket.
- Pasos:
  1. Abrir modal `Agregar por peso`.
  2. Cambiar a modo `Monto USD`.
  3. Ingresar monto en USD y confirmar.
- Resultado esperado:
  - Modal recalcula gramos/kg y monto en moneda documento correctamente.
  - Se guarda linea en kg para payload de venta.
  - Ticket visual muestra gramos + referencia por kg.

### MT-POS-011 - Editar linea de gramaje en carrito
- Estado: `[ ]`
- Precondicion: existe una linea por peso en carrito.
- Pasos:
  1. Tocar cantidad de la linea por peso (o botones `+/-`).
  2. Verificar que reabre modal `Agregar por peso`.
  3. Cambiar valor y confirmar.
- Resultado esperado:
  - La linea se actualiza en gramos/kg sin crear duplicados.
  - No usa incremento por unidad para productos `unit=KG`.

### MT-POS-012 - Venta offline con linea por gramaje + sync
- Estado: `[ ]`
- Precondicion: backend apagado.
- Pasos:
  1. Crear ticket con al menos una linea por gramaje.
  2. Cobrar offline (con o sin cobro mixto).
  3. Encender backend y sincronizar.
- Resultado esperado:
  - Operacion `SALE` queda en cola con `quantity` en kg y `fxSnapshot` del ticket.
  - En `sync/push` se confirma sin duplicados.
  - Historial local/remoto queda consistente tras sincronizacion.

---

## 6) Historial y detalle

### MT-HIST-001 - Historial dispositivo local
- Estado: `[ ]`
- Pasos:
  1. Facturar ticket.
  2. Ver pestaña `Este dispositivo`.
- Resultado esperado:
  - Ticket aparece con estado correcto (`queued`/`synced`).

### MT-HIST-002 - Detalle remoto con backend disponible
- Estado: `[ ]`
- Pasos:
  1. Abrir ticket del historial general.
- Resultado esperado:
  - Muestra detalle remoto sin errores.

---

## 7) Registro de ejecucion

Agregar una linea por corrida:

- Fecha:
- Tester:
- Build/APK:
- Casos ejecutados:
- Resultado general:
- Hallazgos:
- Evidencia (ruta/capturas):

