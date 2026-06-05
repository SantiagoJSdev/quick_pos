# Documentación Quick POS (Flutter)

Solo **dos documentos** mantienen el contexto del proyecto:

| Documento | Para qué |
|-----------|----------|
| [`FRONTEND_INTEGRATION_CONTEXT.md`](./FRONTEND_INTEGRATION_CONTEXT.md) | **Fuente única de verdad:** arquitectura, flujos, contratos API, módulos Flutter, dashboard, offline, sync, **pendientes de implementar**. |
| [`MANUAL_TESTS.md`](./MANUAL_TESTS.md) | **QA manual:** casos de prueba, estados `[ ]` / `[x]`, registro de ejecuciones. |

## Reglas

1. No crear docs paralelos en `docs/` — ampliar `FRONTEND_INTEGRATION_CONTEXT.md`.
2. Nueva prueba manual → `MANUAL_TESTS.md`.
3. Contratos detallados del **backend Nest** viven en el repo del API (Swagger `/api/docs`), no duplicados aquí salvo lo que el front consume.

## Inicio rápido dev

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3002/api/v1
```

- Emulador Android → `10.0.2.2` (no `localhost`).
- PIN admin app (default): `1200Mia` — debe coincidir con `DASHBOARD_ADMIN_PIN` / `CONFIG_ADMIN_PIN` del servidor para dashboard.
