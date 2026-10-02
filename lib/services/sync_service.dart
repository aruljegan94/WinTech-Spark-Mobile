import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../core/models/models.dart';
import '../core/models/shop_settings.dart';
import 'hive_service.dart';

/// Handles bidirectional sync between local Hive and shared Firestore root collections.
/// Shared collections with Spark-PWA Web App:
/// - /products
/// - /sales
/// - /expenses
class SyncService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static StreamSubscription<QuerySnapshot>? _productSub;
  static StreamSubscription<QuerySnapshot>? _expenseSub;

  // ── Firestore Root Collection References ──────────────────────────────────
  static CollectionReference get productsCol => _db.collection('products');
  static CollectionReference get salesCol => _db.collection('sales');
  static CollectionReference get expensesCol => _db.collection('expenses');
  static CollectionReference get purchasesCol => _db.collection('purchases');
  static CollectionReference get vendorsCol => _db.collection('vendors');
  static CollectionReference get companyProfilesCol => _db.collection('companyProfiles');
  static CollectionReference get settingsCol => _db.collection('settings');
  static CollectionReference get usersCol => _db.collection('users');

  // ── Start Live Background Sync ───────────────────────────────────────────
  /// Call this when the app starts (e.g. in MainLayout initState) to keep
  /// local Hive cache in continuous sync with the Web App Firestore database.
  static void initLiveSync() {
    _startProductSync();
    _startExpenseSync();
    uploadUnsyncedData();
  }

  static void disposeLiveSync() {
    _productSub?.cancel();
    _expenseSub?.cancel();
  }

  /// Listens to root /products collection and synchronizes into local Hive
  static void _startProductSync() {
    _productSub?.cancel();
    _productSub = productsCol.snapshots().listen(
      (snapshot) async {
        final box = HiveService.getBox<Product>(HiveService.productBoxName);
        for (final change in snapshot.docChanges) {
          final doc = change.doc;
          final data = doc.data() as Map<String, dynamic>?;

          if (change.type == DocumentChangeType.removed) {
            await box.delete(doc.id);
          } else if (data != null) {
            final product = Product.fromFirestore(data, doc.id);
            await box.put(doc.id, product);
          }
        }
        if (kDebugMode) {
          print('[SyncService] Products synced from Firestore. Total: ${box.length}');
        }
      },
      onError: (err) {
        if (kDebugMode) print('[SyncService] Product sync error: $err');
      },
    );
  }

  /// Listens to root /expenses collection and synchronizes into local Hive
  static void _startExpenseSync() {
    _expenseSub?.cancel();
    _expenseSub = expensesCol.snapshots().listen(
      (snapshot) async {
        final box = HiveService.getBox<Expense>(HiveService.expenseBoxName);
        for (final change in snapshot.docChanges) {
          final doc = change.doc;
          final data = doc.data() as Map<String, dynamic>?;

          if (change.type == DocumentChangeType.removed) {
            await box.delete(doc.id);
          } else if (data != null) {
            final expense = Expense.fromFirestore(data, doc.id);
            await box.put(doc.id, expense);
          }
        }
        if (kDebugMode) {
          print('[SyncService] Expenses synced from Firestore. Total: ${box.length}');
        }
      },
      onError: (err) {
        if (kDebugMode) print('[SyncService] Expense sync error: $err');
      },
    );
  }

  /// Real-time create or update product across Hive & Firestore root collection
  static Future<void> saveOrUpdateProduct(Product product) async {
    await HiveService.addProduct(product);
    try {
      await productsCol.doc(product.id).set({
        'id': product.id,
        'productName': product.productName,
        'category': product.category,
        'purchasePrice': product.purchasePrice,
        'sellingPrice': product.sellingPrice,
        'stockQuantity': product.stockQuantity,
        'gstPercentage': product.gstPercentage,
        'barcode': product.barcode ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) print('[SyncService] Failed to sync product: $e');
    }
  }

  /// Real-time stock quantity update across Hive & Firestore
  static Future<void> updateProductStock(String productId, int newQuantity) async {
    final box = HiveService.getBox<Product>(HiveService.productBoxName);
    final product = box.get(productId);
    if (product != null) {
      product.stockQuantity = newQuantity;
      await product.save();
    }

    try {
      await productsCol.doc(productId).update({
        'stockQuantity': newQuantity,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) print('[SyncService] Failed to update stock online: $e');
    }
  }

  /// Delete product across Hive & Firestore
  static Future<void> deleteProduct(String productId) async {
    await HiveService.deleteProduct(productId);
    try {
      await productsCol.doc(productId).delete();
    } catch (e) {
      if (kDebugMode) print('[SyncService] Failed to delete product online: $e');
    }
  }

  // ── One-time: Push unsynced local data to Firestore ──────────────────────
  static Future<void> uploadUnsyncedData() async {
    try {
      await Future.wait([
        _uploadSales(),
        _uploadExpenses(),
        _uploadProducts(),
      ]);
    } catch (e) {
      if (kDebugMode) print('[SyncService] uploadUnsyncedData error: $e');
    }
  }

  static Future<void> _uploadSales() async {
    final sales = HiveService.getBox<Sale>(HiveService.saleBoxName).values
        .where((s) => !s.isSynced)
        .toList();

    for (final sale in sales) {
      await salesCol.doc(sale.id).set({
        'id': sale.id,
        'invoiceNumber': sale.invoiceNumber,
        'date': sale.date.toIso8601String(),
        'customerName': sale.customerName ?? '',
        'subtotal': sale.subtotal,
        'gstAmount': sale.gstAmount,
        'total': sale.total,
        'paymentStatus': sale.paymentStatus,
        'status': sale.paymentStatus, // For Web App PWA compatibility
        'paymentMode': sale.paymentMode,
        'amountPaid': sale.paymentStatus == 'Paid' ? sale.total : 0.0,
        'items': sale.items
            .map((i) => {
                  'productId': i.productId,
                  'productName': i.productName,
                  'quantity': i.quantity,
                  'price': i.price,
                  'gstPercentage': i.gstPercentage,
                  'total': i.total,
                })
            .toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      sale.isSynced = true;
      await sale.save();
    }
    if (kDebugMode && sales.isNotEmpty) {
      print('[SyncService] Uploaded ${sales.length} offline sales.');
    }
  }

  static Future<void> _uploadExpenses() async {
    final expenses =
        HiveService.getBox<Expense>(HiveService.expenseBoxName).values
            .where((e) => !e.isSynced)
            .toList();

    for (final expense in expenses) {
      await expensesCol.doc(expense.id).set({
        'id': expense.id,
        'date': expense.date.toIso8601String(),
        'expenseType': expense.expenseType,
        'amount': expense.amount,
        'notes': expense.notes ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      expense.isSynced = true;
      await expense.save();
    }
    if (kDebugMode && expenses.isNotEmpty) {
      print('[SyncService] Uploaded ${expenses.length} offline expenses.');
    }
  }

  static Future<void> _uploadProducts() async {
    final products =
        HiveService.getBox<Product>(HiveService.productBoxName).values.toList();

    for (final product in products) {
      await productsCol.doc(product.id).set({
        'id': product.id,
        'productName': product.productName,
        'category': product.category,
        'purchasePrice': product.purchasePrice,
        'sellingPrice': product.sellingPrice,
        'stockQuantity': product.stockQuantity,
        'gstPercentage': product.gstPercentage,
        'barcode': product.barcode ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    if (kDebugMode && products.isNotEmpty) {
      print('[SyncService] Synced ${products.length} products to root /products.');
    }
  }

  // ── Real-time Dashboard Streams (Root Collections) ────────────────────────

  /// Stream of all sales for the current month
  static Stream<QuerySnapshot> get currentMonthSalesStream {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1).toIso8601String();
    final end = DateTime(now.year, now.month + 1, 1).toIso8601String();
    return salesCol
        .where('date', isGreaterThanOrEqualTo: start)
        .where('date', isLessThan: end)
        .orderBy('date', descending: true)
        .snapshots();
  }

  /// Stream of all expenses for the current month
  static Stream<QuerySnapshot> get currentMonthExpensesStream {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1).toIso8601String();
    final end = DateTime(now.year, now.month + 1, 1).toIso8601String();
    return expensesCol
        .where('date', isGreaterThanOrEqualTo: start)
        .where('date', isLessThan: end)
        .snapshots();
  }

  /// Stream of recent 10 invoices (any month)
  static Stream<QuerySnapshot> get recentSalesStream {
    return salesCol
        .orderBy('date', descending: true)
        .limit(10)
        .snapshots();
  }

  /// Direct full streams for executive dashboard
  static Stream<QuerySnapshot> get allSalesStream =>
      salesCol.orderBy('date', descending: true).snapshots();
  static Stream<QuerySnapshot> get allProductsStream =>
      productsCol.snapshots();
  static Stream<QuerySnapshot> get allPurchasesStream =>
      purchasesCol.snapshots();
  static Stream<QuerySnapshot> get allExpensesStream =>
      expensesCol.snapshots();

  // ── Helpers to compute stats from a QuerySnapshot ────────────────────────
  static Map<String, dynamic> aggregateSales(QuerySnapshot snapshot) {
    int totalCount = snapshot.docs.length;
    double paidAmount = 0;
    double pendingAmount = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final total = (data['total'] ?? 0).toDouble();
      final paid = (data['paidAmount'] ?? data['amountPaid'] ?? 0).toDouble();
      final status = data['paymentStatus'] ?? data['status'] ?? '';

      if (status == 'Paid') {
        paidAmount += total;
      } else if (status == 'Partial') {
        paidAmount += paid;
        pendingAmount += (total - paid);
      } else {
        pendingAmount += total;
      }
    }

    return {
      'totalCount': totalCount,
      'paidAmount': paidAmount,
      'pendingAmount': pendingAmount,
    };
  }

  static double aggregateExpenses(QuerySnapshot snapshot) {
    double total = 0;
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      total += (data['amount'] ?? 0).toDouble();
    }
    return total;
  }

  // ── Company Profile & Settings Sync with Web App ─────────────────────────

  /// Fetches default company profile from Firestore and syncs into local ShopSettings
  static Future<Map<String, dynamic>?> fetchCompanyProfile() async {
    try {
      final snap = await companyProfilesCol
          .where('isDefault', isEqualTo: true)
          .limit(1)
          .get();
      QueryDocumentSnapshot? profileDoc;
      if (snap.docs.isNotEmpty) {
        profileDoc = snap.docs.first;
      } else {
        final all = await companyProfilesCol.limit(1).get();
        if (all.docs.isNotEmpty) profileDoc = all.docs.first;
      }

      if (profileDoc != null) {
        final data = profileDoc.data() as Map<String, dynamic>;
        data['id'] = profileDoc.id;

        // Sync into local Hive ShopSettings
        final current = HiveService.getShopSettings();
        final updated = ShopSettings(
          shopName: (data['companyName'] ?? current.shopName).toString(),
          location: (data['address'] ?? current.location).toString(),
          invoicePrefix: (data['invoicePrefix'] ?? current.invoicePrefix).toString(),
          invoiceSuffix: (data['invoiceSuffix'] ?? current.invoiceSuffix).toString(),
          invoiceCounter: current.invoiceCounter,
        );
        await HiveService.saveShopSettings(updated);
        return data;
      }
    } catch (e) {
      if (kDebugMode) print('[SyncService] fetchCompanyProfile error: $e');
    }
    return null;
  }

  /// Saves company profile to Firestore and syncs into local ShopSettings
  static Future<bool> saveCompanyProfile(Map<String, dynamic> data) async {
    try {
      final String? docId = data['id'];
      final updateData = Map<String, dynamic>.from(data);
      updateData.remove('id');
      updateData['isDefault'] = true;
      updateData['updatedAt'] = FieldValue.serverTimestamp();

      if (docId != null && docId.isNotEmpty) {
        await companyProfilesCol.doc(docId).set(updateData, SetOptions(merge: true));
      } else {
        final existing = await companyProfilesCol.limit(1).get();
        if (existing.docs.isNotEmpty) {
          await companyProfilesCol
              .doc(existing.docs.first.id)
              .set(updateData, SetOptions(merge: true));
        } else {
          await companyProfilesCol.add(updateData);
        }
      }

      // Sync into local Hive ShopSettings
      final current = HiveService.getShopSettings();
      final updated = ShopSettings(
        shopName: (data['companyName'] ?? current.shopName).toString().trim(),
        location: (data['address'] ?? current.location).toString().trim(),
        invoicePrefix: (data['invoicePrefix'] ?? current.invoicePrefix).toString().trim(),
        invoiceSuffix: (data['invoiceSuffix'] ?? current.invoiceSuffix).toString().trim(),
        invoiceCounter: current.invoiceCounter,
      );
      await HiveService.saveShopSettings(updated);
      return true;
    } catch (e) {
      if (kDebugMode) print('[SyncService] saveCompanyProfile error: $e');
      return false;
    }
  }

  /// Fetches global app settings from Firestore root /settings/app
  static Future<Map<String, dynamic>?> fetchAppSettings() async {
    try {
      final doc = await settingsCol.doc('app').get();
      if (doc.exists && doc.data() != null) {
        return doc.data() as Map<String, dynamic>;
      }
    } catch (e) {
      if (kDebugMode) print('[SyncService] fetchAppSettings error: $e');
    }
    return null;
  }

  /// Saves app settings to Firestore root /settings/app
  static Future<bool> saveAppSettings(Map<String, dynamic> data) async {
    try {
      await settingsCol.doc('app').set(data, SetOptions(merge: true));
      return true;
    } catch (e) {
      if (kDebugMode) print('[SyncService] saveAppSettings error: $e');
      return false;
    }
  }

  /// Fetches user profile from Firestore /users/{uid}
  static Future<Map<String, dynamic>?> fetchUserProfile(String uid) async {
    try {
      final doc = await usersCol.doc(uid).get();
      if (doc.exists && doc.data() != null) {
        return doc.data() as Map<String, dynamic>;
      }
    } catch (e) {
      if (kDebugMode) print('[SyncService] fetchUserProfile error: $e');
    }
    return null;
  }

  /// Saves or updates user profile in Firestore /users/{uid}
  static Future<bool> saveUserProfile(String uid, Map<String, dynamic> data) async {
    try {
      await usersCol.doc(uid).set(data, SetOptions(merge: true));
      return true;
    } catch (e) {
      if (kDebugMode) print('[SyncService] saveUserProfile error: $e');
      return false;
    }
  }

  /// Performs full bi-directional sync with Spark-PWA Web App
  static Future<Map<String, dynamic>> performFullSync() async {
    try {
      // 1. Upload unsynced local data
      await uploadUnsyncedData();

      // 2. Fetch fresh products from Firestore
      final prodSnap = await productsCol.get();
      final prodBox = HiveService.getBox<Product>(HiveService.productBoxName);
      for (final doc in prodSnap.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null) {
          final p = Product.fromFirestore(data, doc.id);
          await prodBox.put(doc.id, p);
        }
      }

      // 3. Fetch fresh expenses from Firestore
      final expSnap = await expensesCol.get();
      final expBox = HiveService.getBox<Expense>(HiveService.expenseBoxName);
      for (final doc in expSnap.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null) {
          final exp = Expense.fromFirestore(data, doc.id);
          await expBox.put(doc.id, exp);
        }
      }

      // 4. Fetch company profile & settings
      await fetchCompanyProfile();
      await fetchAppSettings();

      return {
        'success': true,
        'products': prodBox.length,
        'expenses': expBox.length,
        'timestamp': DateTime.now(),
      };
    } catch (e) {
      if (kDebugMode) print('[SyncService] performFullSync error: $e');
      return {
        'success': false,
        'error': e.toString(),
        'timestamp': DateTime.now(),
      };
    }
  }
}
