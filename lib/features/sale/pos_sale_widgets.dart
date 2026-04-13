import 'package:flutter/material.dart';

import '../../core/models/catalog_product.dart';
import '../../core/models/pos_cart_line.dart';
import '../../core/widgets/quickmarket_branding.dart';
import 'pos_sale_ui_tokens.dart';

String _posLeadingInitial(String name) {
  if (name.isEmpty) return '?';
  final it = name.runes.iterator;
  if (!it.moveNext()) return '?';
  return String.fromCharCode(it.current).toUpperCase();
}

class PosSaleTopBar extends StatelessWidget {
  const PosSaleTopBar({
    super.key,
    required this.onRefresh,
    required this.onSync,
    this.syncBusy = false,
    this.showSyncDot = false,
    this.onBack,
  });

  final VoidCallback onRefresh;
  final VoidCallback onSync;
  final bool syncBusy;
  final bool showSyncDot;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 6),
      decoration: const BoxDecoration(
        color: PosSaleUi.surface,
        border: Border(bottom: BorderSide(color: PosSaleUi.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (onBack != null) ...[
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: onBack,
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: PosSaleUi.text,
              ),
              tooltip: 'Volver',
            ),
            const SizedBox(width: 2),
          ],
          const QuickMarketWordmark(
            logoSize: 22,
            fontSize: 12,
            gap: 6,
          ),
          const Spacer(),
          IconButton(
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, color: PosSaleUi.textMuted, size: 20),
            tooltip: 'Recargar catálogo',
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: syncBusy ? null : onSync,
                icon: syncBusy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: PosSaleUi.primary,
                        ),
                      )
                    : const Icon(
                        Icons.cloud_sync_outlined,
                        color: PosSaleUi.textMuted,
                        size: 20,
                      ),
                tooltip: 'Sincronizar',
              ),
              if (showSyncDot)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: PosSaleUi.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: PosSaleUi.surface, width: 1),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Buscador fijo + botón escáner.
