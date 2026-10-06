import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_universal_printer/pos_universal_printer.dart' hide Size;
import 'package:printing/printing.dart';
import '../../../core/theme.dart';
import '../../../services/hive_service.dart';
import '../../../services/invoice_service.dart';
import '../../../services/pdf_service.dart';
import '../../../services/printer_service.dart';

class ThermalPrintDialog extends StatefulWidget {
  final Map<String, dynamic> invoice;

  const ThermalPrintDialog({
    super.key,
    required this.invoice,
  });

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> invoice,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ThermalPrintDialog(invoice: invoice),
    );
  }

  @override
  State<ThermalPrintDialog> createState() => _ThermalPrintDialogState();
}

class _ThermalPrintDialogState extends State<ThermalPrintDialog> {
  late String _paperWidth; // '58mm' (2 Inch) or '80mm' (3 Inch)
  Map<String, dynamic>? _companyProfile;
  bool _isPrinting = false;

  final ThermalPrinterService _printerService = ThermalPrinterService();
  final NumberFormat _fmt = NumberFormat('#,##,##0.00', 'en_IN');
  final DateFormat _dateFmt = DateFormat('dd-MMM-yyyy hh:mm a');

  @override
  void initState() {
    super.initState();
    _paperWidth = HiveService.getPreferredPaperSize();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await InvoiceService.getDefaultCompanyProfile();
      if (mounted) {
        setState(() {
          _companyProfile = profile;
        });
      }
    } catch (_) {}
  }

  void _setPaperWidth(String width) {
    setState(() => _paperWidth = width);
    HiveService.setPreferredPaperSize(width);
  }

  @override
  Widget build(BuildContext context) {
    final is3Inch = _paperWidth == '80mm';
    final settings = HiveService.getShopSettings();
    final shopName = _companyProfile?['companyName'] ??
        (settings.shopName.isNotEmpty ? settings.shopName : 'WinTech Spark+');
    final address = _companyProfile?['address'] ?? settings.location;
    final contact = _companyProfile?['contact'] ?? '';
    final gstNumber = _companyProfile?['gstNumber'] ?? '';

    final List items = (widget.invoice['items'] as List?) ?? [];
    final double subtotal = (widget.invoice['subtotal'] ?? 0).toDouble();
    final double gstAmount = (widget.invoice['gstAmount'] ?? 0).toDouble();
    final double total = (widget.invoice['total'] ?? 0).toDouble();
    final double paidAmount = (widget.invoice['paidAmount'] ??
            widget.invoice['amountPaid'] ??
            0)
        .toDouble();
    final double balance = (total - paidAmount).clamp(0.0, total);
    final status = (widget.invoice['paymentStatus'] ??
            widget.invoice['status'] ??
            'Paid')
        .toString();
    final paymentMode = widget.invoice['paymentMode'] ?? 'Cash';
    final invoiceDate =
        DateTime.tryParse(widget.invoice['date'] ?? '') ?? DateTime.now();
    final customerName = widget.invoice['customerName'] ?? '';
    final customerMobile = widget.invoice['customerMobile'] ?? '';

    final isPrinterReady = _printerService.isPrinterReady;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // ── Header Bar ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.print_rounded,
                      color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Thermal Receipt Print',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${widget.invoice['invoiceNumber'] ?? ''} • 2" & 3" Supported',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // ── Paper Width Selector ─────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: AppColors.surfaceContainerLow,
            child: Row(
              children: [
                const Text(
                  'Paper Size:',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _PaperSizeButton(
                    label: '58mm (2 Inch)',
                    selected: _paperWidth == '58mm',
                    onTap: () => _setPaperWidth('58mm'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PaperSizeButton(
                    label: '80mm (3 Inch)',
                    selected: _paperWidth == '80mm',
                    onTap: () => _setPaperWidth('80mm'),
                  ),
                ),
              ],
            ),
          ),

          // ── Thermal Printer Connection Status Banner ─────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: isPrinterReady
                  ? Colors.green.shade50
                  : Colors.amber.shade50,
              border: Border(
                bottom: BorderSide(
                  color: isPrinterReady
                      ? Colors.green.shade200
                      : Colors.amber.shade200,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _printerService.hasSystemPrinter
                      ? Icons.print_rounded
                      : (_printerService.isConnected
                          ? Icons.bluetooth_connected_rounded
                          : Icons.print_outlined),
                  size: 18,
                  color: isPrinterReady
                      ? Colors.green.shade700
                      : Colors.amber.shade800,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _printerService.hasSystemPrinter
                        ? 'Printer: ${_printerService.selectedSystemPrinter!.name}'
                        : (_printerService.isConnected
                            ? 'Bluetooth: ${_printerService.connectedDevice!.name}'
                            : (_printerService.isDesktopPlatform
                                ? 'Thermal Printer: Not selected'
                                : 'No Printer Connected')),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isPrinterReady
                          ? Colors.green.shade800
                          : Colors.amber.shade900,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: _openPrinterPicker,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      isPrinterReady ? 'Change' : 'Select Printer',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isPrinterReady
                            ? Colors.green.shade800
                            : AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Thermal Paper Preview ────────────────────────────────────
          Expanded(
            child: Container(
              color: Colors.grey.shade100,
              width: double.infinity,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                child: Center(
                  child: Container(
                    width: is3Inch ? 300 : 230,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.black, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: DefaultTextStyle(
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.black,
                        fontSize: 11,
                        height: 1.25,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Shop Header
                          Text(
                            shopName.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                          if (address.isNotEmpty)
                            Text(address, textAlign: TextAlign.center),
                          if (contact.isNotEmpty)
                            Text('Ph: $contact', textAlign: TextAlign.center),
                          if (gstNumber.isNotEmpty)
                            Text('GSTIN: $gstNumber',
                                textAlign: TextAlign.center),
                          const SizedBox(height: 4),

                          // Tax Invoice Banner
                          Container(
                            decoration: const BoxDecoration(
                              border: Border(
                                top: BorderSide(color: Colors.black),
                                bottom: BorderSide(color: Colors.black),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: const Text(
                              'TAX INVOICE',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 4),

                          // Metadata
                          _previewRow('Invoice #:',
                              widget.invoice['invoiceNumber'] ?? ''),
                          _previewRow('Date:', _dateFmt.format(invoiceDate)),
                          if (customerName.isNotEmpty)
                            _previewRow('Customer:', customerName),
                          if (customerMobile.isNotEmpty)
                            _previewRow('Phone:', customerMobile.toString()),

                          _previewDashedDivider(is3Inch),

                          // Items Table Header
                          const Row(
                            children: [
                              Expanded(
                                  flex: 5,
                                  child: Text('Item',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold))),
                              Expanded(
                                  flex: 2,
                                  child: Text('Qty',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold))),
                              Expanded(
                                  flex: 2,
                                  child: Text('Rate',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold))),
                              Expanded(
                                  flex: 3,
                                  child: Text('Amt',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold))),
                            ],
                          ),

                          _previewDashedDivider(is3Inch),

                          // Items List
                          ...items.map((item) {
                            final name = (item['productName'] ?? '').toString();
                            final qty = item['quantity'] ?? 1;
                            final price = (item['price'] ?? 0).toDouble();
                            final itemTotal = (item['total'] ?? 0).toDouble();
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 1.5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      '$qty',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      _fmt.format(price),
                                      textAlign: TextAlign.right,
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      _fmt.format(itemTotal),
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),

                          _previewDashedDivider(is3Inch),

                          // Totals
                          _previewRow('Subtotal:', 'Rs. ${_fmt.format(subtotal)}'),
                          _previewRow('GST:', 'Rs. ${_fmt.format(gstAmount)}'),
                          Container(
                            decoration: const BoxDecoration(
                              border: Border(
                                top: BorderSide(color: Colors.black),
                                bottom: BorderSide(color: Colors.black),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('TOTAL:',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12)),
                                Text('Rs. ${_fmt.format(total)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                          _previewRow('Payment Mode:', paymentMode),
                          _previewRow('Payment Status:', status.toUpperCase()),
                          if (paidAmount > 0 && balance > 0.01) ...[
                            _previewRow('Amount Paid:', 'Rs. ${_fmt.format(paidAmount)}'),
                            _previewRow('Balance Due:', 'Rs. ${_fmt.format(balance)}', bold: true),
                          ],

                          _previewDashedDivider(is3Inch),

                          // Footer
                          const SizedBox(height: 4),
                          const Text(
                            'Thank You for Your Business!',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Text('Please Visit Again',
                              textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Bottom Action Controls ───────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                // Share Thermal Receipt
                IconButton.outlined(
                  onPressed: () => PdfService.shareThermalReceipt(
                    widget.invoice,
                    is3Inch: is3Inch,
                    companyProfile: _companyProfile,
                  ),
                  icon: const Icon(Icons.share_rounded),
                  tooltip: 'Share Receipt PDF',
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(width: 8),

                // System Print Dialog (Preview with exact roll dimensions)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => PdfService.printThermalReceipt(
                      widget.invoice,
                      is3Inch: is3Inch,
                      companyProfile: _companyProfile,
                    ),
                    icon: const Icon(Icons.preview_rounded, size: 18),
                    label: const Text('System Dialog'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.primary),
                      foregroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Direct Thermal Print Button (Instant Print, No Windows Dialog, Exact Roll Cut)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isPrinting ? null : _handleDirectPrint,
                    icon: _isPrinting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.print_rounded, size: 18),
                    label: Text(_isPrinting ? 'Printing…' : 'Direct Print'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFF1A73E8),
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Direct Thermal Printing Logic ───────────────────────────────────────────
  Future<void> _handleDirectPrint() async {
    final is3Inch = _paperWidth == '80mm';

    if (!_printerService.isPrinterReady) {
      // Prompt user to select or connect a printer first
      await _openPrinterPicker();
      if (!_printerService.isPrinterReady) return;
    }

    setState(() => _isPrinting = true);
    final success = await _printerService.printDirectInvoice(
      invoice: widget.invoice,
      is3Inch: is3Inch,
      companyProfile: _companyProfile,
    );

    if (mounted) {
      setState(() => _isPrinting = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Receipt sent directly to thermal printer!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Direct print failed. Opening system print preview...'),
            backgroundColor: Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Fallback to system spooler dialog with correct roll format
        await PdfService.printThermalReceipt(
          widget.invoice,
          is3Inch: is3Inch,
          companyProfile: _companyProfile,
        );
      }
    }
  }

  // ── Unified Printer Picker Sheet ────────────────────────────────────────────
  Future<void> _openPrinterPicker() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => UnifiedPrinterPicker(
        printerService: _printerService,
        onSelected: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }

  // ── Preview Helpers ─────────────────────────────────────────────────────────
  Widget _previewRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w900 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewDashedDivider(bool is3Inch) {
    final dashes = is3Inch
        ? '------------------------------------------------'
        : '--------------------------------';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        dashes,
        maxLines: 1,
        style: const TextStyle(color: Colors.black87),
      ),
    );
  }
}

// ── Paper Size Button ────────────────────────────────────────────────────────
class _PaperSizeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PaperSizeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (selected) ...[
              const Icon(Icons.check_rounded, color: Colors.white, size: 14),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Unified Printer Picker Modal (Windows / USB / Network & Bluetooth) ────────
class UnifiedPrinterPicker extends StatefulWidget {
  final ThermalPrinterService printerService;
  final VoidCallback onSelected;

  const UnifiedPrinterPicker({
    super.key,
    required this.printerService,
    required this.onSelected,
  });

  @override
  State<UnifiedPrinterPicker> createState() => _UnifiedPrinterPickerState();
}

class _UnifiedPrinterPickerState extends State<UnifiedPrinterPicker>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Printer> _systemPrinters = [];
  bool _loadingSystem = true;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    // Default to Windows/USB tab on desktop, otherwise Bluetooth if preferred
    final initialIndex = widget.printerService.isDesktopPlatform ? 0 : 0;
    _tabController = TabController(length: 2, vsync: this, initialIndex: initialIndex);
    _loadSystemPrinters();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSystemPrinters() async {
    setState(() => _loadingSystem = true);
    final list = await widget.printerService.getSystemPrinters();
    if (mounted) {
      setState(() {
        _systemPrinters = list;
        _loadingSystem = false;
      });
    }
  }

  bool _isThermalPrinter(String name) {
    final lower = name.toLowerCase();
    const keywords = [
      'pos',
      'thermal',
      'receipt',
      '80',
      '58',
      'xp-',
      'xprinter',
      'epson',
      'tvs',
      'rp',
      'zj',
      'bill',
      'sprt',
      'hoin',
    ];
    return keywords.any((kw) => lower.contains(kw));
  }

  Future<void> _selectSystemPrinter(Printer printer) async {
    await widget.printerService.setSystemPrinter(printer);
    widget.onSelected();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Selected "${printer.name}" as Thermal Printer'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _testPrintSystemPrinter(Printer printer) async {
    setState(() => _isTesting = true);
    final ok = await PdfService.directPrintTestReceipt(printer: printer);
    if (mounted) {
      setState(() => _isTesting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Test receipt sent to "${printer.name}"!'
                : 'Failed to send test receipt to "${printer.name}". Check cable & driver.',
          ),
          backgroundColor: ok ? Colors.green : Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeSystem = widget.printerService.selectedSystemPrinter;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.print_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Thermal Printer',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppColors.onSurface,
                      ),
                    ),
                    Text(
                      'Windows / USB Spooler & Bluetooth',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Tabs
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurfaceElevated
                  : AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              labelColor: Colors.white,
              unselectedLabelColor:
                  isDark ? Colors.white60 : Colors.grey.shade700,
              labelStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              tabs: const [
                Tab(
                  iconMargin: EdgeInsets.zero,
                  text: 'Windows / USB Printers',
                ),
                Tab(
                  iconMargin: EdgeInsets.zero,
                  text: 'Bluetooth Printers',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Tab views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: System / Windows Printers
                _buildSystemPrintersTab(isDark, activeSystem),

                // Tab 2: Bluetooth Printers
                BluetoothDevicePickerView(
                  printerService: widget.printerService,
                  onConnected: (dev) {
                    widget.onSelected();
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemPrintersTab(bool isDark, Printer? activeSystem) {
    if (_loadingSystem) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_systemPrinters.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.print_disabled_rounded,
                size: 44, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'No installed Windows printers found',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'Install your thermal printer driver (POS-80, XP-80, etc.) in Windows Settings.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loadSystemPrinters,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh Printers'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Found ${_systemPrinters.length} installed printers',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                ),
              ),
              InkWell(
                onTap: _loadSystemPrinters,
                child: const Row(
                  children: [
                    Icon(Icons.refresh_rounded,
                        size: 14, color: AppColors.primary),
                    SizedBox(width: 4),
                    Text(
                      'Refresh',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _systemPrinters.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final printer = _systemPrinters[index];
              final isSelected = activeSystem?.url == printer.url ||
                  (activeSystem?.name == printer.name);
              final isThermal = _isThermalPrinter(printer.name);

              return Container(
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : (isDark
                          ? AppColors.darkSurfaceElevated
                          : AppColors.surfaceContainerLow),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : (isDark
                            ? AppColors.darkBorder
                            : Colors.grey.shade200),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: CircleAvatar(
                    backgroundColor: isSelected
                        ? AppColors.primary
                        : (isThermal
                            ? Colors.green.shade100
                            : Colors.grey.shade200),
                    child: Icon(
                      Icons.print_rounded,
                      size: 20,
                      color: isSelected
                          ? Colors.white
                          : (isThermal
                              ? Colors.green.shade800
                              : Colors.grey.shade700),
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          printer.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isDark ? Colors.white : AppColors.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isThermal) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Thermal POS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    printer.isDefault
                        ? 'Windows Default Printer'
                        : (printer.model ?? 'System Printer'),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: _isTesting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.receipt_long_rounded, size: 18),
                        tooltip: 'Test Print',
                        onPressed: _isTesting
                            ? null
                            : () => _testPrintSystemPrinter(printer),
                      ),
                      const SizedBox(width: 4),
                      ElevatedButton(
                        onPressed: () => _selectSystemPrinter(printer),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isSelected
                              ? Colors.green
                              : AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          isSelected ? 'Selected' : 'Use',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Bluetooth Device Picker View ─────────────────────────────────────────────
class BluetoothDevicePickerView extends StatefulWidget {
  final ThermalPrinterService printerService;
  final Function(PrinterDevice) onConnected;

  const BluetoothDevicePickerView({
    super.key,
    required this.printerService,
    required this.onConnected,
  });

  @override
  State<BluetoothDevicePickerView> createState() =>
      _BluetoothDevicePickerViewState();
}

class _BluetoothDevicePickerViewState extends State<BluetoothDevicePickerView> {
  List<PrinterDevice> _devices = [];
  bool _isScanning = true;
  String? _connectingAddress;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() => _isScanning = true);
    final list = await widget.printerService.getDevices();
    if (mounted) {
      setState(() {
        _devices = list;
        _isScanning = false;
      });
    }
  }

  Future<void> _connect(PrinterDevice device) async {
    setState(() => _connectingAddress = device.address);
    final ok = await widget.printerService.connect(device);
    if (mounted) {
      setState(() => _connectingAddress = null);
      if (ok) {
        widget.onConnected(device);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not pair with Bluetooth printer.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!_isScanning && _devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_disabled_rounded,
                size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'No Bluetooth printers found',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Make sure printer Bluetooth is ON and paired.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Scan Again'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (_isScanning)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          ),
        Expanded(
          child: ListView.separated(
            itemCount: _devices.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: isDark ? AppColors.darkBorder : Colors.grey.shade200,
            ),
            itemBuilder: (context, i) {
              final dev = _devices[i];
              final isConnecting = _connectingAddress == dev.address;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: isDark
                      ? AppColors.darkSurfaceElevated
                      : AppColors.surfaceContainerLow,
                  child: const Icon(Icons.print_rounded,
                      color: AppColors.primary, size: 20),
                ),
                title: Text(
                  dev.name.isNotEmpty ? dev.name : 'Unknown Device',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.onSurface,
                  ),
                ),
                subtitle: Text(
                  dev.address ?? '',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : Colors.grey.shade600,
                  ),
                ),
                trailing: isConnecting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : ElevatedButton(
                        onPressed: () => _connect(dev),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Connect',
                            style: TextStyle(fontSize: 12)),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Bluetooth Device Picker Modal (Legacy Compatibility) ─────────────────────
// ── Public Bluetooth Device Scanner Sheet ────────────────────────────────────
class BluetoothDevicePicker extends StatefulWidget {
  final ThermalPrinterService printerService;
  final Function(PrinterDevice) onConnected;

  const BluetoothDevicePicker({
    super.key,
    required this.printerService,
    required this.onConnected,
  });

  @override
  State<BluetoothDevicePicker> createState() => _BluetoothDevicePickerState();
}

class _BluetoothDevicePickerState extends State<BluetoothDevicePicker> {
  List<PrinterDevice> _devices = [];
  bool _isScanning = true;
  String? _connectingAddress;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() => _isScanning = true);
    final list = await widget.printerService.getDevices();
    if (mounted) {
      setState(() {
        _devices = list;
        _isScanning = false;
      });
    }
  }

  Future<void> _connect(PrinterDevice device) async {
    setState(() => _connectingAddress = device.address);
    final ok = await widget.printerService.connect(device);
    if (mounted) {
      setState(() => _connectingAddress = null);
      if (ok) {
        widget.onConnected(device);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not pair with Bluetooth printer.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : Colors.grey.shade200,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bluetooth_searching_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Select Bluetooth Printer',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.onSurface,
                  ),
                ),
              ),
              if (_isScanning)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _scan,
                  tooltip: 'Rescan',
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Make sure your 2-inch or 3-inch thermal printer is powered on and Bluetooth is enabled.',
            style: TextStyle(
              color: isDark ? Colors.white54 : Colors.grey,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          if (!_isScanning && _devices.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Icon(Icons.print_disabled_rounded,
                      size: 40, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(
                    'No Bluetooth printers found.',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Pair your printer in Android Settings > Bluetooth first.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _scan,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Scan Again'),
                  ),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _devices.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: isDark ? AppColors.darkBorder : Colors.grey.shade200,
                ),
                itemBuilder: (context, i) {
                  final dev = _devices[i];
                  final isConnecting = _connectingAddress == dev.address;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: isDark
                          ? AppColors.darkSurfaceElevated
                          : AppColors.surfaceContainerLow,
                      child: const Icon(Icons.print_rounded,
                          color: AppColors.primary, size: 20),
                    ),
                    title: Text(
                      dev.name.isNotEmpty ? dev.name : 'Unknown Device',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppColors.onSurface,
                      ),
                    ),
                    subtitle: Text(
                      dev.address ?? '',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : Colors.grey.shade600,
                      ),
                    ),
                    trailing: isConnecting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : ElevatedButton(
                            onPressed: () => _connect(dev),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Connect',
                                style: TextStyle(fontSize: 12)),
                          ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
