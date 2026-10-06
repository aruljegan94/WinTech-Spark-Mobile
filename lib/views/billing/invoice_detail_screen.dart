import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/hive_service.dart';
import '../../services/invoice_service.dart';
import '../../services/pdf_service.dart';
import 'widgets/thermal_print_dialog.dart';

class InvoiceDetailScreen extends StatelessWidget {
  final Map<String, dynamic> invoice;
  const InvoiceDetailScreen({super.key, required this.invoice});

  @override
  Widget build(BuildContext context) {
    final settings = HiveService.getShopSettings();
    final shopName =
        settings.shopName.isNotEmpty ? settings.shopName : 'WinTech Spark+';
    final shopLocation = settings.location;
    final fmt = NumberFormat('#,##,##0.00', 'en_IN');
    final dateFmt = DateFormat('dd MMM yyyy, hh:mm a');

    final List items = (invoice['items'] as List?) ?? [];
    final double subtotal = (invoice['subtotal'] ?? 0).toDouble();
    final double gstAmount = (invoice['gstAmount'] ?? 0).toDouble();
    final double total = (invoice['total'] ?? 0).toDouble();
    final double paidAmount =
        (invoice['paidAmount'] ?? invoice['amountPaid'] ?? 0).toDouble();
    final double balance = total - paidAmount;
    final status = invoice['paymentStatus'] ?? invoice['status'] ?? 'Pending';
    final invoiceDate =
        DateTime.tryParse(invoice['date'] ?? '') ?? DateTime.now();

    Color statusColor;
    switch (status) {
      case 'Paid':
        statusColor = Colors.green;
        break;
      case 'Partial':
        statusColor = Colors.orange;
        break;
      default:
        statusColor = Colors.redAccent;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: Text(invoice['invoiceNumber'] ?? 'Invoice'),
        actions: [
          IconButton(
            onPressed: () =>
                ThermalPrintDialog.show(context, invoice: invoice),
            icon: const Icon(Icons.receipt_long_rounded,
                color: Color(0xFF1A73E8)),
            tooltip: 'Thermal Receipt (2"/3")',
          ),
          IconButton(
            onPressed: () => InvoiceService.shareInvoiceViaWhatsApp(invoice),
            icon: const Icon(Icons.chat_rounded, color: Color(0xFF25D366)),
            tooltip: 'WhatsApp Bill',
          ),
          IconButton(
            onPressed: () => PdfService.shareInvoice(invoice),
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Download PDF',
          ),
          IconButton(
            onPressed: () => PdfService.printInvoice(invoice),
            icon: const Icon(Icons.print_rounded),
            tooltip: 'Print',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Shop Header Card ───────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shopName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (shopLocation.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            shopLocation,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.4), width: 1),
                    ),
                    child: const Text(
                      'INVOICE',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Invoice Meta ──────────────────────────────────────
            _InfoCard(
              child: Column(
                children: [
                  _metaRow('Invoice No', invoice['invoiceNumber'] ?? '',
                      bold: true),
                  const Divider(height: 20),
                  _metaRow(
                      'Date', dateFmt.format(invoiceDate)),
                  _metaRow(
                      'Customer',
                      (invoice['customerName']?.isNotEmpty == true)
                          ? invoice['customerName']
                          : 'Walk-in Customer'),
                  if (invoice['customerMobile'] != null &&
                      invoice['customerMobile'].toString().trim().isNotEmpty)
                    _metaRow('Mobile', invoice['customerMobile'].toString()),
                  if (invoice['customerAddress'] != null &&
                      invoice['customerAddress'].toString().trim().isNotEmpty)
                    _metaRow('Address', invoice['customerAddress'].toString()),
                  _metaRow('Payment Mode',
                      invoice['paymentMode'] ?? 'Cash'),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Status',
                          style: TextStyle(
                              color: Colors.grey, fontSize: 13)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: statusColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Items Table ───────────────────────────────────────
            _InfoCard(
              title: 'Items',
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurfaceElevated
                          : AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(width: 10),
                        Expanded(
                            flex: 4,
                            child: Text('Item',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.grey))),
                        Expanded(
                            child: Text('Qty',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.grey))),
                        Expanded(
                            flex: 2,
                            child: Text('Rate',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.grey))),
                        Expanded(
                            flex: 2,
                            child: Text('Total',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.grey))),
                        SizedBox(width: 10),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...items.asMap().entries.map((entry) {
                    final i = entry.value;
                    final isLast = entry.key == items.length - 1;
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                          child: Row(
                            children: [
                              Expanded(
                                  flex: 4,
                                  child: Text(i['productName'] ?? '',
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600))),
                              Expanded(
                                  child: Text('${i['quantity'] ?? 1}',
                                      style: const TextStyle(fontSize: 13))),
                              Expanded(
                                  flex: 2,
                                  child: Text(
                                      '₹${fmt.format((i['price'] ?? 0).toDouble())}',
                                      style: const TextStyle(fontSize: 13))),
                              Expanded(
                                flex: 2,
                                child: Text(
                                    '₹${fmt.format((i['total'] ?? 0).toDouble())}',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                        if (!isLast)
                          Divider(height: 1, color: Colors.grey.shade100),
                      ],
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Totals ────────────────────────────────────────────
            _InfoCard(
              title: 'Summary',
              child: Column(
                children: [
                  _summaryRow('Subtotal', '₹${fmt.format(subtotal)}'),
                  const SizedBox(height: 8),
                  _summaryRow('GST Amount', '₹${fmt.format(gstAmount)}',
                      secondary: true),
                  const Divider(height: 20),
                  _summaryRow('Total', '₹${fmt.format(total)}',
                      bold: true, fontSize: 18),
                  if (paidAmount > 0) ...[
                    const SizedBox(height: 8),
                    _summaryRow('Paid', '₹${fmt.format(paidAmount)}',
                        color: Colors.green),
                    if (balance > 0.01) ...[
                      const SizedBox(height: 8),
                      _summaryRow(
                          'Balance Due', '₹${fmt.format(balance)}',
                          color: Colors.redAccent,
                          bold: true),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: total > 0 ? paidAmount / total : 0,
                          backgroundColor: Colors.grey.shade200,
                          color: Colors.orange,
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 32),

            // ── Action buttons ────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        ThermalPrintDialog.show(context, invoice: invoice),
                    icon: const Icon(Icons.receipt_long_rounded, size: 18),
                    label: const Text(
                      'Thermal Print (2"/3")',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFF1A73E8),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => PdfService.printInvoice(invoice),
                    icon: const Icon(Icons.print_rounded, size: 18),
                    label: const Text(
                      'A4 Print / PDF',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.primary),
                      foregroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () =>
                    InvoiceService.shareInvoiceViaWhatsApp(invoice),
                icon: const Icon(Icons.chat_rounded, color: Colors.white, size: 18),
                label: const Text(
                  'Share on WhatsApp',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
                  const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      bold ? FontWeight.w800 : FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value,
      {bool bold = false,
      bool secondary = false,
      Color? color,
      double fontSize = 14}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: fontSize,
                color: secondary ? Colors.grey : Colors.black87,
                fontWeight:
                    bold ? FontWeight.w900 : FontWeight.normal)),
        Text(value,
            style: TextStyle(
                fontSize: fontSize,
                fontWeight:
                    bold ? FontWeight.w900 : FontWeight.w600,
                color: color ?? AppColors.onSurface)),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final Widget child;
  final String? title;

  const _InfoCard({required this.child, this.title});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? AppColors.darkBorder
              : AppColors.outlineVariant.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.025),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: isDark
                    ? AppColors.darkText50
                    : AppColors.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}
