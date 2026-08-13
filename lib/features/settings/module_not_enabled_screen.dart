import 'package:flutter/material.dart';

import '../sale/pos_sale_ui_tokens.dart';

/// Pantalla de bloqueo cuando Inventario o Proveedores no están habilitados
/// en este dispositivo (Inicio → switches con clave de administración).
class ModuleNotEnabledScreen extends StatelessWidget {
  const ModuleNotEnabledScreen({
    super.key,
    required this.moduleTitle,
    this.onGoHome,
  });

  final String moduleTitle;
  final VoidCallback? onGoHome;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(moduleTitle),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 56,
                color: PosSaleUi.textMuted,
              ),
              const SizedBox(height: 20),
              Text(
                'No habilitado en este dispositivo',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: PosSaleUi.text,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'Para usar $moduleTitle, habilitalo en Inicio con la clave '
                'de administración (mismo PIN que Configuración).',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: PosSaleUi.textMuted,
                      height: 1.4,
                    ),
              ),
              if (onGoHome != null) ...[
                const SizedBox(height: 28),
                FilledButton.tonal(
                  onPressed: onGoHome,
                  child: const Text('Ir a Inicio'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
