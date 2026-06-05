# Quick POS

App Flutter de punto de venta (Quick Market) con soporte offline, multi-moneda y dashboard operativo.

## Documentacion

Toda la contexto para desarrollo esta en:

- **[docs/README.md](docs/README.md)** — indice
- **[docs/FRONTEND_INTEGRATION_CONTEXT.md](docs/FRONTEND_INTEGRATION_CONTEXT.md)** — arquitectura, flujos, API, modulos, pendientes
- **[docs/MANUAL_TESTS.md](docs/MANUAL_TESTS.md)** — QA manual

## Ejecutar

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3002/api/v1
```

| Entorno | URL API |
|---------|---------|
| Emulador Android | `http://10.0.2.2:3002/api/v1` |
| Dispositivo LAN | `http://<IP-PC>:3002/api/v1` (o configurar en Inicio → Configuracion) |

PIN administracion (default): `1200Mia` — alinear con el backend para dashboard y config de tienda.

## Estructura

```text
lib/
  core/          # API, sync, prefs, modelos
  features/      # inventory, sale, suppliers, dashboard, settings, shell
docs/            # 2 documentos + indice
```
