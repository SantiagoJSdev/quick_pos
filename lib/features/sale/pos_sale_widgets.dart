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
    required this.rateHeadline,
    required this.rateSub,
    required this.onRefresh,
    required this.onSync,
    this.syncBusy = false,
    this.showSyncDot = false,
    this.onBack,
  });

  final String rateHeadline;
  final String rateSub;
  final VoidCallback onRefresh;
  final VoidCallback onSync;
  final bool syncBusy;
  final bool showSyncDot;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
      decoration: const BoxDecoration(
        color: PosSaleUi.surface,
        border: Border(bottom: BorderSide(color: PosSaleUi.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onBack != null) ...[
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: onBack,
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: PosSaleUi.text,
              ),
              tooltip: 'Volver',
            ),
            const SizedBox(width: 4),
          ],
          const QuickMarketWordmark(),
          const Spacer(),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: PosSaleUi.goldDim,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0x33E8C34A),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: PosSaleUi.gold,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          rateHeadline,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: PosSaleUi.gold,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                          maxLines: 2,
                          textAlign: TextAlign.end,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  rateSub,
                  style: const TextStyle(
                    fontSize: 9,
                    color: PosSaleUi.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, color: PosSaleUi.textMuted),
            tooltip: 'Recargar catálogo',
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                onPressed: syncBusy ? null : onSync,
                icon: syncBusy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: PosSaleUi.primary,
                        ),
                      )
                    : const Icon(Icons.cloud_sync_outlined,
                        color: PosSaleUi.textMuted),
                tooltip: 'Sincronizar',
              ),
              if (showSyncDot)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: PosSaleUi.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: PosSaleUi.surface, width: 1.5),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                      const Icon(Icons.search,
                          size: 18, color: PosSaleUi.textMuted),
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
                          icon: const Icon(Icons.close,
                              size: 18, color: PosSaleUi.textMuted),
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
                  child: const Icon(Icons.qr_code_scanner,
                      color: PosSaleUi.primary, size: 22),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: PosSaleUi.surface3,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: () {
                  final img = imageUrl?.trim();
                  if (img == null || img.isEmpty) {
                    return Center(
                      child: Text(
                        _posLeadingInitial(line.name),
                        style: const TextStyle(
                          fontSize: 18,
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
                        _posLeadingInitial(line.name),
                        style: const TextStyle(
                          fontSize: 18,
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
                    line.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: PosSaleUi.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        fontSize: 11,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                      children: [
                        TextSpan(
                          text: '$unitFunctional $functionalCode',
                          style: const TextStyle(
                            color: PosSaleUi.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const TextSpan(
                          text: ' · ',
                          style: TextStyle(color: PosSaleUi.textMuted),
                        ),
                        TextSpan(
                          text:
                              '${line.documentUnitPrice} $documentCode',
                          style: const TextStyle(color: PosSaleUi.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _QtyPill(
              quantity: line.quantity,
              onMinus: onMinus,
              onPlus: onPlus,
              onQtyTap: onQtyTap,
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$lineTotalFunctional $functionalCode',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: PosSaleUi.text,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  '${line.lineTotalDocument} $documentCode',
                  style: const TextStyle(
                    fontSize: 11,
                    color: PosSaleUi.textMuted,
                    fontFeatures: [FontFeature.tabularFigures()],
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

class _QtyPill extends StatelessWidget {
  const _QtyPill({
    required this.quantity,
    required this.onMinus,
    required this.onPlus,
    required this.onQtyTap,
  });

  final String quantity;
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
                quantity,
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
    required this.subtotalLabel,
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
    this.mixedPaymentAppliedLabel,
    this.mixedPaymentRemainingLabel,
    this.canChargeWithPayments = true,
  });

  final String functionalCode;
  final String documentCode;
  final String functionalTotalLabel;
  final String documentTotalLabel;
  final String totalFunctional;
  final String totalDocument;
  final String subtotalLabel;
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
  final String? mixedPaymentAppliedLabel;
  final String? mixedPaymentRemainingLabel;
  final bool canChargeWithPayments;

  @override
  Widget build(BuildContext context) {
    final feedback = cartFeedback?.trim();
    final err = cartFeedbackIsError;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: err
                        ? PosSaleUi.error.withValues(alpha: 0.45)
                        : PosSaleUi.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        err
                            ? Icons.error_outline_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 18,
                        color: err ? PosSaleUi.error : PosSaleUi.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          feedback,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.25,
                            color: err ? PosSaleUi.error : PosSaleUi.text,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (heldTicketsCount > 0 && onOpenHeldTickets != null) ...[
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onOpenHeldTickets,
                  icon: const Icon(Icons.inventory_2_outlined,
                      size: 18, color: PosSaleUi.primary),
                  label: Text(
                    'Guardados ($heldTicketsCount)',
                    style: const TextStyle(
                      color: PosSaleUi.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
            if (currencySelector != null) ...[
              currencySelector!,
              const SizedBox(height: 8),
            ],
            if (cartNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Subtotal',
                    style: TextStyle(fontSize: 11, color: PosSaleUi.textMuted),
                  ),
                  Text(
                    subtotalLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      color: PosSaleUi.text,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Ítems',
                    style: TextStyle(fontSize: 11, color: PosSaleUi.textMuted),
                  ),
                  Text(
                    itemsSummary,
                    style: const TextStyle(
                      fontSize: 11,
                      color: PosSaleUi.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: PosSaleUi.surface3,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: PosSaleUi.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _TotalBlock(
                      label: functionalTotalLabel,
                      amount: totalFunctional,
                      highlight: false,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 48,
                    color: PosSaleUi.divider,
                  ),
                  Expanded(
                    child: _TotalBlock(
                      label: documentTotalLabel,
                      amount: totalDocument,
                      highlight: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (onOpenMixedPayment != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: PosSaleUi.surface3,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: PosSaleUi.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (mixedPaymentAppliedLabel != null)
                            Text(
                              mixedPaymentAppliedLabel!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: PosSaleUi.text,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (mixedPaymentRemainingLabel != null) ...[
                            const SizedBox(height: 2),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: (canChargeWithPayments
                                        ? PosSaleUi.success
                                        : PosSaleUi.error)
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: (canChargeWithPayments
                                          ? PosSaleUi.success
                                          : PosSaleUi.error)
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      canChargeWithPayments
                                          ? Icons.check_circle_outline
                                          : Icons.error_outline,
                                      size: 13,
                                      color: canChargeWithPayments
                                          ? PosSaleUi.success
                                          : PosSaleUi.error,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        mixedPaymentRemainingLabel!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: canChargeWithPayments
                                              ? PosSaleUi.success
                                              : PosSaleUi.error,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: onOpenMixedPayment,
                      icon: const Icon(Icons.attach_money, size: 16),
                      label: const Text('Pago USD'),
                    ),
                    if (onClearMixedPayment != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: onClearMixedPayment,
                        tooltip: 'Limpiar pago USD',
                        icon: const Icon(Icons.clear, size: 18),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: cartNotEmpty ? onClear : null,
                  style: IconButton.styleFrom(
                    backgroundColor: PosSaleUi.surface3,
                    foregroundColor: PosSaleUi.textMuted,
                  ),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Vaciar ticket',
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: onDiscount,
                  style: IconButton.styleFrom(
                    backgroundColor: PosSaleUi.surface3,
                    foregroundColor: PosSaleUi.textFaint,
                  ),
                  icon: const Icon(Icons.percent_outlined),
                  tooltip: 'Descuentos — próximamente',
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: (cartNotEmpty && onPutOnHold != null)
                      ? onPutOnHold
                      : null,
                  style: IconButton.styleFrom(
                    backgroundColor: PosSaleUi.surface3,
                    foregroundColor: PosSaleUi.primary,
                  ),
                  icon: const Icon(Icons.pause_circle_outline),
                  tooltip: 'Poner ticket en espera',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: (cartNotEmpty &&
                            canChargeWithPayments &&
                            !chargeBusy)
                        ? onCharge
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: PosSaleUi.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: PosSaleUi.surface4,
                      disabledForegroundColor: PosSaleUi.textFaint,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: cartNotEmpty ? 4 : 0,
                      shadowColor: PosSaleUi.primary.withValues(alpha: 0.35),
                    ),
                    child: chargeBusy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.payments_outlined, size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                'Cobrar',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
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
  });

  final String label;
  final String amount;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: PosSaleUi.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            amount,
            style: TextStyle(
              fontSize: 20,
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
