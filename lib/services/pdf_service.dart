import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../core/models/shop_settings.dart';
import 'hive_service.dart';

class PdfService {
  static final _fmt = NumberFormat('#,##,##0.00', 'en_IN');
  static final _dateFmt = DateFormat('dd MMM yyyy, hh:mm a');

  /// Build a professional A4 invoice PDF
  static Future<Uint8List> buildInvoicePdf(
      Map<String, dynamic> invoice) async {
    final ShopSettings settings = HiveService.getShopSettings();
    final pdf = pw.Document();

    final shopName =
        settings.shopName.isNotEmpty ? settings.shopName : 'WinTech Spark+';
    final shopLocation = settings.location;

    // Parse items
    final List items = (invoice['items'] as List?) ?? [];
    final double subtotal = (invoice['subtotal'] ?? 0).toDouble();
    final double gstAmount = (invoice['gstAmount'] ?? 0).toDouble();
    final double total = (invoice['total'] ?? 0).toDouble();
    final double paidAmount = (invoice['paidAmount'] ?? 0).toDouble();
    final double balance = total - paidAmount;

    final invoiceDate = DateTime.tryParse(invoice['date'] ?? '') ?? DateTime.now();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        shopName,
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      if (shopLocation.isNotEmpty)
                        pw.Text(
                          shopLocation,
                          style: const pw.TextStyle(
                              fontSize: 10, color: PdfColors.grey700),
                        ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: pw.BoxDecoration(
                          color: const PdfColor.fromInt(0xFF1A73E8),
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Text(
                          'INVOICE',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.Divider(height: 32, color: PdfColors.grey300),

              // ── Invoice Meta ─────────────────────────────────────
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _metaRow('Invoice No', invoice['invoiceNumber'] ?? ''),
                      _metaRow('Date', _dateFmt.format(invoiceDate)),
                      if ((invoice['customerName'] ?? '').isNotEmpty)
                        _metaRow('Customer', invoice['customerName']),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      _statusBadge(invoice['paymentStatus'] ?? 'Pending'),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Mode: ${invoice['paymentMode'] ?? 'Cash'}',
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 24),

              // ── Items Table ───────────────────────────────────────
              pw.Table(
                border: pw.TableBorder(
                  horizontalInside: const pw.BorderSide(
                      color: PdfColors.grey200, width: 0.8),
                  bottom: const pw.BorderSide(
                      color: PdfColors.grey300, width: 1),
                ),
                columnWidths: {
                  0: const pw.FlexColumnWidth(4),
                  1: const pw.FlexColumnWidth(1.2),
                  2: const pw.FlexColumnWidth(1.8),
                  3: const pw.FlexColumnWidth(1.2),
                  4: const pw.FlexColumnWidth(2),
                },
                children: [
                  // Header row
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFFF5F5F5)),
                    children: [
                      _tableHeader('Item'),
                      _tableHeader('Qty'),
                      _tableHeader('Rate (₹)'),
                      _tableHeader('GST%'),
                      _tableHeader('Total (₹)'),
                    ],
                  ),
                  // Item rows
                  ...items.map((item) {
                    return pw.TableRow(
                      children: [
                        _tableCell(item['productName'] ?? ''),
                        _tableCell('${item['quantity'] ?? 1}'),
                        _tableCell(_fmt.format((item['price'] ?? 0).toDouble())),
                        _tableCell(
                            '${(item['gstPercentage'] ?? 0).toStringAsFixed(0)}%'),
                        _tableCell(_fmt.format((item['total'] ?? 0).toDouble())),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 24),

              // ── Totals ────────────────────────────────────────────
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Container(
                  width: 240,
                  child: pw.Column(
                    children: [
                      _totalRow('Subtotal', '₹${_fmt.format(subtotal)}'),
                      _totalRow('GST Amount', '₹${_fmt.format(gstAmount)}'),
                      pw.Divider(color: PdfColors.grey300),
                      _totalRow(
                        'Total',
                        '₹${_fmt.format(total)}',
                        bold: true,
                        fontSize: 14,
                      ),
                      if (paidAmount > 0 && paidAmount < total) ...[
                        _totalRow('Paid',
                            '₹${_fmt.format(paidAmount)}',
                            color: PdfColors.green700),
                        _totalRow('Balance Due',
                            '₹${_fmt.format(balance)}',
                            bold: true,
                            color: PdfColors.red700),
                      ],
                    ],
                  ),
                ),
              ),

              pw.Spacer(),

              // ── Footer ────────────────────────────────────────────
              pw.Divider(color: PdfColors.grey300),
              pw.Center(
                child: pw.Text(
                  'Thank you for your business! — $shopName',
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey600),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  // ── Print directly ─────────────────────────────────────────────────────────
  static Future<void> printInvoice(Map<String, dynamic> invoice) async {
    final bytes = await buildInvoicePdf(invoice);
    await Printing.layoutPdf(
      onLayout: (_) => bytes,
      name: 'Invoice_${invoice['invoiceNumber'] ?? ''}',
    );
  }

  // ── Share / Download ───────────────────────────────────────────────────────
  static Future<void> shareInvoice(Map<String, dynamic> invoice) async {
    final bytes = await buildInvoicePdf(invoice);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Invoice_${invoice['invoiceNumber'] ?? ''}.pdf',
    );
  }

  // ── Thermal Receipt PDF (2 Inch / 58mm & 3 Inch / 80mm) ────────────────────
  static Future<Uint8List> buildThermalReceiptPdf({
    required Map<String, dynamic> invoice,
    required bool is3Inch,
    Map<String, dynamic>? companyProfile,
  }) async {
    final settings = HiveService.getShopSettings();
    final shopName = companyProfile?['companyName'] ??
        (settings.shopName.isNotEmpty ? settings.shopName : 'WinTech Spark+');
    final shopAddress = companyProfile?['address'] ?? settings.location;
    final shopPhone = companyProfile?['contact'] ?? '';
    final gstNumber = companyProfile?['gstNumber'] ?? '';

    final List items = (invoice['items'] as List?) ?? [];
    final double subtotal = (invoice['subtotal'] ?? 0).toDouble();
    final double gstAmount = (invoice['gstAmount'] ?? 0).toDouble();
    final double total = (invoice['total'] ?? 0).toDouble();
    final double paidAmount =
        (invoice['paidAmount'] ?? invoice['amountPaid'] ?? 0).toDouble();
    final status = (invoice['paymentStatus'] ?? invoice['status'] ?? 'Paid')
        .toString()
        .toUpperCase();
    final paymentMode = invoice['paymentMode'] ?? 'Cash';
    final invoiceDate =
        DateTime.tryParse(invoice['date'] ?? '') ?? DateTime.now();
    final customerName = invoice['customerName'] ?? '';
    final customerMobile = invoice['customerMobile'] ?? '';

    final pdf = pw.Document();
    final double rollWidth =
        is3Inch ? (80 * PdfPageFormat.mm) : (58 * PdfPageFormat.mm);
    final double margin =
        is3Inch ? (3 * PdfPageFormat.mm) : (2 * PdfPageFormat.mm);

    pdf.addPage(
      pw.Page(
        pageFormat:
            PdfPageFormat(rollWidth, double.infinity, marginAll: margin),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Header
              pw.Text(
                shopName.toUpperCase(),
                textAlign: pw.TextAlign.center,
                style:
                    pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
              if (shopAddress.isNotEmpty)
                pw.Text(shopAddress,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 8)),
              if (shopPhone.isNotEmpty)
                pw.Text('Ph: $shopPhone',
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 8)),
              if (gstNumber.isNotEmpty)
                pw.Text('GSTIN: $gstNumber',
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 3),

              pw.Container(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(width: 0.8),
                    bottom: pw.BorderSide(width: 0.8),
                  ),
                ),
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Text(
                  'TAX INVOICE',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 3),

              // Invoice Meta
              _thermalMetaRow('Invoice #:', invoice['invoiceNumber'] ?? ''),
              _thermalMetaRow('Date:', _dateFmt.format(invoiceDate)),
              if (customerName.isNotEmpty)
                _thermalMetaRow('Customer:', customerName),
              if (customerMobile.isNotEmpty)
                _thermalMetaRow('Phone:', customerMobile.toString()),

              _thermalDashedDivider(),

              // Items Header
              pw.Row(
                children: [
                  pw.Expanded(
                      flex: 5,
                      child: pw.Text('Item',
                          style: pw.TextStyle(
                              fontSize: 8, fontWeight: pw.FontWeight.bold))),
                  pw.Expanded(
                      flex: 2,
                      child: pw.Text('Qty',
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                              fontSize: 8, fontWeight: pw.FontWeight.bold))),
                  pw.Expanded(
                      flex: 2,
                      child: pw.Text('Rate',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                              fontSize: 8, fontWeight: pw.FontWeight.bold))),
                  pw.Expanded(
                      flex: 3,
                      child: pw.Text('Amt',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                              fontSize: 8, fontWeight: pw.FontWeight.bold))),
                ],
              ),
              _thermalDashedDivider(),

              // Items List
              ...items.map((item) {
                final double price = (item['price'] ?? 0).toDouble();
                final double itemTotal = (item['total'] ?? 0).toDouble();
                final int qty = (item['quantity'] ?? 1) is int
                    ? item['quantity']
                    : (item['quantity'] ?? 1).toInt();
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        flex: 5,
                        child: pw.Text(item['productName'] ?? '',
                            style: const pw.TextStyle(fontSize: 8)),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text('$qty',
                            textAlign: pw.TextAlign.center,
                            style: const pw.TextStyle(fontSize: 8)),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text(_fmt.format(price),
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(fontSize: 8)),
                      ),
                      pw.Expanded(
                        flex: 3,
                        child: pw.Text(_fmt.format(itemTotal),
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(
                                fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      ),
                    ],
                  ),
                );
              }),

