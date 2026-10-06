import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pos_universal_printer/pos_universal_printer.dart';
import 'package:printing/printing.dart';
import '../core/models/models.dart';
import '../core/models/shop_settings.dart';
import 'hive_service.dart';
import 'pdf_service.dart';

class ThermalPrinterService {
  static final ThermalPrinterService _instance =
      ThermalPrinterService._internal();
  factory ThermalPrinterService() => _instance;
  ThermalPrinterService._internal() {
    _restoreSavedSystemPrinter();
  }

  final BlueThermalCompatPrinter bluetooth = BlueThermalCompatPrinter.instance;
  final PosUniversalPrinter _manager = PosUniversalPrinter.instance;

  // ── Bluetooth Connection State (Mobile / Android) ──────────────────────────
  PrinterDevice? _connectedDevice;
  PrinterDevice? get connectedDevice => _connectedDevice;
  bool get isConnected => _connectedDevice != null;

  // ── Windows / Desktop / Spooler Printer State ─────────────────────────────
  Printer? _selectedSystemPrinter;
  Printer? get selectedSystemPrinter => _selectedSystemPrinter;
  bool get hasSystemPrinter => _selectedSystemPrinter != null;

  /// True if any printer (Bluetooth or Windows/System) is ready for direct printing
  bool get isPrinterReady => isConnected || hasSystemPrinter;

  /// Display name of the active printer
  String get activePrinterDisplayName {
    if (_selectedSystemPrinter != null) {
      return _selectedSystemPrinter!.name;
    }
    if (_connectedDevice != null) {
      return _connectedDevice!.name.isNotEmpty
          ? _connectedDevice!.name
          : _connectedDevice!.address ?? 'Bluetooth Printer';
    }
    return 'No Printer Selected';
  }

  /// Whether current platform is desktop (Windows, macOS, Linux)
  bool get isDesktopPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// Restores previously saved system printer from Hive
  Future<void> _restoreSavedSystemPrinter() async {
    try {
      final savedUrl = HiveService.getSelectedPrinterUrl();
      final savedName = HiveService.getSelectedPrinterName();
      if (savedUrl == null && savedName == null) return;

      final printers = await Printing.listPrinters();
      for (final p in printers) {
        if ((savedUrl != null && p.url == savedUrl) ||
            (savedName != null && p.name == savedName)) {
          _selectedSystemPrinter = p;
          break;
        }
      }
    } catch (e) {
      debugPrint('Error restoring saved system printer: $e');
    }
  }

  /// Fetches all system installed printers (Windows Spooler / CUPS)
  Future<List<Printer>> getSystemPrinters() async {
    try {
      return await Printing.listPrinters();
    } catch (e) {
      debugPrint('Error listing system printers: $e');
      return [];
    }
  }

  /// Sets and saves the system thermal printer to Hive
  Future<void> setSystemPrinter(Printer printer) async {
    _selectedSystemPrinter = printer;
    await HiveService.setSelectedPrinter(
      url: printer.url,
      name: printer.name,
    );
  }

  /// Clears active system printer
  Future<void> clearSystemPrinter() async {
    _selectedSystemPrinter = null;
    await HiveService.setSelectedPrinter(url: null, name: null);
  }

