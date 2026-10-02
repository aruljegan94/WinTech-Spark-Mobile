import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pos_universal_printer/pos_universal_printer.dart';
import 'package:pos_universal_printer/blue_thermal_compat.dart';
import '../core/models/models.dart';
import '../core/models/shop_settings.dart';
import 'hive_service.dart';

class ThermalPrinterService {
  static final ThermalPrinterService _instance =
      ThermalPrinterService._internal();
  factory ThermalPrinterService() => _instance;
  ThermalPrinterService._internal();

  final BlueThermalCompatPrinter bluetooth = BlueThermalCompatPrinter.instance;
  final PosUniversalPrinter _manager = PosUniversalPrinter.instance;

  PrinterDevice? _connectedDevice;
  PrinterDevice? get connectedDevice => _connectedDevice;
  bool get isConnected => _connectedDevice != null;

  /// Scans for available Bluetooth printers
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
          "  $qty x ₹${fmt.format(price)}",
          "₹${fmt.format(itemTotal)}",
          1,
        );
      }

      bluetooth.printCustom(divider, 1, 1);

      // ── Totals ──────────────────────────────────────────────────────────
      bluetooth.printLeftRight("Subtotal:", "₹${fmt.format(subtotal)}", 1);
      bluetooth.printLeftRight("GST:", "₹${fmt.format(gstAmount)}", 1);
      bluetooth.printLeftRight("TOTAL:", "₹${fmt.format(total)}", 2);
      bluetooth.printLeftRight("Payment Mode:", paymentMode, 1);
      bluetooth.printLeftRight("Payment Status:", status.toUpperCase(), 1);

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
    bluetooth.printCustom("WINTECH SPARK", 2, 1);
    bluetooth.printCustom(product.productName, 1, 1);
    bluetooth.printCustom("PRICE: ${product.sellingPrice}", 2, 1);
    if (product.barcode != null) {
      bluetooth.printQRcode(product.barcode!);
    }
    bluetooth.printNewLine();
    bluetooth.paperCut();
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
