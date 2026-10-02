import 'package:hive/hive.dart';

part 'shop_settings.g.dart';

@HiveType(typeId: 10)
class ShopSettings extends HiveObject {
  @HiveField(0)
  String shopName;

  @HiveField(1)
  String location;

  @HiveField(2)
  String invoicePrefix;

  @HiveField(3)
  String invoiceSuffix;

  @HiveField(4)
  int invoiceCounter;

  ShopSettings({
    this.shopName = '',
    this.location = '',
    this.invoicePrefix = 'INV-',
    this.invoiceSuffix = '',
    this.invoiceCounter = 1,
  });

  /// Returns the next invoice number, e.g. WIN/INV-001/26
  String get nextInvoiceNumber {
    final num = invoiceCounter.toString().padLeft(3, '0');
    return '$invoicePrefix$num$invoiceSuffix';
  }
}