  /// Scans system printers for ones likely to be thermal / POS receipt printers
  Future<Printer?> autoDetectThermalPrinter() async {
    try {
      final printers = await getSystemPrinters();
      if (printers.isEmpty) return null;

      const thermalKeywords = [
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

      for (final printer in printers) {
        final nameLower = printer.name.toLowerCase();
        for (final kw in thermalKeywords) {
          if (nameLower.contains(kw)) {
            return printer;
          }
        }
      }

      // Default fallback to system default printer if available
      return printers.cast<Printer?>().firstWhere(
            (p) => p?.isDefault ?? false,
            orElse: () => printers.first,
          );
    } catch (e) {
      debugPrint('Error auto-detecting thermal printer: $e');
      return null;
    }
  }

  /// Direct 1-Click Thermal Print (Instant, no Windows print dialog, correct roll sizing)
  Future<bool> printDirectInvoice({
    required Map<String, dynamic> invoice,
    bool is3Inch = true,
    Map<String, dynamic>? companyProfile,
    Printer? overridePrinter,
  }) async {
    try {
      // 1. Try Windows/System Direct Print first if configured or override provided
      final targetPrinter = overridePrinter ?? _selectedSystemPrinter;
      if (targetPrinter != null) {
        return await PdfService.directPrintThermalReceipt(
          invoice: invoice,
          printer: targetPrinter,
          is3Inch: is3Inch,
          companyProfile: companyProfile,
        );
      }

      // 2. If running on desktop/Windows and no printer is chosen, try auto-detecting
      if (isDesktopPlatform) {
        final detected = await autoDetectThermalPrinter();
        if (detected != null) {
          await setSystemPrinter(detected);
          return await PdfService.directPrintThermalReceipt(
            invoice: invoice,
            printer: detected,
            is3Inch: is3Inch,
            companyProfile: companyProfile,
          );
        }
      }

      // 3. Fallback to Bluetooth ESC/POS if connected (Mobile)
      if (isConnected) {
        return await printThermalInvoice(
          invoice: invoice,
          is3Inch: is3Inch,
          companyProfile: companyProfile,
        );
      }

      return false;
    } catch (e) {
      debugPrint('Direct thermal print error: $e');
      return false;
    }
  }

  /// Direct Test Receipt (Works on both Windows Thermal Printers and Bluetooth)
  Future<bool> printDirectTestReceipt({bool is3Inch = true}) async {
    try {
      if (_selectedSystemPrinter != null) {
        return await PdfService.directPrintTestReceipt(
          printer: _selectedSystemPrinter!,
          is3Inch: is3Inch,
        );
      }

      if (isDesktopPlatform) {
        final detected = await autoDetectThermalPrinter();
        if (detected != null) {
          await setSystemPrinter(detected);
          return await PdfService.directPrintTestReceipt(
            printer: detected,
            is3Inch: is3Inch,
          );
        }
      }

      if (isConnected) {
        return await printTestReceipt(is3Inch: is3Inch);
      }

      return false;
    } catch (e) {
      debugPrint('Direct test print error: $e');
      return false;
    }
  }

  /// Scans for available Bluetooth printers (Android/iOS)
  Future<List<PrinterDevice>> getDevices() async {
    final devices = <PrinterDevice>[];
    try {
      await for (final device in _manager.scanBluetooth()) {
        if (!devices.any((d) => d.address == device.address)) {
          devices.add(device);
        }
      }
    } catch (e) {
      debugPrint('Error scanning Bluetooth devices: $e');
    }
    return devices;
  }

  /// Connects to selected Bluetooth printer device
  Future<bool> connect(PrinterDevice device) async {
    try {
      await bluetooth.ensureDevice(
        role: PosPrinterRole.cashier,
        device: device,
      );
      _connectedDevice = device;
      return true;
    } catch (e) {
      debugPrint('Failed to connect to printer: $e');
      return false;
    }
  }

  /// Disconnects from active printer
  Future<void> disconnect() async {
    try {
      await _manager.dispose();
      _connectedDevice = null;
    } catch (e) {
      debugPrint('Error disconnecting printer: $e');
    }
  }

  /// Prints a 2-inch (58mm) or 3-inch (80mm) thermal receipt for an invoice map
  Future<bool> printThermalInvoice({
    required Map<String, dynamic> invoice,
    bool is3Inch = true,
    Map<String, dynamic>? companyProfile,
  }) async {
    try {
      final ShopSettings settings = HiveService.getShopSettings();
      final shopName = companyProfile?['companyName'] ??
          (settings.shopName.isNotEmpty ? settings.shopName : 'WinTech Spark+');
      final address = companyProfile?['address'] ?? settings.location;
      final contact = companyProfile?['contact'] ?? '';
      final gstNumber = companyProfile?['gstNumber'] ?? '';

      final fmt = NumberFormat('#,##,##0.00', 'en_IN');
      final dateFormat = DateFormat('dd-MMM-yyyy hh:mm a');

      final List items = (invoice['items'] as List?) ?? [];
      final double subtotal = (invoice['subtotal'] ?? 0).toDouble();
      final double gstAmount = (invoice['gstAmount'] ?? 0).toDouble();
      final double total = (invoice['total'] ?? 0).toDouble();
      final invoiceDate =
          DateTime.tryParse(invoice['date'] ?? '') ?? DateTime.now();
      final customerName = invoice['customerName'] ?? '';
      final customerMobile = invoice['customerMobile'] ?? '';
      final paymentMode = invoice['paymentMode'] ?? 'Cash';
      final status =
          (invoice['paymentStatus'] ?? invoice['status'] ?? 'Paid').toString();

      final divider = is3Inch
          ? "------------------------------------------------"
          : "--------------------------------";

      // ── Header ──────────────────────────────────────────────────────────
      bluetooth.printCustom(shopName.toUpperCase(), is3Inch ? 2 : 1, 1);
      if (address.isNotEmpty) {
        bluetooth.printCustom(address, 1, 1);
      }
      if (contact.isNotEmpty) {
        bluetooth.printCustom("Ph: $contact", 1, 1);
      }
      if (gstNumber.isNotEmpty) {
        bluetooth.printCustom("GSTIN: $gstNumber", 1, 1);
      }
      bluetooth.printNewLine();
      bluetooth.printCustom("TAX INVOICE", 1, 1);
      bluetooth.printCustom(divider, 1, 1);

      // ── Meta ────────────────────────────────────────────────────────────
      bluetooth.printLeftRight(
          "Invoice #:", invoice['invoiceNumber'] ?? '', 1);
      bluetooth.printLeftRight("Date:", dateFormat.format(invoiceDate), 1);
      if (customerName.isNotEmpty) {
        bluetooth.printLeftRight("Customer:", customerName, 1);
      }
      if (customerMobile.isNotEmpty) {
        bluetooth.printLeftRight("Phone:", customerMobile.toString(), 1);
      }
      bluetooth.printCustom(divider, 1, 1);

      // ── Items ───────────────────────────────────────────────────────────
      if (is3Inch) {
        bluetooth.printLeftRight("Item           Qty   Rate", "Amount", 1);
      } else {
        bluetooth.printLeftRight("Item     Qty  Rate", "Amount", 1);
      }
      bluetooth.printCustom(divider, 1, 1);

      for (final item in items) {
        final name = (item['productName'] ?? '').toString();
        final qty = item['quantity'] ?? 1;
        final price = (item['price'] ?? 0).toDouble();
        final itemTotal = (item['total'] ?? 0).toDouble();

        // Print item name
        bluetooth.printCustom(name, 1, 0);
        // Print qty, price and total on next line
        bluetooth.printLeftRight(
          "  $qty x Rs. ${fmt.format(price)}",
          "Rs. ${fmt.format(itemTotal)}",
          1,
        );
      }

      bluetooth.printCustom(divider, 1, 1);

      // ── Totals ──────────────────────────────────────────────────────────
      bluetooth.printLeftRight("Subtotal:", "Rs. ${fmt.format(subtotal)}", 1);
      bluetooth.printLeftRight("GST:", "Rs. ${fmt.format(gstAmount)}", 1);
      bluetooth.printLeftRight("TOTAL:", "Rs. ${fmt.format(total)}", 2);
      bluetooth.printLeftRight("Payment Mode:", paymentMode, 1);
      bluetooth.printLeftRight("Payment Status:", status.toUpperCase(), 1);
      final double paidAmount =
          (invoice['paidAmount'] ?? invoice['amountPaid'] ?? 0).toDouble();
      final double balance = (total - paidAmount).clamp(0.0, total);
      if (paidAmount > 0 && paidAmount < total) {
        bluetooth.printLeftRight("Paid:", "Rs. ${fmt.format(paidAmount)}", 1);
        bluetooth.printLeftRight("Balance:", "Rs. ${fmt.format(balance)}", 1);
      }

      bluetooth.printCustom(divider, 1, 1);

      // ── Footer ──────────────────────────────────────────────────────────
      bluetooth.printCustom("Thank You for Your Business!", 1, 1);
      bluetooth.printCustom("Please Visit Again", 1, 1);
      bluetooth.printNewLine();
      bluetooth.printNewLine();
      bluetooth.paperCut();

      return true;
    } catch (e) {
      debugPrint('Thermal print error: $e');
      return false;
    }
  }

  /// Legacy Sale receipt compatibility
  Future<void> printReceipt(Sale sale) async {
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

    bluetooth.printCustom("WINTECH SPARK", 3, 1);
    bluetooth.printNewLine();
    bluetooth.printCustom("Invoice: ${sale.invoiceNumber}", 1, 1);
    bluetooth.printCustom(dateFormat.format(sale.date), 1, 1);
    bluetooth.printCustom("--------------------------------", 1, 1);

    for (var item in sale.items) {
      bluetooth.printLeftRight(
        "${item.productName} x${item.quantity}",
        item.total.toStringAsFixed(2),
        1,
      );
    }

    bluetooth.printCustom("--------------------------------", 1, 1);

    bluetooth.printLeftRight("Subtotal", sale.subtotal.toStringAsFixed(2), 1);
    bluetooth.printLeftRight("GST (18%)", sale.gstAmount.toStringAsFixed(2), 1);
    bluetooth.printCustom("TOTAL: ${sale.total.toStringAsFixed(2)}", 2, 2);

    bluetooth.printNewLine();
    bluetooth.printCustom("Thank you for your business!", 1, 1);
    bluetooth.printNewLine();
    bluetooth.printNewLine();
    bluetooth.paperCut();
  }

  /// Label print for inventory
  Future<void> printLabel(Product product) async {
    if (_selectedSystemPrinter != null) {
      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(
            50 * PdfPageFormat.mm,
            30 * PdfPageFormat.mm,
            marginAll: 2 * PdfPageFormat.mm,
          ),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text('WINTECH SPARK',
                    style: pw.TextStyle(
                        fontSize: 8, fontWeight: pw.FontWeight.bold)),
                pw.Text(product.productName,
                    maxLines: 1, style: const pw.TextStyle(fontSize: 7)),
                pw.Text('PRICE: Rs. ${product.sellingPrice}',
                    style: pw.TextStyle(
                        fontSize: 8, fontWeight: pw.FontWeight.bold)),
                if (product.barcode != null && product.barcode!.isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 2),
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.code128(),
                      data: product.barcode!,
                      width: 80,
                      height: 14,
                    ),
                  ),
              ],
            );
          },
        ),
      );
      final bytes = await doc.save();
      await Printing.directPrintPdf(
        printer: _selectedSystemPrinter!,
        onLayout: (_) => bytes,
        format: const PdfPageFormat(50 * PdfPageFormat.mm, 30 * PdfPageFormat.mm),
        usePrinterSettings: true,
      );
      return;
    }

    if (isConnected) {
      bluetooth.printCustom("WINTECH SPARK", 2, 1);
      bluetooth.printCustom(product.productName, 1, 1);
      bluetooth.printCustom("PRICE: ${product.sellingPrice}", 2, 1);
      if (product.barcode != null) {
        bluetooth.printQRcode(product.barcode!);
      }
      bluetooth.printNewLine();
      bluetooth.paperCut();
    }
  }

  /// Prints a test receipt to verify Bluetooth printer connectivity
  Future<bool> printTestReceipt({bool is3Inch = true}) async {
    try {
      final ShopSettings settings = HiveService.getShopSettings();
      final shopName = settings.shopName.isNotEmpty ? settings.shopName : "WINTECH SPARK+";

      bluetooth.printCustom(shopName.toUpperCase(), is3Inch ? 2 : 1, 1);
      bluetooth.printCustom("BLUETOOTH PRINTER TEST", 1, 1);
      bluetooth.printCustom(is3Inch ? "80mm (3-Inch) Thermal" : "58mm (2-Inch) Thermal", 1, 1);
      bluetooth.printNewLine();
      bluetooth.printLeftRight("Status:", "Connected & Ready", 1);
      bluetooth.printLeftRight("Time:", DateFormat('dd-MMM-yyyy hh:mm a').format(DateTime.now()), 1);
      bluetooth.printNewLine();
      bluetooth.printCustom("Spark+ Thermal Engine OK!", 1, 1);
      bluetooth.printNewLine();
      bluetooth.printNewLine();
      bluetooth.paperCut();
      return true;
    } catch (e) {
      debugPrint("Test print error: $e");
      return false;
    }
  }
}
