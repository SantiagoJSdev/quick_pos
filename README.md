# quick_pos

Flutter project quick.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

<!-- flutter run -d emulator-5554
flutter build apk --release -->
<!-- flutter run -->



<!-- ) Integración en el flujo (poca UI, mucho valor)
Una sola pantalla o sección “Resumen de sesión offline” (accesible desde Inicio o desde el banner de cola) que muestre:

Bloque	Contenido
Contadores
Pendientes por opType (SALE, SALE_RETURN, PURCHASE_RECEIVE, catálogo, proveedor, fotos, etc.)
Último sync
serverTime de la última respuesta de sync/push (si ya lo tenés en memoria/prefs; si no, persistir solo eso + conteos ack/skipped/failed)
Acción
Botón “Copiar resumen” (texto plano para pegar en ticket de QA o Slack)
Momento en el flujo: al desactivar “offline forzado” o al detectar backend alcanzable + cola vacía, mostrar un snack o bottom sheet breve: “Último push: N ack, 0 failed — cola limpia”.

Con eso cubrís exactamente el escenario “facturamos 3 productos en 2 ventas, dimos de alta 3 productos y un proveedor, anulamos…” sin inventar un nuevo modelo de negocio: seguís confiando en la cola y en la respuesta del servidor, pero el cajero/QA ve un checklist vivo. -->