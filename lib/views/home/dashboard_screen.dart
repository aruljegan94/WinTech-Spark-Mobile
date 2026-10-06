import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/hive_service.dart';
import '../../services/sync_service.dart';
import '../alerts/alerts_screen.dart';
import '../billing/create_invoice_screen.dart';
import '../billing/invoice_detail_screen.dart';
import '../inventory/add_product_dialog.dart';
import '../../widgets/compact_barcode_scanner_dialog.dart';

class DashboardScreen extends StatefulWidget {
  final Function(int)? onNavigate;

  const DashboardScreen({
    super.key,
    this.onNavigate,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final NumberFormat _fmt = NumberFormat('#,##,##0', 'en_IN');
  final DateFormat _dateFmt = DateFormat('EEEE, dd MMM yyyy');

  @override
  Widget build(BuildContext context) {
    final settings = HiveService.getShopSettings();
    final shopName =
        settings.shopName.isNotEmpty ? settings.shopName : 'WinTech Spark+';

    return StreamBuilder<QuerySnapshot>(
      stream: SyncService.allSalesStream,
      builder: (context, salesSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: SyncService.allExpensesStream,
          builder: (context, expSnap) {
            return StreamBuilder<QuerySnapshot>(
              stream: SyncService.allProductsStream,
              builder: (context, prodSnap) {
                return StreamBuilder<QuerySnapshot>(
                  stream: SyncService.allPurchasesStream,
                  builder: (context, purSnap) {
                    final isInitialLoading =
                        salesSnap.connectionState == ConnectionState.waiting &&
                            !salesSnap.hasData;

                    // ── 1. Sales & Invoices Aggregation ───────────────────────
                    final salesDocs = salesSnap.data?.docs ?? [];
                    double totalBilled = 0;
                    double totalCollected = 0;
                    double totalPendingDue = 0;
                    double salesToday = 0;
                    final now = DateTime.now();

                    for (final doc in salesDocs) {
                      final data = doc.data() as Map<String, dynamic>;
                      final total = (data['total'] ?? 0).toDouble();
                      final paid = (data['paidAmount'] ??
                              data['amountPaid'] ??
                              0)
                          .toDouble();
                      final status =
                          data['paymentStatus'] ?? data['status'] ?? 'Paid';
                      final date =
                          DateTime.tryParse(data['date'] ?? '') ?? now;

                      totalBilled += total;

                      if (status == 'Paid') {
                        totalCollected += total;
                      } else if (status == 'Partial') {
                        totalCollected += paid;
                        totalPendingDue += (total - paid);
                      } else {
                        totalPendingDue += total;
                      }

                      if (date.year == now.year &&
                          date.month == now.month &&
                          date.day == now.day) {
                        salesToday += total;
                      }
                    }

                    // ── 2. Expenses & Net Margin ─────────────────────────────
                    final expDocs = expSnap.data?.docs ?? [];
                    double totalExpenses = 0;
                    for (final doc in expDocs) {
                      final data = doc.data() as Map<String, dynamic>;
                      totalExpenses += (data['amount'] ?? 0).toDouble();
                    }
                    final netMargin = totalBilled - totalExpenses;

                    // ── 3. Products & Inventory Valuation ────────────────────
                    final prodDocs = prodSnap.data?.docs ?? [];
                    double stockValuation = 0;
                    int lowStockCount = 0;
                    int outOfStockCount = 0;

                    for (final doc in prodDocs) {
                      final data = doc.data() as Map<String, dynamic>;
                      final stock =
                          (data['stockQuantity'] ?? data['stock'] ?? 0) as num;
                      final buyPrice =
                          (data['purchasePrice'] ?? data['buyingPrice'] ?? 0)
                              as num;
                      final minStock =
                          (data['minStockLevel'] ?? 5) as num;

                      stockValuation += (stock * buyPrice).toDouble();

                      if (stock <= 0) {
                        outOfStockCount++;
                      } else if (stock <= minStock) {
                        lowStockCount++;
                      }
                    }

                    // ── 4. Purchases & Supplier Dues ─────────────────────────
                    final purDocs = purSnap.data?.docs ?? [];
                    double totalPurchases = 0;
                    double supplierDues = 0;

                    for (final doc in purDocs) {
                      final data = doc.data() as Map<String, dynamic>;
                      final total = (data['totalAmount'] ?? data['total'] ?? 0)
                          .toDouble();
                      final paid = (data['amountPaid'] ?? data['paid'] ?? 0)
                          .toDouble();
                      final status = data['paymentStatus'] ?? '';

                      totalPurchases += total;
                      if (status != 'Paid') {
                        supplierDues += (total - paid).clamp(0.0, total);
                      }
                    }

                    // ── 5. Recent 5 Invoices ─────────────────────────────────
                    final recentInvoices = salesDocs.take(5).toList();
                    final isDark =
                        Theme.of(context).brightness == Brightness.dark;

                    return Scaffold(
                      backgroundColor: isDark
                          ? AppColors.darkBackground
                          : AppColors.lightBackground,
                      body: isInitialLoading
                          ? const Center(child: CircularProgressIndicator())
                          : RefreshIndicator(
                              onRefresh: () async {
                                await SyncService.uploadUnsyncedData();
                              },
                              child: SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: BouncingScrollPhysics(),
                                ),
                                padding: const EdgeInsets.fromLTRB(
                                    16, 12, 16, 120),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // ── Welcome & Date Bar ──────────────────
                                    _buildHeaderBar(shopName),

                                    const SizedBox(height: 14),

                                    // ── 1. The Grand Sales & Revenue Card ────
                                    _buildRevenueHeroCard(
                                      totalBilled: totalBilled,
                                      totalCollected: totalCollected,
                                      totalPendingDue: totalPendingDue,
                                      invoiceCount: salesDocs.length,
                                      salesToday: salesToday,
                                    ),

                                    const SizedBox(height: 14),

                                    // ── Low Stock Alert Banner (If Any) ─────
                                    if (lowStockCount > 0 ||
                                        outOfStockCount > 0) ...[
                                      _buildLowStockAlertBanner(
                                        lowCount: lowStockCount,
                                        outCount: outOfStockCount,
                                      ),
                                      const SizedBox(height: 14),
                                    ],

                                    // ── 2. Bento Grid 2x2 ────────────────────
                                    _buildBentoSummaryGrid(
                                      purchasesTotal: totalPurchases,
                                      purchasesCount: purDocs.length,
                                      supplierDues: supplierDues,
                                      stockValuation: stockValuation,
                                      productsCount: prodDocs.length,
                                      lowStockCount: lowStockCount,
                                      totalExpenses: totalExpenses,
                                      netMargin: netMargin,
                                    ),

                                    const SizedBox(height: 20),

                                    // ── 3. Quick Actions Hub ─────────────────
                                    _buildQuickActionsHub(),

                                    const SizedBox(height: 24),

                                    // ── 4. Recent Invoices Feed ──────────────
                                    _buildRecentInvoicesSection(
                                        recentInvoices),
                                  ],
                                ),
                              ),
                            ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  // ── Header Greeting Bar ────────────────────────────────────────────────────
  Widget _buildHeaderBar(String shopName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                shopName,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                  color: isDark ? AppColors.darkText100 : AppColors.lightText100,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                _dateFmt.format(DateTime.now()),
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.darkText50 : AppColors.lightText50,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF064E3B).withValues(alpha: 0.45)
                : const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? const Color(0xFF10B981).withValues(alpha: 0.35)
                  : const Color(0xFFA5D6A7),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_done_rounded,
                color: isDark ? const Color(0xFF34D399) : const Color(0xFF2E7D32),
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                'Cloud Sync',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? const Color(0xFF34D399) : const Color(0xFF2E7D32),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 1. The Grand Sales & Revenue Hero Card (Moved from Billing) ────────────
  Widget _buildRevenueHeroCard({
    required double totalBilled,
    required double totalCollected,
    required double totalPendingDue,
    required int invoiceCount,
    required double salesToday,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.revenueGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.15 : 0.25),
        ),
        boxShadow: CyberShadows.shadow100(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Label + Invoice Count Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.insights_rounded,
                        color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'TOTAL BILLED',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$invoiceCount Bills',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Total Billed Amount (Fitted for large numbers)
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '₹${_fmt.format(totalBilled)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Sub-KPI Grid: Collected + Pending Due + Today (Zero Overflow Guaranteed)
          Row(
            children: [
              // Collected
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded,
                                color: Color(0xFF69F0AE), size: 13),
                            SizedBox(width: 4),
                            Text(
                              'COLLECTED',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '₹${_fmt.format(totalCollected)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Pending Due
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.timelapse_rounded,
                                color: Color(0xFFFFD54F), size: 13),
                            SizedBox(width: 4),
                            Text(
                              'PENDING DUE',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '₹${_fmt.format(totalPendingDue)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Today's Sales
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.today_rounded,
                                color: Color(0xFF80D8FF), size: 13),
                            SizedBox(width: 4),
                            Text(
                              'TODAY',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '₹${_fmt.format(salesToday)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Low Stock Alert Banner ─────────────────────────────────────────────────
  Widget _buildLowStockAlertBanner({
    required int lowCount,
    required int outCount,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AlertsScreen()),
      ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF26140A) : const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF9A3412) : const Color(0xFFFED7AA),
          ),
          boxShadow: CyberShadows.shadow30(isDark),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: isDark ? 0.25 : 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFF97316), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Inventory Alerts',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isDark
                          ? const Color(0xFFFDBA74)
                          : const Color(0xFF9A3412),
                    ),
                  ),
                  Text(
                    outCount > 0
                        ? '$outCount out of stock, $lowCount low in stock'
                        : '$lowCount items are running low on stock',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? const Color(0xFFFB923C)
                          : const Color(0xFFC2410C),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: isDark ? const Color(0xFFFB923C) : const Color(0xFFEA580C),
            ),
          ],
        ),
      ),
    );
  }

  // ── 2. Bento Summary Grid ──────────────────────────────────────────────────
  Widget _buildBentoSummaryGrid({
    required double purchasesTotal,
    required int purchasesCount,
    required double supplierDues,
    required double stockValuation,
    required int productsCount,
    required int lowStockCount,
    required double totalExpenses,
    required double netMargin,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Row(
          children: [
            // Purchases & Supplier Dues Card
            Expanded(
              child: _BentoCard(
                icon: Icons.shopping_bag_rounded,
                iconColor: const Color(0xFF8B5CF6),
                iconBg: isDark
                    ? const Color(0xFF8B5CF6).withValues(alpha: 0.20)
                    : const Color(0xFFF3E8FF),
                title: 'PURCHASES',
                value: '₹${_fmt.format(purchasesTotal)}',
                subtitle:
                    '$purchasesCount orders • Dues: ₹${_fmt.format(supplierDues)}',
                subtitleColor: supplierDues > 0
                    ? (isDark ? const Color(0xFFFBBF24) : Colors.orange.shade800)
                    : (isDark ? AppColors.darkText50 : Colors.grey.shade600),
                onTap: () {},
              ),
            ),
            const SizedBox(width: 12),

            // Inventory Assets Card
            Expanded(
              child: _BentoCard(
                icon: Icons.inventory_2_rounded,
                iconColor: const Color(0xFF38BDF8),
                iconBg: isDark
                    ? const Color(0xFF38BDF8).withValues(alpha: 0.20)
                    : const Color(0xFFE0F2FE),
                title: 'INVENTORY VALUE',
                value: '₹${_fmt.format(stockValuation)}',
                subtitle: '$productsCount products catalogued',
                onTap: () => widget.onNavigate?.call(2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // Expenses Card
            Expanded(
              child: _BentoCard(
                icon: Icons.account_balance_wallet_rounded,
                iconColor: const Color(0xFFF43F5E),
                iconBg: isDark
                    ? const Color(0xFFF43F5E).withValues(alpha: 0.20)
                    : const Color(0xFFFFE4E6),
                title: 'EXPENSES',
                value: '₹${_fmt.format(totalExpenses)}',
                subtitle: 'Track operational costs',
                onTap: () => widget.onNavigate?.call(3),
              ),
            ),
            const SizedBox(width: 12),

            // Net Margin Card
            Expanded(
              child: _BentoCard(
                icon: Icons.trending_up_rounded,
                iconColor: const Color(0xFF10B981),
                iconBg: isDark
                    ? const Color(0xFF10B981).withValues(alpha: 0.20)
                    : const Color(0xFFD1FAE5),
                title: 'NET MARGIN',
                value: '₹${_fmt.format(netMargin)}',
                subtitle: netMargin >= 0
                    ? 'Profitable operations'
                    : 'Expenses exceed sales',
                subtitleColor: netMargin >= 0
                    ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                    : (isDark ? const Color(0xFFF87171) : Colors.redAccent),
                onTap: () {},
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── 3. Quick Actions Hub ───────────────────────────────────────────────────
  Widget _buildQuickActionsHub() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'QUICK ACTIONS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            color: isDark ? AppColors.darkText50 : AppColors.lightText50,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _QuickActionTile(
              label: 'New Bill',
              icon: Icons.add_circle_rounded,
              color: isDark ? AppColors.primaryLight : AppColors.primary,
              bgColor: AppColors.primary
                  .withValues(alpha: isDark ? 0.25 : 0.10),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CreateInvoiceScreen()),
              ),
            ),
            const SizedBox(width: 10),
            _QuickActionTile(
              label: 'Add Item',
              icon: Icons.inventory_rounded,
              color: isDark
                  ? const Color(0xFFA78BFA)
                  : const Color(0xFF7C3AED),
              bgColor: (isDark
                      ? const Color(0xFFA78BFA)
                      : const Color(0xFF7C3AED))
                  .withValues(alpha: isDark ? 0.25 : 0.12),
              onTap: () => showDialog(
                context: context,
                builder: (_) => const AddProductDialog(),
              ),
            ),
            const SizedBox(width: 10),
            _QuickActionTile(
              label: 'Scan',
              icon: Icons.qr_code_scanner_rounded,
              color: isDark
                  ? const Color(0xFF38BDF8)
                  : const Color(0xFF0284C7),
              bgColor: (isDark
                      ? const Color(0xFF38BDF8)
                      : const Color(0xFF0284C7))
                  .withValues(alpha: isDark ? 0.25 : 0.12),
              onTap: () async {
                final code = await CompactBarcodeScannerDialog.show(context);
                if (code == null || code.isEmpty || !mounted) return;
                final product = HiveService.getProductByBarcode(code);
                if (!mounted) return;
                if (product != null) {
                  showDialog(
                    context: context,
                    builder: (_) => AddProductDialog(productToEdit: product),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Barcode "$code" not found in inventory'),
                      action: SnackBarAction(
                        label: 'Add New',
                        textColor: AppColors.primaryLight,
                        onPressed: () {
                          if (mounted) {
                            showDialog(
                              context: context,
                              builder: (_) => const AddProductDialog(),
                            );
                          }
                        },
                      ),
                    ),
                  );
                }
              },
            ),
            const SizedBox(width: 10),
            _QuickActionTile(
              label: 'Alerts',
              icon: Icons.notifications_active_rounded,
              color: isDark
                  ? const Color(0xFFFBBF24)
                  : const Color(0xFFD97706),
              bgColor: (isDark
                      ? const Color(0xFFFBBF24)
                      : const Color(0xFFD97706))
                  .withValues(alpha: isDark ? 0.25 : 0.12),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AlertsScreen()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── 4. Recent Invoices Section ─────────────────────────────────────────────
  Widget _buildRecentInvoicesSection(List<QueryDocumentSnapshot> recentInvoices) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'RECENT INVOICES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: isDark ? AppColors.darkText50 : AppColors.lightText50,
              ),
            ),
            TextButton(
              onPressed: () => widget.onNavigate?.call(1),
              child: Row(
                children: [
                  Text(
                    'View All Bills',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.primaryLight : AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: isDark ? AppColors.primaryLight : AppColors.primary,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (recentInvoices.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? AppColors.darkBorder
                    : AppColors.primary.withValues(alpha: 0.15),
              ),
              boxShadow: CyberShadows.shadow30(isDark),
            ),
            child: Text(
              'No invoices recorded yet.',
              style: TextStyle(
                color: isDark ? AppColors.darkText70 : AppColors.lightText70,
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? AppColors.darkBorder
                    : AppColors.primary.withValues(alpha: 0.15),
              ),
              boxShadow: CyberShadows.shadow50(isDark),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recentInvoices.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: isDark
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.primary.withValues(alpha: 0.08),
              ),
              itemBuilder: (context, i) {
                final doc = recentInvoices[i];
                final data = doc.data() as Map<String, dynamic>;
                data['_docId'] = doc.id;

                final invNum = data['invoiceNumber'] ?? 'INV';
                final customer = data['customerName']?.isNotEmpty == true
                    ? data['customerName']
                    : 'Walk-in Customer';
                final total = (data['total'] ?? 0).toDouble();
                final status =
                    data['paymentStatus'] ?? data['status'] ?? 'Paid';
                final date =
                    DateTime.tryParse(data['date'] ?? '') ?? DateTime.now();

                Color statusColor = const Color(0xFF10B981);
                if (status == 'Partial') {
                  statusColor = const Color(0xFFF59E0B);
                } else if (status == 'Pending') {
                  statusColor = const Color(0xFFEF4444);
                }

                return ListTile(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InvoiceDetailScreen(invoice: data),
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary
                          .withValues(alpha: isDark ? 0.20 : 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.receipt_rounded,
                        color:
                            isDark ? AppColors.primaryLight : AppColors.primary,
                        size: 18),
                  ),
                  title: Row(
                    children: [
                      Text(
                        invNum,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isDark
                              ? AppColors.darkText100
                              : AppColors.lightText100,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor
                              .withValues(alpha: isDark ? 0.25 : 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: statusColor
                                .withValues(alpha: isDark ? 0.40 : 0.25),
                          ),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    '$customer • ${DateFormat('dd MMM').format(date)}',
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          isDark ? AppColors.darkText70 : AppColors.lightText50,
                    ),
                  ),
                  trailing: Text(
                    '₹${_fmt.format(total)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: isDark
                          ? AppColors.darkText100
                          : AppColors.lightText100,
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

// ── Bento Card Subwidget ─────────────────────────────────────────────────────
class _BentoCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String value;
  final String subtitle;
  final Color? subtitleColor;
  final VoidCallback onTap;

  const _BentoCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.value,
    required this.subtitle,
    this.subtitleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? AppColors.darkBorder
                : AppColors.primary.withValues(alpha: 0.15),
          ),
          boxShadow: CyberShadows.shadow50(isDark),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 18),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 11,
                  color: isDark ? AppColors.darkText30 : AppColors.lightText30,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: isDark ? AppColors.darkText50 : AppColors.lightText50,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                  color:
                      isDark ? AppColors.darkText100 : AppColors.lightText100,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: subtitleColor ??
                    (isDark ? AppColors.darkText70 : AppColors.lightText70),
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Quick Action Tile ────────────────────────────────────────────────────────
class _QuickActionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? AppColors.darkBorder
                  : AppColors.primary.withValues(alpha: 0.15),
            ),
            boxShadow: CyberShadows.shadow30(isDark),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkText100 : AppColors.lightText100,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