class PosSaleSearchBlock extends StatefulWidget {
  const PosSaleSearchBlock({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onScanTap,
    this.onScanLongPress,
    this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onScanTap;

  /// Demo / emulador: escaneo aleatorio sin cámara.
  final VoidCallback? onScanLongPress;
  final VoidCallback? onClear;

  @override
  State<PosSaleSearchBlock> createState() => _PosSaleSearchBlockState();
}

class _PosSaleSearchBlockState extends State<PosSaleSearchBlock> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        color: PosSaleUi.surface,
        border: Border(bottom: BorderSide(color: PosSaleUi.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (context, v, _) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: PosSaleUi.surface3,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: widget.focusNode.hasFocus
                          ? PosSaleUi.primary
                          : PosSaleUi.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search,
                        size: 18,
                        color: PosSaleUi.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: widget.controller,
                          focusNode: widget.focusNode,
                          style: const TextStyle(
                            color: PosSaleUi.text,
                            fontSize: 14,
                          ),
                          cursorColor: PosSaleUi.primary,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: 'Buscar producto o código…',
                            hintStyle: TextStyle(color: PosSaleUi.textFaint),
                          ),
                          autocorrect: false,
                          enableSuggestions: false,
                          smartDashesType: SmartDashesType.disabled,
                          smartQuotesType: SmartQuotesType.disabled,
                          spellCheckConfiguration:
                              SpellCheckConfiguration.disabled(),

                          /// En Android suele ocultar la franja de sugerencias encima del teclado.
                          keyboardType: TextInputType.visiblePassword,
                          textInputAction: TextInputAction.search,
                        ),
                      ),
                      if (v.text.isNotEmpty)
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          onPressed: widget.onClear,
                          icon: const Icon(
                            Icons.close,
                            size: 18,
                            color: PosSaleUi.textMuted,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: widget.onScanLongPress != null
                ? 'Escanear con la cámara (mantén pulsado: simular en demo)'
                : 'Escanear con la cámara',
            child: Material(
              color: PosSaleUi.primaryDim,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: widget.onScanTap,
                onLongPress: widget.onScanLongPress,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: PosSaleUi.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner,
                    color: PosSaleUi.primary,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PosSaleSearchResultTile extends StatelessWidget {
  const PosSaleSearchResultTile({
    super.key,
    required this.product,
    required this.primaryLine,
    required this.secondaryLine,
    this.imageUrl,
    required this.onTap,
  });

  final CatalogProduct product;
  final String primaryLine;
  final String secondaryLine;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: PosSaleUi.surface4,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: () {
                    final img = imageUrl?.trim();
                    if (img == null || img.isEmpty) {
                      return Center(
                        child: Text(
                          _posLeadingInitial(product.name),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: PosSaleUi.text,
                          ),
                        ),
                      );
                    }
                    return Image.network(
                      img,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Center(
                        child: Text(
                          _posLeadingInitial(product.name),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: PosSaleUi.text,
                          ),
                        ),
                      ),
                    );
                  }(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: PosSaleUi.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      secondaryLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: PosSaleUi.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                primaryLine,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: PosSaleUi.text,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PosSaleCartLineTile extends StatelessWidget {
  const PosSaleCartLineTile({
    super.key,
    required this.line,
    this.imageUrl,
    required this.unitFunctional,
    required this.lineTotalFunctional,
    required this.functionalCode,
    required this.documentCode,
    required this.onMinus,
    required this.onPlus,
    required this.onQtyTap,
    required this.onDismissed,
    this.onShowPriceDetail,
  });

  final PosCartLine line;
  final String? imageUrl;
  final String unitFunctional;
  final String lineTotalFunctional;
  final String functionalCode;
  final String documentCode;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onQtyTap;
  final VoidCallback onDismissed;
  final VoidCallback? onShowPriceDetail;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('cart_${line.productId}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: PosSaleUi.error.withValues(alpha: 0.2),
        child: const Icon(Icons.delete_outline, color: PosSaleUi.error),
      ),
      onDismissed: (_) => onDismissed(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: PosSaleUi.surface3,
                borderRadius: BorderRadius.circular(6),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: () {
                  final img = imageUrl?.trim();
                  if (img == null || img.isEmpty) {
                    return Center(
                      child: Text(
                        _posLeadingInitial(line.name),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: PosSaleUi.text,
                        ),
                      ),
                    );
                  }
                  return Image.network(
                    img,
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Text(
                        _posLeadingInitial(line.name),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: PosSaleUi.text,
                        ),
                      ),
                    ),
                  );
                }(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: onShowPriceDetail != null
                  ? Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onShowPriceDetail,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            line.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: PosSaleUi.text,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        line.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: PosSaleUi.text,
                          height: 1.2,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 6),
            _QtyPill(
              quantity: line.quantity,
              quantityDisplay: line.isByWeight && line.displayGrams != null
                  ? '${line.displayGrams} g'
                  : null,
              onMinus: onMinus,
              onPlus: onPlus,
              onQtyTap: onQtyTap,
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyPill extends StatelessWidget {
  const _QtyPill({
    required this.quantity,
    this.quantityDisplay,
    required this.onMinus,
    required this.onPlus,
    required this.onQtyTap,
  });

  final String quantity;
  final String? quantityDisplay;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onQtyTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: PosSaleUi.surface3,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: PosSaleUi.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniIcon(icon: Icons.remove, onTap: onMinus),
          InkWell(
            onTap: onQtyTap,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                quantityDisplay ?? quantity,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: PosSaleUi.text,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          _MiniIcon(icon: Icons.add, onTap: onPlus),
        ],
      ),
    );
  }
}

