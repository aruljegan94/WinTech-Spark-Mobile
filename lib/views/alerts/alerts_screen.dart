import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/models/models.dart';
import '../../services/hive_service.dart';
import '../../services/sync_service.dart';
import '../../services/invoice_service.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _currencyFormatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Store Alerts & Tasks',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'All Alerts'),
            Tab(text: 'Low Stock'),
            Tab(text: 'Unpaid Bills'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAllAlertsTab(),
          _buildLowStockTab(),
          _buildUnpaidBillsTab(),
        ],
      ),
    );
  }

  Widget _buildAllAlertsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLowStockSection(limit: 3),
          const SizedBox(height: 28),
          _buildUnpaidBillsSection(limit: 3),
        ],
      ),
    );
  }

  Widget _buildLowStockTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: _buildLowStockSection(),
    );
  }

  Widget _buildUnpaidBillsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: _buildUnpaidBillsSection(),
    );
  }

  // ── Low Stock Section ───────────────────────────────────────────────────────
  Widget _buildLowStockSection({int? limit}) {
    return ValueListenableBuilder<Box<Product>>(
      valueListenable:
          Hive.box<Product>(HiveService.productBoxName).listenable(),
      builder: (context, box, _) {
        final lowStockProducts = box.values
            .where((p) => p.stockQuantity <= 10)
            .toList()
          ..sort((a, b) => a.stockQuantity.compareTo(b.stockQuantity));

        final displayItems =
            limit != null ? lowStockProducts.take(limit).toList() : lowStockProducts;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.warning_amber_rounded,
                          color: Colors.red, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Low Stock Warnings (${lowStockProducts.length})',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (displayItems.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppColors.outlineVariant.withValues(alpha: 0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_outline_rounded,
                        color: Colors.green, size: 24),
                    SizedBox(width: 12),
                    Text('All product stocks are healthy!',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              )
            else
              ...displayItems.map((p) => _buildLowStockCard(p)),
          ],
        );
      },
    );
  }

  Widget _buildLowStockCard(Product product) {
    final isZero = product.stockQuantity <= 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isZero
              ? Colors.red.withValues(alpha: 0.4)
              : Colors.orange.withValues(alpha: 0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isZero
                            ? Colors.red.withValues(alpha: 0.1)
                            : Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isZero ? 'OUT OF STOCK' : 'LOW STOCK: ${product.stockQuantity}',
                        style: TextStyle(
                          color: isZero ? Colors.red : Colors.orange.shade800,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      product.category,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  product.productName,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Selling: ${_currencyFormatter.format(product.sellingPrice)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => _showRestockDialog(product),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Restock'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Unpaid Invoices Section ─────────────────────────────────────────────────
  Widget _buildUnpaidBillsSection({int? limit}) {
    return StreamBuilder<QuerySnapshot>(
      stream: SyncService.salesCol
          .orderBy('date', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        final allDocs = snapshot.data?.docs ?? [];
        final docs = allDocs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final status = data['paymentStatus'] ?? data['status'];
          return status == 'Pending' || status == 'Partial';
        }).toList();

        final displayDocs = limit != null ? docs.take(limit).toList() : docs;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.receipt_long_rounded,
                      color: Colors.orange, size: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  'Pending Collections (${docs.length})',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (docs.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppColors.outlineVariant.withValues(alpha: 0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.verified_rounded,
                        color: Colors.green, size: 24),
                    SizedBox(width: 12),
                    Text('No overdue or pending payments!',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              )
            else
              ...displayDocs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return _buildUnpaidBillCard(doc.id, data);
              }),
          ],
        );
      },
    );
  }

  Widget _buildUnpaidBillCard(String docId, Map<String, dynamic> data) {
    final invoiceNumber = data['invoiceNumber'] ?? 'INV';
    final customerName = data['customerName'] ?? 'Walk-in Customer';
    final total = (data['total'] ?? 0).toDouble();
    final paid = (data['paidAmount'] ?? data['amountPaid'] ?? 0).toDouble();
    final due = total - paid;
    final status = data['paymentStatus'] ?? data['status'] ?? 'Pending';

    DateTime date;
    final rawDate = data['date'];
    if (rawDate is String) {
      date = DateTime.tryParse(rawDate) ?? DateTime.now();
    } else {
      date = DateTime.now();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                invoiceNumber,
                style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                    fontSize: 14),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: status == 'Partial'
                      ? Colors.orange.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    color: status == 'Partial' ? Colors.orange : Colors.red,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                customerName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              Text(
                'Due: ${_currencyFormatter.format(due)}',
                style: const TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w800,
                    fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('dd MMM yyyy, hh:mm a').format(date),
            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () => _markPaidDialog(docId, total),
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('Mark Paid'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green,
                  side: const BorderSide(color: Colors.green),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Quick Restock Dialog ──────────────────────────────────────────────────
  void _showRestockDialog(Product product) {
    final qtyCtrl = TextEditingController(text: '10');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Restock ${product.productName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current Stock: ${product.stockQuantity}',
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Add Quantity',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.add_box_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final addQty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
              if (addQty > 0) {
                // Update local Hive
                product.stockQuantity += addQty;
                await product.save();

                // Update shared Firestore /products
                SyncService.productsCol.doc(product.id).update({
                  'stockQuantity': FieldValue.increment(addQty),
                  'updatedAt': FieldValue.serverTimestamp(),
                }).catchError((_) {});

                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Stock updated for ${product.productName}! New total: ${product.stockQuantity}'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Add Stock'),
          ),
        ],
      ),
    );
  }

  // ── Mark Paid Dialog ──────────────────────────────────────────────────────
  void _markPaidDialog(String docId, double total) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Confirm Payment'),
        content: Text(
            'Mark this invoice as fully paid (${_currencyFormatter.format(total)})?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await InvoiceService.updatePayment(docId, total, 'Paid');
              if (mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Payment recorded and synced!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Confirm Paid'),
          ),
        ],
      ),
    );
  }
}
