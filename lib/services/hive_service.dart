import 'package:hive_flutter/hive_flutter.dart';
import '../core/models/models.dart';
import '../core/models/shop_settings.dart';

class HiveService {
  static const String productBoxName = 'products';
  static const String saleBoxName = 'sales';
  static const String expenseBoxName = 'expenses';
  static const String settingsBoxName = 'shop_settings';

  static Future<void> init() async {
    await Hive.initFlutter();

    // Register Adapters
    Hive.registerAdapter(ProductAdapter());
    Hive.registerAdapter(SaleItemAdapter());
    Hive.registerAdapter(SaleAdapter());
    Hive.registerAdapter(ExpenseAdapter());
    Hive.registerAdapter(ShopSettingsAdapter());

    await Hive.openBox<Product>(productBoxName);
    await Hive.openBox<Sale>(saleBoxName);
    await Hive.openBox<Expense>(expenseBoxName);
    await Hive.openBox<ShopSettings>(settingsBoxName);
    await Hive.openBox('printer_settings');
  }

  // ── Shop Settings ─────────────────────────────────────────────
  static Box<ShopSettings> get _settingsBox =>
      Hive.box<ShopSettings>(settingsBoxName);

  static ShopSettings getShopSettings() {
    return _settingsBox.get('main') ??
        ShopSettings(
          shopName: '',
          location: '',
          invoicePrefix: 'INV-',
          invoiceSuffix: '',
          invoiceCounter: 1,
        );
  }

  static Future<void> saveShopSettings(ShopSettings settings) async {
    await _settingsBox.put('main', settings);
  }

  // ── Printer Settings ──────────────────────────────────────────
  static Box get _printerBox => Hive.box('printer_settings');

  static String? getSelectedPrinterUrl() {
    return _printerBox.get('selected_printer_url') as String?;
  }

  static String? getSelectedPrinterName() {
    return _printerBox.get('selected_printer_name') as String?;
  }

  static Future<void> setSelectedPrinter({
    required String? url,
    required String? name,
  }) async {
    await _printerBox.put('selected_printer_url', url);
    await _printerBox.put('selected_printer_name', name);
  }

  static String getPreferredPaperSize() {
    return _printerBox.get('preferred_paper_size', defaultValue: '80mm') as String;
  }

  static Future<void> setPreferredPaperSize(String size) async {
    await _printerBox.put('preferred_paper_size', size);
  }


  // Generic CRUD
  static Box<T> getBox<T>(String name) => Hive.box<T>(name);

  // Example specific methods
  static List<Product> getAllProducts() {
    return getBox<Product>(productBoxName).values.toList();
  }

  static Product? getProductById(String id) {
    return getBox<Product>(productBoxName).get(id);
  }

  static Product? getProductByBarcode(String barcode) {
    try {
      return getBox<Product>(productBoxName).values.firstWhere(
        (p) => (p.barcode != null && p.barcode == barcode) || p.id == barcode,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteProduct(String id) async {
    await getBox<Product>(productBoxName).delete(id);
  }

  static Future<void> addProduct(Product product) async {
    await getBox<Product>(productBoxName).put(product.id, product);
  }

  static Future<void> addSale(Sale sale) async {
    await getBox<Sale>(saleBoxName).put(sale.id, sale);
    
    // Update stock levels
    final productBox = getBox<Product>(productBoxName);
    for (var item in sale.items) {
      final product = productBox.get(item.productId);
      if (product != null) {
        product.stockQuantity -= item.quantity;
        await product.save();
      }
    }
  }

  static Future<void> addExpense(Expense expense) async {
    await getBox<Expense>(expenseBoxName).put(expense.id, expense);
  }
}