class _MiniIcon extends StatelessWidget {
  const _MiniIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  /// Mínimo ~40 logical px para que en emulador/dedo sea fácil acertar (Material ~48).
  static const double _tap = 40;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          width: _tap,
          height: _tap,
          child: Icon(icon, size: 22, color: PosSaleUi.textMuted),
        ),
      ),
    );
  }
}

class PosSaleCheckoutPanel extends StatelessWidget {
  const PosSaleCheckoutPanel({
    super.key,
    required this.functionalCode,
    required this.documentCode,
    required this.functionalTotalLabel,
    required this.documentTotalLabel,
    required this.totalFunctional,
    required this.totalDocument,
    required this.itemsSummary,
    required this.cartNotEmpty,
    required this.onClear,
    required this.onCharge,
    required this.chargeBusy,
    this.onDiscount,
    this.currencySelector,
    this.cartFeedback,
    this.cartFeedbackIsError = false,
    this.onPutOnHold,
    this.onOpenHeldTickets,
    this.heldTicketsCount = 0,
    this.onOpenMixedPayment,
    this.onClearMixedPayment,
    /// Una sola línea, p. ej. `USD: 10.00 · resta VES: 360.00` (null si no hay pago mixto).
    this.mixedPaymentDetailLine,
    this.canChargeWithPayments = true,
  });

  final String functionalCode;
  final String documentCode;
  final String functionalTotalLabel;
  final String documentTotalLabel;
  final String totalFunctional;
  final String totalDocument;
  final String itemsSummary;
  final bool cartNotEmpty;
  final VoidCallback onClear;
  final VoidCallback onCharge;
  final bool chargeBusy;
  final VoidCallback? onDiscount;
  final Widget? currencySelector;

  /// Mensaje breve al agregar al ticket (arriba de «Moneda del ticket»; no tapa Cobrar/Vaciar).
  final String? cartFeedback;

  /// Estilo de aviso (error) para el mismo bloque que [cartFeedback].
  final bool cartFeedbackIsError;

  /// Guardar carrito en espera (local, sin API).
  final VoidCallback? onPutOnHold;

  /// Abrir lista de tickets en espera.
  final VoidCallback? onOpenHeldTickets;

  /// Cantidad de tickets guardados en este dispositivo / tienda.
  final int heldTicketsCount;
  final VoidCallback? onOpenMixedPayment;
  final VoidCallback? onClearMixedPayment;
  final String? mixedPaymentDetailLine;
  final bool canChargeWithPayments;

