import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/models/models.dart';
import '../core/models/shop_settings.dart';
import 'hive_service.dart';

class InvoiceService {
  static final _db = FirebaseFirestore.instance;

  // Shared root collections with Spark-PWA Web App
  static CollectionReference get _salesCol => _db.collection('sales');
  static CollectionReference get _productsCol => _db.collection('products');
  static CollectionReference get _customersCol => _db.collection('customers');
  static CollectionReference get _companyProfilesCol => _db.collection('companyProfiles');
  static DocumentReference get _salesCounterDoc => _db.collection('counters').doc('sales');

  /// Fetches default company profile from Firestore
  static Future<Map<String, dynamic>?> getDefaultCompanyProfile() async {
    try {
      final profileSnap = await _companyProfilesCol
          .where('isDefault', isEqualTo: true)
          .limit(1)
          .get();
      if (profileSnap.docs.isNotEmpty) {
        return profileSnap.docs.first.data() as Map<String, dynamic>;
      }
      final allSnap = await _companyProfilesCol.limit(1).get();
      if (allSnap.docs.isNotEmpty) {
        return allSnap.docs.first.data() as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Fetches next synchronized invoice number from Firestore counters/sales
  /// using prefix/suffix configured in default company profile.
  static Future<String> getNextInvoiceNumber() async {
    try {
      // 1. Get prefix from default company profile
      String prefix = 'INV-';
      String suffix = '';
      try {
        final profile = await getDefaultCompanyProfile();
        if (profile != null) {
          prefix = profile['invoicePrefix'] ?? 'INV-';
          suffix = profile['invoiceSuffix'] ?? '';
        }
      } catch (_) {}

      // 2. Get counter from counters/sales
      final counterSnap = await _salesCounterDoc.get();
      int currentNumber = 0;
      if (counterSnap.exists && counterSnap.data() != null) {
        final data = counterSnap.data() as Map<String, dynamic>;
        currentNumber = (data['currentNumber'] ?? 0) is int
            ? data['currentNumber']
            : (data['currentNumber'] as num?)?.toInt() ?? 0;
      }

      final nextNumber = currentNumber + 1;
      final formatted = nextNumber.toString().padLeft(3, '0');
      return '$prefix$formatted$suffix';
    } catch (e) {
      // Fallback to local settings if offline
      final settings = HiveService.getShopSettings();
      return settings.nextInvoiceNumber;
    }
  }

  /// Saves or updates an invoice with atomic Firestore sync, customer balance
  /// tracking, counter updates, and stock deduction.
  static Future<Map<String, String>> saveInvoice({
    String? docId,
    String? existingInvoiceNumber,
    String? originalDate,
    required List<SaleItem> items,
    required double subtotal,
    required double gstAmount,
    required double total,
    required String paymentMode,
    required String paymentStatus,
    String? customerId,
    String? customerName,
    String? customerMobile,
    String? customerAddress,
    String? customerGstNo,
    String? notes,
    double paidAmount = 0,
  }) async {
    final isUpdate = docId != null;
    final finalDocId = isUpdate ? docId : _salesCol.doc().id;
    final finalDate = isUpdate
        ? (originalDate ?? DateTime.now().toIso8601String())
        : DateTime.now().toIso8601String();

    String finalInvoiceNumber = existingInvoiceNumber ?? '';

    // If creating a brand new invoice and no invoiceNumber was pre-supplied:
    if (!isUpdate && finalInvoiceNumber.isEmpty) {
      finalInvoiceNumber = await getNextInvoiceNumber();
    }

    final docRef = _salesCol.doc(finalDocId);
    final nowIso = DateTime.now().toIso8601String();

    final data = {
      'id': finalDocId,
      'invoiceNumber': finalInvoiceNumber,
      'date': finalDate,
      if (customerId != null && customerId.isNotEmpty) 'customerId': customerId,
      'customerName': customerName?.isNotEmpty == true ? customerName : 'N/A',
      if (customerMobile != null && customerMobile.isNotEmpty)
        'customerMobile': customerMobile,
      if (customerAddress != null && customerAddress.isNotEmpty)
        'customerAddress': customerAddress,
      if (customerGstNo != null && customerGstNo.isNotEmpty)
        'customerGstNo': customerGstNo,
      'items': items
          .map((i) => {
                'productId': i.productId,
                'productName': i.productName,
                'quantity': i.quantity,
                'price': i.price,
                'gstPercentage': i.gstPercentage,
                'total': i.total,
              })
          .toList(),
      'subtotal': subtotal,
      'gstAmount': gstAmount,
      'total': total,
      'paidAmount': paidAmount,
      'amountPaid': paidAmount, // For Web App PWA alignment
      'paymentStatus': paymentStatus,
      'status': paymentStatus, // For Web App PWA alignment
      'paymentMode': paymentMode,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'isSynced': true,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final invoicePendingDue = paymentStatus == 'Pending'
        ? total
        : paymentStatus == 'Partial'
            ? (total - paidAmount).clamp(0.0, total)
            : 0.0;

    if (!isUpdate) {
      data['createdAt'] = FieldValue.serverTimestamp();
      await docRef.set(data);

      // ── 1. Increment Firestore counters/sales ──
      _salesCounterDoc.set({
        'currentNumber': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((_) {});

      // ── 2. Auto-decrement inventory stock in both Firestore and Hive ──
      for (final item in items) {
        if (item.productId.isNotEmpty) {
          _productsCol.doc(item.productId).update({
            'stockQuantity': FieldValue.increment(-item.quantity),
            'updatedAt': FieldValue.serverTimestamp(),
          }).catchError((e) {
            if (kDebugMode) print('[InvoiceService] Stock decrement error: $e');
          });

          final localProduct = HiveService.getProductById(item.productId);
          if (localProduct != null) {
            localProduct.stockQuantity -= item.quantity;
            await localProduct.save();
          }
        }
      }

      // ── 3. Update or Create Customer in Firestore /customers ──
      if (customerId != null && customerId.isNotEmpty) {
        _customersCol.doc(customerId).update({
          'totalSpent': FieldValue.increment(total),
          'totalInvoices': FieldValue.increment(1),
          'pendingDue': FieldValue.increment(invoicePendingDue),
          if (customerMobile != null && customerMobile.isNotEmpty)
            'mobile': customerMobile,
          if (customerAddress != null && customerAddress.isNotEmpty)
            'address': customerAddress,
          'updatedAt': nowIso,
        }).catchError((_) {});
      } else if (customerName != null &&
          customerName.trim().isNotEmpty &&
          customerName.trim() != 'N/A' &&
          customerName.trim() != 'Walk-in Customer') {
        // Auto-create new customer in /customers
        final newCustRef = _customersCol.doc();
        newCustRef.set({
          'id': newCustRef.id,
          'name': customerName.trim(),
          'mobile': customerMobile ?? '',
          'address': customerAddress ?? '',
          'pendingDue': invoicePendingDue,
          'totalSpent': total,
          'totalInvoices': 1,
          'createdAt': nowIso,
          'updatedAt': nowIso,
        }).catchError((_) {});
      }

      // Increment local invoice counter in shop settings as fallback
      final settings = HiveService.getShopSettings();
      final updatedSettings = ShopSettings(
        shopName: settings.shopName,
        location: settings.location,
        invoicePrefix: settings.invoicePrefix,
        invoiceSuffix: settings.invoiceSuffix,
        invoiceCounter: settings.invoiceCounter + 1,
      );
      await HiveService.saveShopSettings(updatedSettings);
    } else {
      await docRef.set(data, SetOptions(merge: true));
    }

    // Save to local Hive sales box as well
    final localSale = Sale(
      id: finalDocId,
      invoiceNumber: finalInvoiceNumber,
      date: DateTime.tryParse(finalDate) ?? DateTime.now(),
      customerName: customerName,
      items: items,
      subtotal: subtotal,
      gstAmount: gstAmount,
      total: total,
      paymentStatus: paymentStatus,
      paymentMode: paymentMode,
      isSynced: true,
    );
    await HiveService.addSale(localSale);

    return {
      'docId': finalDocId,
      'invoiceNumber': finalInvoiceNumber,
      'date': finalDate,
    };
  }

  // ── Update payment ─────────────────────────────────────────────────────────
  static Future<void> updatePayment(
      String docId, double paidAmount, String paymentStatus) async {
    await _salesCol.doc(docId).update({
      'paidAmount': paidAmount,
      'amountPaid': paidAmount,
      'paymentStatus': paymentStatus,
      'status': paymentStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Delete invoice ─────────────────────────────────────────────────────────
  static Future<void> deleteInvoice(String docId) async {
    await _salesCol.doc(docId).delete();
  }

  // ── Real-time stream with optional filters ─────────────────────────────────
  static Stream<QuerySnapshot> invoicesStream({
    DateTime? dateFrom,
    DateTime? dateTo,
  }) {
    Query query = _salesCol.orderBy('date', descending: true);

    if (dateFrom != null) {
      query = query.where('date',
          isGreaterThanOrEqualTo: dateFrom.toIso8601String());
    }
    if (dateTo != null) {
      final endDate = DateTime(dateTo.year, dateTo.month, dateTo.day + 1);
      query = query.where('date', isLessThan: endDate.toIso8601String());
    }

    return query.snapshots();
  }

  // ── Customer Directory Stream ─────────────────────────────────────────────
  static Stream<List<Customer>> streamCustomers() {
    return _customersCol.orderBy('name').snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => Customer.fromFirestore(
                  doc.data() as Map<String, dynamic>, doc.id))
              .toList(),
        );
  }

  // ── WhatsApp Direct Share ─────────────────────────────────────────────────
  static Future<void> shareInvoiceViaWhatsApp(
      Map<String, dynamic> invoice) async {
    String compName = 'WinTech-Spark';
    try {
      final compSnap = await _companyProfilesCol
          .where('isDefault', isEqualTo: true)
          .limit(1)
          .get();
      if (compSnap.docs.isNotEmpty) {
        final data = compSnap.docs.first.data() as Map<String, dynamic>;
        compName = data['companyName'] ?? compName;
      }
    } catch (_) {}

    final invNo = invoice['invoiceNumber'] ?? 'INV';
    final customerName = invoice['customerName'] ?? 'Valued Customer';
    final date = DateTime.tryParse(invoice['date'] ?? '') ?? DateTime.now();
    final dateStr = DateFormat('dd-MMM-yyyy').format(date);
    final total = (invoice['total'] ?? 0).toDouble();
    final paid =
        (invoice['paidAmount'] ?? invoice['amountPaid'] ?? 0).toDouble();
    final due = total - paid;
    final status = invoice['paymentStatus'] ?? invoice['status'] ?? 'Paid';

    String text = '⚡ *TAX INVOICE - $compName*\n';
    text += 'Invoice No: *#$invNo*\n';
    text += 'Date: $dateStr\n';
    text += 'Customer: $customerName\n';
    text += 'Total Amount: *₹${total.toStringAsFixed(2)}*\n';
    text += 'Payment Status: *$status*\n';
    if (due > 0.01) {
      text += '⚠️ Outstanding Balance: *₹${due.toStringAsFixed(2)}*\n';
    }
    text += '\nThank you for choosing $compName!';

    String phone = (invoice['customerMobile'] ?? '')
        .toString()
        .replaceAll(RegExp(r'\D'), '');
    if (phone.length == 10) {
      phone = '91$phone';
    }

    final urlString = phone.isNotEmpty
        ? 'https://wa.me/$phone?text=${Uri.encodeComponent(text)}'
        : 'https://wa.me/?text=${Uri.encodeComponent(text)}';

    final uri = Uri.parse(urlString);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── Helper: Convert Firestore doc to usable map ────────────────────────────
  static Map<String, dynamic> fromDoc(QueryDocumentSnapshot doc) {
    return doc.data() as Map<String, dynamic>;
  }
}
