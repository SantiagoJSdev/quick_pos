/// Etiquetas legibles para códigos de método de pago del API.
String paymentMethodLabel(String method) {
  switch (method.trim().toUpperCase()) {
    case 'USD_CASH':
      return 'Efectivo USD';
    case 'VES_CASH':
      return 'Efectivo VES';
    case 'CARD':
      return 'Tarjeta';
    case 'TRANSFER':
      return 'Transferencia';
    case 'MOBILE_PAYMENT':
      return 'Pago móvil';
    case 'ZELLE':
      return 'Zelle';
    case 'OTHER':
      return 'Otro';
    default:
      if (method.isEmpty) return '—';
      return method.replaceAll('_', ' ');
  }
}