  @override
  Widget build(BuildContext context) {
    final feedback = cartFeedback?.trim();
    final err = cartFeedbackIsError;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        color: PosSaleUi.surface,
        border: Border(top: BorderSide(color: PosSaleUi.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (feedback != null && feedback.isNotEmpty) ...[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: err
                      ? PosSaleUi.error.withValues(alpha: 0.12)
                      : PosSaleUi.primaryDim,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: err
                        ? PosSaleUi.error.withValues(alpha: 0.45)
                        : PosSaleUi.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        err
                            ? Icons.error_outline_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 16,
                        color: err ? PosSaleUi.error : PosSaleUi.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          feedback,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.2,
                            color: err ? PosSaleUi.error : PosSaleUi.text,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (heldTicketsCount > 0 && onOpenHeldTickets != null) ...[
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onOpenHeldTickets,
                  icon: const Icon(
                    Icons.inventory_2_outlined,
                    size: 16,
                    color: PosSaleUi.primary,
                  ),
                  label: Text(
                    'Guardados ($heldTicketsCount)',
                    style: const TextStyle(
                      color: PosSaleUi.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
            ],
            if (currencySelector != null) ...[
              currencySelector!,
              const SizedBox(height: 4),
            ],
            if (cartNotEmpty) ...[
              Text(
                itemsSummary,
                style: const TextStyle(
                  fontSize: 10,
                  height: 1.1,
                  color: PosSaleUi.textMuted,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: PosSaleUi.surface3,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: PosSaleUi.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _TotalBlock(
                      label: functionalTotalLabel,
                      amount: totalFunctional,
                      highlight: false,
                      dense: true,
                    ),
                  ),
                  Container(width: 1, height: 36, color: PosSaleUi.divider),
                  Expanded(
                    child: _TotalBlock(
                      label: documentTotalLabel,
                      amount: totalDocument,
                      highlight: true,
                      dense: true,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: cartNotEmpty ? onClear : null,
                  style: IconButton.styleFrom(
                    backgroundColor: PosSaleUi.surface3,
                    foregroundColor: PosSaleUi.textMuted,
                    padding: const EdgeInsets.all(6),
                    minimumSize: const Size(36, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Vaciar ticket',
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  onPressed: onDiscount,
                  style: IconButton.styleFrom(
                    backgroundColor: PosSaleUi.surface3,
                    foregroundColor: PosSaleUi.textFaint,
                    padding: const EdgeInsets.all(6),
                    minimumSize: const Size(36, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.percent_outlined, size: 20),
                  tooltip: 'Descuentos — próximamente',
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  onPressed: (cartNotEmpty && onPutOnHold != null)
                      ? onPutOnHold
                      : null,
                  style: IconButton.styleFrom(
                    backgroundColor: PosSaleUi.surface3,
                    foregroundColor: PosSaleUi.primary,
                    padding: const EdgeInsets.all(6),
                    minimumSize: const Size(36, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.pause_circle_outline, size: 20),
                  tooltip: 'Poner ticket en espera',
                ),
                if (onOpenMixedPayment != null) ...[
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    onPressed: cartNotEmpty ? onOpenMixedPayment : null,
                    style: IconButton.styleFrom(
                      backgroundColor: mixedPaymentDetailLine != null
                          ? PosSaleUi.primary.withValues(alpha: 0.2)
                          : PosSaleUi.surface3,
                      foregroundColor: canChargeWithPayments
                          ? PosSaleUi.text
                          : PosSaleUi.error,
                      padding: const EdgeInsets.all(6),
                      minimumSize: const Size(36, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: Icon(
                      Icons.attach_money,
                      size: 20,
                      color: mixedPaymentDetailLine != null
                          ? PosSaleUi.primary
                          : PosSaleUi.textMuted,
                    ),
                    tooltip: 'Pago $functionalCode',
                  ),
                  if (mixedPaymentDetailLine != null &&
                      onClearMixedPayment != null) ...[
                    IconButton(
                      onPressed: onClearMixedPayment,
                      tooltip: 'Quitar pago $functionalCode',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 36,
                      ),
                      icon: const Icon(
                        Icons.backspace_outlined,
                        size: 18,
                        color: PosSaleUi.textMuted,
                      ),
                    ),
                  ],
                ],
                const SizedBox(width: 6),
                Expanded(
                  child: FilledButton(
                    onPressed:
                        (cartNotEmpty && canChargeWithPayments && !chargeBusy)
                        ? onCharge
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: PosSaleUi.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: PosSaleUi.surface4,
                      disabledForegroundColor: PosSaleUi.textFaint,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      minimumSize: const Size(0, 40),
                      elevation: cartNotEmpty ? 2 : 0,
                      shadowColor: PosSaleUi.primary.withValues(alpha: 0.35),
                    ),
                    child: chargeBusy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.payments_outlined, size: 16),
                              SizedBox(width: 6),
                              Text(
                                'Cobrar',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalBlock extends StatelessWidget {
  const _TotalBlock({
    required this.label,
    required this.amount,
    required this.highlight,
    this.dense = false,
  });

  final String label;
  final String amount;
  final bool highlight;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: dense ? 4 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: dense ? 8 : 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: PosSaleUi.textMuted,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: dense ? 2 : 4),
          Text(
            amount,
            style: TextStyle(
              fontSize: dense ? 15 : 20,
              fontWeight: FontWeight.w700,
              color: highlight ? PosSaleUi.gold : PosSaleUi.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
