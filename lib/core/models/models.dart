import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'models.g.dart';

@HiveType(typeId: 0)
class Product extends HiveObject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String productName;
  @HiveField(2)
  final String category;
  @HiveField(3)
  final double purchasePrice;
  @HiveField(4)
  final double sellingPrice;
  @HiveField(5)
  int stockQuantity;
  @HiveField(6)
  final double gstPercentage;
  @HiveField(7)
  final String? barcode;

  Product({
    required this.id,
    required this.productName,
    required this.category,
    required this.purchasePrice,
    required this.sellingPrice,
    required this.stockQuantity,
    this.gstPercentage = 18.0,
    this.barcode,
  });

  factory Product.newItem({
    required String productName,
    required String category,
    required double purchasePrice,
    required double sellingPrice,
    required int stockQuantity,
    String? barcode,
  }) {
    return Product(
      id: const Uuid().v4(),
      productName: productName,
      category: category,
      purchasePrice: purchasePrice,
      sellingPrice: sellingPrice,
      stockQuantity: stockQuantity,
      barcode: barcode,
    );
  }

  factory Product.fromFirestore(Map<String, dynamic> data, String id) {
    return Product(
      id: id,
      productName: data['productName'] ?? '',
      category: data['category'] ?? 'General',
      purchasePrice: (data['purchasePrice'] ?? 0).toDouble(),
      sellingPrice: (data['sellingPrice'] ?? 0).toDouble(),
      stockQuantity: data['stockQuantity'] is int
          ? data['stockQuantity']
          : (data['stockQuantity'] as num?)?.toInt() ?? 0,
      gstPercentage: (data['gstPercentage'] ?? 18.0).toDouble(),
      barcode: data['barcode'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'productName': productName,
      'category': category,
      'purchasePrice': purchasePrice,
      'sellingPrice': sellingPrice,
      'stockQuantity': stockQuantity,
      'gstPercentage': gstPercentage,
      if (barcode != null && barcode!.isNotEmpty) 'barcode': barcode,
    };
  }
}

@HiveType(typeId: 1)
class SaleItem {
  @HiveField(0)
  final String productId;
  @HiveField(1)
  final String productName;
  @HiveField(2)
  final int quantity;
  @HiveField(3)
  final double price;
  @HiveField(4)
  final double gstPercentage;
  @HiveField(5)
  final double total;

  SaleItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.price,
    required this.gstPercentage,
    required this.total,
  });
}

@HiveType(typeId: 2)
class Sale extends HiveObject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String invoiceNumber;
  @HiveField(2)
  final DateTime date;
  @HiveField(3)
  final String? customerName;
  @HiveField(4)
  final List<SaleItem> items;
  @HiveField(5)
  final double subtotal;
  @HiveField(6)
  final double gstAmount;
  @HiveField(7)
  final double total;
  @HiveField(8)
  final String paymentStatus; // Paid, Pending, Partial
  @HiveField(9)
  final String paymentMode; // Cash, UPI
  @HiveField(10)
  bool isSynced;

  Sale({
    required this.id,
    required this.invoiceNumber,
    required this.date,
    this.customerName,
    required this.items,
    required this.subtotal,
    required this.gstAmount,
    required this.total,
    required this.paymentStatus,
    required this.paymentMode,
    this.isSynced = false,
  });
}

@HiveType(typeId: 3)
class Expense extends HiveObject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final DateTime date;
  @HiveField(2)
  final String expenseType;
  @HiveField(3)
  final double amount;
  @HiveField(4)
  final String? notes;
  @HiveField(5)
  bool isSynced;

  Expense({
    required this.id,
    required this.date,
    required this.expenseType,
    required this.amount,
    this.notes,
    this.isSynced = false,
  });

  factory Expense.fromFirestore(Map<String, dynamic> data, String id) {
    DateTime parsedDate;
    final rawDate = data['date'];
    if (rawDate is String) {
      parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }
    return Expense(
      id: id,
      date: parsedDate,
      expenseType: data['expenseType'] ?? 'Others',
      amount: (data['amount'] ?? 0).toDouble(),
      notes: data['notes'],
      isSynced: true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'expenseType': expenseType,
      'amount': amount,
      'notes': notes ?? '',
    };
  }
}

class Customer {
  final String id;
  final String name;
  final String mobile;
  final String? address;
  final String? email;
  final double pendingDue;
  final double totalSpent;
  final int totalInvoices;
  final String? offers;
  final String? notes;

  Customer({
    required this.id,
    required this.name,
    required this.mobile,
    this.address,
    this.email,
    this.pendingDue = 0,
    this.totalSpent = 0,
    this.totalInvoices = 0,
    this.offers,
    this.notes,
  });

  factory Customer.fromFirestore(Map<String, dynamic> data, String id) {
    return Customer(
      id: id,
      name: data['name'] ?? '',
      mobile: data['mobile'] ?? '',
      address: data['address'],
      email: data['email'],
      pendingDue: (data['pendingDue'] ?? 0).toDouble(),
      totalSpent: (data['totalSpent'] ?? 0).toDouble(),
      totalInvoices: (data['totalInvoices'] ?? 0) is int
          ? data['totalInvoices']
          : (data['totalInvoices'] as num?)?.toInt() ?? 0,
      offers: data['offers'],
      notes: data['notes'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name,
      'mobile': mobile,
      if (address != null && address!.isNotEmpty) 'address': address,
      if (email != null && email!.isNotEmpty) 'email': email,
      'pendingDue': pendingDue,
      'totalSpent': totalSpent,
      'totalInvoices': totalInvoices,
      if (offers != null && offers!.isNotEmpty) 'offers': offers,
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }
}