              _thermalDashedDivider(),

              // Totals
              _thermalTotalRow('Subtotal:', '₹${_fmt.format(subtotal)}'),
              _thermalTotalRow('GST:', '₹${_fmt.format(gstAmount)}'),
              pw.Container(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(width: 0.8),
                    bottom: pw.BorderSide(width: 0.8),
                  ),
                ),
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                margin: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('TOTAL:',
                        style: pw.TextStyle(
                            fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.Text('₹${_fmt.format(total)}',
                        style: pw.TextStyle(
                            fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
              _thermalTotalRow('Mode:', paymentMode),
              _thermalTotalRow('Status:', status),
              if (paidAmount > 0 && paidAmount < total) ...[
                _thermalTotalRow('Paid:', '₹${_fmt.format(paidAmount)}'),
                _thermalTotalRow('Balance:', '₹${_fmt.format(total - paidAmount)}'),
              ],

              _thermalDashedDivider(),

              // Footer
              pw.SizedBox(height: 3),
              pw.Text('Thank You for Your Business!',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      fontSize: 8, fontWeight: pw.FontWeight.bold)),
              pw.Text('Please Visit Again',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 7)),
              pw.SizedBox(height: 12),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Print thermal receipt via system print spooler
  static Future<void> printThermalReceipt(
    Map<String, dynamic> invoice, {
    bool is3Inch = true,
    Map<String, dynamic>? companyProfile,
  }) async {
    final bytes = await buildThermalReceiptPdf(
      invoice: invoice,
      is3Inch: is3Inch,
      companyProfile: companyProfile,
    );
    final double rollWidth =
        is3Inch ? (80 * PdfPageFormat.mm) : (58 * PdfPageFormat.mm);
    await Printing.layoutPdf(
      onLayout: (_) => bytes,
      name: 'Receipt_${invoice['invoiceNumber'] ?? ''}',
      format: PdfPageFormat(rollWidth, double.infinity,
          marginAll: is3Inch ? 3 * PdfPageFormat.mm : 2 * PdfPageFormat.mm),
    );
  }

  /// Share thermal receipt PDF
  static Future<void> shareThermalReceipt(
    Map<String, dynamic> invoice, {
    bool is3Inch = true,
    Map<String, dynamic>? companyProfile,
  }) async {
    final bytes = await buildThermalReceiptPdf(
      invoice: invoice,
      is3Inch: is3Inch,
      companyProfile: companyProfile,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Receipt_${invoice['invoiceNumber'] ?? ''}.pdf',
    );
  }

  static pw.Widget _thermalDashedDivider() {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Text(
        '------------------------------------------------',
        maxLines: 1,
        style: const pw.TextStyle(fontSize: 6, color: PdfColors.black),
      ),
    );
  }

  static pw.Widget _thermalMetaRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 0.8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
          pw.Text(value,
              style:
                  pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  static pw.Widget _thermalTotalRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 0.8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
          pw.Text(value,
              style:
                  pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  static pw.Widget _metaRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        children: [
          pw.Text('$label: ',
              style: const pw.TextStyle(
                  fontSize: 10, color: PdfColors.grey700)),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  static pw.Widget _statusBadge(String status) {
    final color = status == 'Paid'
        ? PdfColors.green700
        : status == 'Partial'
            ? PdfColors.orange700
            : PdfColors.red700;
    return pw.Container(
      padding:
          const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: color),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        status.toUpperCase(),
        style: pw.TextStyle(
            fontSize: 9, color: color, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget _tableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey700),
      ),
    );
  }

  static pw.Widget _tableCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 9)),
    );
  }

  static pw.Widget _totalRow(
    String label,
    String value, {
    bool bold = false,
    double fontSize = 11,
    PdfColor? color,
  }) {
    final style = bold
        ? pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: fontSize,
            color: color)
        : pw.TextStyle(fontSize: fontSize, color: color ?? PdfColors.grey800);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text(value, style: style),
        ],
      ),
    );
  }
}
