import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/invoice_service.dart';
import '../../services/pdf_service.dart';
import 'create_invoice_screen.dart';
import 'invoice_detail_screen.dart';
import 'widgets/thermal_print_dialog.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final _fmt = NumberFormat('#,##,##0.00', 'en_IN');
  final _searchCtrl = TextEditingController();

  String? _statusFilter; // null = all, 'Paid', 'Pending', 'Partial'
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String _searchQuery = '';

  final List<String> _tabs = ['All', 'Paid', 'Pending', 'Partial'];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      body: StreamBuilder<QuerySnapshot>(
        stream: InvoiceService.invoicesStream(
          dateFrom: _dateFrom,
          dateTo: _dateTo,
        ),
        builder: (context, snapshot) {
          final allDocs = snapshot.data?.docs ?? [];

          // ── Status Counts ─────────────────────────────────────────────
          int paidCount = 0;
          int pendingCount = 0;
          int partialCount = 0;

          for (final doc in allDocs) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['paymentStatus'] ?? data['status'] ?? 'Paid';

            if (status == 'Paid') {
              paidCount++;
            } else if (status == 'Partial') {
              partialCount++;
            } else {
              pendingCount++;
            }
          }

          // ── Filter by paymentStatus & search query ────────────────────────
          var filteredDocs = allDocs;

          if (_statusFilter != null) {
            filteredDocs = filteredDocs.where((d) {
              final data = d.data() as Map<String, dynamic>;
              final status = data['paymentStatus'] ?? data['status'];
              return status == _statusFilter;
            }).toList();
          }

          if (_searchQuery.isNotEmpty) {
            filteredDocs = filteredDocs.where((d) {
              final data = d.data() as Map<String, dynamic>;
              final inv = (data['invoiceNumber'] ?? '').toString().toLowerCase();
              final cust = (data['customerName'] ?? '').toString().toLowerCase();
              final mobile = (data['customerMobile'] ?? '').toString().toLowerCase();
              return inv.contains(_searchQuery) ||
                  cust.contains(_searchQuery) ||
                  mobile.contains(_searchQuery);
            }).toList();
          }

          return Column(
            children: [
              // ── Search & Date Range Bar ──────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurface : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark
                                ? AppColors.darkBorder
                                : AppColors.outlineVariant.withValues(alpha: 0.15),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                  alpha: isDark ? 0.25 : 0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _searchCtrl,
                          style: TextStyle(
                            color: isDark
                                ? AppColors.darkText100
                                : AppColors.lightText100,
                            fontSize: 13,
                          ),
                          onChanged: (v) =>
                              setState(() => _searchQuery = v.toLowerCase()),
                          decoration: InputDecoration(
                            hintText: 'Search invoice, customer or mobile…',
                            hintStyle: TextStyle(
                              color: isDark
                                  ? AppColors.darkText50
                                  : Colors.grey.shade400,
                              fontSize: 13,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              size: 20,
                              color: isDark
                                  ? AppColors.darkText50
                                  : Colors.grey,
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: Icon(
                                      Icons.clear_rounded,
                                      size: 18,
                                      color: isDark
                                          ? AppColors.darkText50
                                          : Colors.grey,
                                    ),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _FilterIconButton(
                      icon: Icons.calendar_month_rounded,
                      active: _dateFrom != null,
                      onTap: _pickDateRange,
                    ),
                  ],
                ),
              ),

              // ── Active Date Range Indicator ─────────────────────────
              if (_dateFrom != null)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(
                              alpha: isDark ? 0.25 : 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.date_range_rounded,
                                color: isDark
                                    ? AppColors.primaryLight
                                    : AppColors.primary,
                                size: 14),
                            const SizedBox(width: 6),
                            Text(
                              '${DateFormat('dd MMM').format(_dateFrom!)} - ${DateFormat('dd MMM yyyy').format(_dateTo!)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppColors.primaryLight
                                    : AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => setState(() {
                                _dateFrom = null;
                                _dateTo = null;
                              }),
                              child: Icon(Icons.cancel_rounded,
                                  size: 14,
                                  color: isDark
                                      ? AppColors.primaryLight
                                      : AppColors.primary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Modern Status Chips Row ──────────────────────────────
              _buildStatusTabs(
                allCount: allDocs.length,
                paidCount: paidCount,
                pendingCount: pendingCount,
                partialCount: partialCount,
                isDark: isDark,
              ),

              const SizedBox(height: 4),

              // ── Invoice Cards List ──────────────────────────────────
              Expanded(
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const Center(child: CircularProgressIndicator())
                    : filteredDocs.isEmpty
                        ? _buildEmptyState(isDark)
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                            physics: const BouncingScrollPhysics(),
                            itemCount: filteredDocs.length,
                            itemBuilder: (context, i) {
                              final doc = filteredDocs[i];
                              final data = doc.data() as Map<String, dynamic>;
                              data['_docId'] = doc.id;
                              return _ModernInvoiceCard(
                                data: data,
                                fmt: _fmt,
                                onAction: (action) =>
                                    _handleAction(action, data),
                              );
                            },
                          ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 90),
        child: FloatingActionButton.extended(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const CreateInvoiceScreen()),
          ),
          backgroundColor: AppColors.primary,
          elevation: 4,
          icon: const Icon(Icons.add_shopping_cart_rounded,
              color: Colors.white, size: 20),
          label: const Text(
            'New Bill',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }

  // ── Status Segmented Tabs ──────────────────────────────────────────────────
  Widget _buildStatusTabs({
    required int allCount,
    required int paidCount,
    required int pendingCount,
    required int partialCount,
    required bool isDark,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: _tabs.map((tab) {
          final isSelected =
              (_statusFilter == null && tab == 'All') || _statusFilter == tab;

          int count = allCount;
          if (tab == 'Paid') count = paidCount;
          if (tab == 'Pending') count = pendingCount;
          if (tab == 'Partial') count = partialCount;

          Color activeColor = AppColors.primary;
          if (tab == 'Paid') activeColor = const Color(0xFF10B981);
          if (tab == 'Pending') activeColor = const Color(0xFFEF4444);
          if (tab == 'Partial') activeColor = const Color(0xFFF59E0B);

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: isSelected,
              showCheckmark: false,
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tab,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : (isDark ? AppColors.darkText70 : Colors.grey.shade700),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.25)
                          : (isDark
                              ? Colors.white12
                              : Colors.grey.withValues(alpha: 0.15)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? Colors.white
                            : (isDark
                                ? AppColors.darkText100
                                : Colors.grey.shade800),
                      ),
                    ),
                  ),
                ],
              ),
              backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
              selectedColor: activeColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected
                      ? activeColor
                      : (isDark
                          ? AppColors.darkBorder
                          : AppColors.outlineVariant.withValues(alpha: 0.25)),
                ),
              ),
              onSelected: (_) {
                setState(() {
                  _statusFilter = tab == 'All' ? null : tab;
                });
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Action Handlers ────────────────────────────────────────────────────────
  void _handleAction(String action, Map<String, dynamic> data) {
    switch (action) {
      case 'view':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InvoiceDetailScreen(invoice: data),
          ),
        );
        break;
      case 'whatsapp':
        InvoiceService.shareInvoiceViaWhatsApp(data);
        break;
      case 'thermal':
        ThermalPrintDialog.show(context, invoice: data);
        break;
      case 'pay':
        _showUpdatePaymentSheet(data);
        break;
      case 'edit':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CreateInvoiceScreen(editData: data),
          ),
        );
        break;
      case 'delete':
        _confirmDelete(data);
        break;
      case 'download':
        PdfService.shareInvoice(data);
        break;
      case 'print':
        PdfService.printInvoice(data);
        break;
    }
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (range != null) {
      setState(() {
        _dateFrom = range.start;
        _dateTo = range.end;
      });
    }
  }

  void _showUpdatePaymentSheet(Map<String, dynamic> data) {
    final total = (data['total'] ?? 0).toDouble();
    final paidAmount =
        (data['paidAmount'] ?? data['amountPaid'] ?? 0).toDouble();
    final ctrl = TextEditingController(text: paidAmount.toStringAsFixed(2));
    String selectedStatus = data['paymentStatus'] ?? data['status'] ?? 'Pending';

    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : Colors.transparent,
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
                      color: AppColors.primary.withValues(alpha: isDark ? 0.25 : 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.payments_rounded,
                        color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Record Payment',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: isDark
                              ? AppColors.darkText100
                              : AppColors.lightText100,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${data['invoiceNumber']} • Total: ₹${_fmt.format(total)}',
                style: TextStyle(
                  color: isDark ? AppColors.darkText50 : Colors.grey,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: ctrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                style: TextStyle(
                  color: isDark
                      ? AppColors.darkText100
                      : AppColors.lightText100,
                ),
                decoration: InputDecoration(
                  labelText: 'Amount Paid (₹)',
                  labelStyle: TextStyle(
                    color: isDark ? AppColors.darkText70 : null,
                  ),
                  prefixIcon: Icon(
                    Icons.currency_rupee_rounded,
                    color: isDark ? AppColors.darkText70 : Colors.grey.shade700,
                  ),
                  filled: true,
                  fillColor: isDark
                      ? AppColors.darkSurfaceElevated
                      : AppColors.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: isDark ? AppColors.darkBorder : Colors.transparent,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: isDark ? AppColors.darkBorder : Colors.transparent,
                    ),
                  ),
                ),
                onChanged: (v) {
                  final paid = double.tryParse(v) ?? 0;
                  setModalState(() {
                    if (paid >= total) {
                      selectedStatus = 'Paid';
                    } else if (paid > 0) {
                      selectedStatus = 'Partial';
                    } else {
                      selectedStatus = 'Pending';
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: ['Paid', 'Partial', 'Pending'].map((s) {
                  final isSelected = selectedStatus == s;
                  Color col = const Color(0xFF10B981);
                  if (s == 'Partial') col = const Color(0xFFF59E0B);
                  if (s == 'Pending') col = const Color(0xFFEF4444);

                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setModalState(() {
                          selectedStatus = s;
                          if (s == 'Paid') ctrl.text = total.toStringAsFixed(2);
                          if (s == 'Pending') ctrl.text = '0.00';
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? col.withValues(alpha: isDark ? 0.25 : 0.15)
                              : (isDark
                                  ? Colors.white10
                                  : Colors.grey.withValues(alpha: 0.08)),
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected
                              ? Border.all(color: col, width: 1.5)
                              : Border.all(
                                  color: isDark
                                      ? AppColors.darkBorder
                                      : Colors.transparent),
                        ),
                        child: Text(
                          s,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? col
                                : (isDark
                                    ? AppColors.darkText70
                                    : Colors.grey.shade700),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final paid = double.tryParse(ctrl.text.trim()) ?? 0;
                    await InvoiceService.updatePayment(
                      data['_docId'],
                      paid,
                      selectedStatus,
                    );
                    if (!mounted) return;
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Payment updated & synced!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Save Payment',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> data) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isDark ? AppColors.darkBorder : Colors.transparent,
          ),
        ),
        title: Text(
          'Delete Invoice',
          style: TextStyle(
            color: isDark ? AppColors.darkText100 : AppColors.lightText100,
          ),
        ),
        content: Text(
          'Are you sure you want to delete invoice ${data['invoiceNumber']}?',
          style: TextStyle(
            color: isDark ? AppColors.darkText70 : Colors.grey.shade700,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? AppColors.darkText50 : Colors.grey.shade600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              await InvoiceService.deleteInvoice(data['_docId']);
              if (!mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Invoice deleted'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: isDark ? 0.15 : 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.receipt_long_rounded,
                size: 56, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(
            'No invoices found',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: isDark ? AppColors.darkText100 : AppColors.lightText100,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap "New Bill" below to generate your first invoice',
            style: TextStyle(
              color: isDark ? AppColors.darkText50 : Colors.grey.shade500,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Modern Compact Invoice Card ──────────────────────────────────────────────
class _ModernInvoiceCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final NumberFormat fmt;
  final Function(String) onAction;

  const _ModernInvoiceCard({
    required this.data,
    required this.fmt,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = data['paymentStatus'] ?? data['status'] ?? 'Paid';
    final total = (data['total'] ?? 0).toDouble();
    final paidAmount =
        (data['paidAmount'] ?? data['amountPaid'] ?? 0).toDouble();
    final balance = (total - paidAmount).clamp(0.0, total);
    final invoiceDate =
        DateTime.tryParse(data['date'] ?? '') ?? DateTime.now();

    final items = (data['items'] as List?) ?? [];
    final itemsCount = items.length;
    final firstItemName =
        items.isNotEmpty ? (items.first['productName'] ?? '') : '';

    Color statusColor =
        isDark ? const Color(0xFF4ADE80) : const Color(0xFF2E7D32);
    Color statusBg =
        isDark ? const Color(0xFF143820) : const Color(0xFFE8F5E9);

    if (status == 'Partial') {
      statusColor =
          isDark ? const Color(0xFFFBBF24) : const Color(0xFFEF6C00);
      statusBg =
          isDark ? const Color(0xFF3B2610) : const Color(0xFFFFF3E0);
    } else if (status == 'Pending') {
      statusColor =
          isDark ? const Color(0xFFF87171) : const Color(0xFFC62828);
      statusBg =
          isDark ? const Color(0xFF381515) : const Color(0xFFFFEBEE);
    }

    final customerName = (data['customerName'] ?? '').toString().trim();
    final customerMobile = (data['customerMobile'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status == 'Paid'
              ? (isDark
                  ? AppColors.darkBorder
                  : AppColors.outlineVariant.withValues(alpha: 0.15))
              : statusColor.withValues(alpha: isDark ? 0.40 : 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onAction('view'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Line 1: Invoice # + Status Badge (Left)  ───  Net Total (Right) ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Invoice Number Monospace Badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.primaryLight.withValues(alpha: 0.15)
                          : AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      data['invoiceNumber'] ?? 'INV',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w900,
                        color:
                            isDark ? AppColors.primaryLight : AppColors.primary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Status Badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Net Total with prominent text (aligned cleanly to the right, never truncated)
                  Text(
                    '₹${fmt.format(total)}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16.5,
                      letterSpacing: -0.3,
                      color: isDark
                          ? AppColors.darkText100
                          : AppColors.lightText100,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 5),

              // ── Line 2: Customer Name (Left)  ───  Invoice Date (Right) ─────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      customerName.isNotEmpty
                          ? customerName
                          : 'Walk-in Customer',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: isDark
                            ? AppColors.darkText100
                            : AppColors.lightText100,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('dd MMM, hh:mm a').format(invoiceDate),
                    style: TextStyle(
                      color:
                          isDark ? AppColors.darkText50 : Colors.grey.shade500,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 5),

              // ── Line 3: Mobile & Due/Items summary (Left)  ───  Actions (Right) ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Customer details & balance
                  Expanded(
                    child: Row(
                      children: [
                        if (customerMobile.isNotEmpty) ...[
                          Text(
                            customerMobile,
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.darkText50
                                  : Colors.grey.shade600,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            ' • ',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white24
                                  : Colors.grey.shade400,
                              fontSize: 11,
                            ),
                          ),
                        ],
                        if (status != 'Paid') ...[
                          Text(
                            'Due: ₹${fmt.format(balance)}',
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5,
                            ),
                          ),
                        ] else ...[
                          Flexible(
                            child: Text(
                              itemsCount > 0
                                  ? '$itemsCount item${itemsCount > 1 ? 's' : ''}${firstItemName.isNotEmpty ? ' • $firstItemName' : ''}'
                                  : 'Paid in full',
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.darkText50
                                    : Colors.grey.shade500,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Quick Action Buttons Row (Right)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // WhatsApp Quick Share
                      _ActionIconButton(
                        icon: Icons.chat_rounded,
                        color: const Color(0xFF25D366),
                        bgColor: const Color(0xFF25D366)
                            .withValues(alpha: isDark ? 0.18 : 0.12),
                        tooltip: 'Share on WhatsApp',
                        onTap: () => onAction('whatsapp'),
                      ),
                      const SizedBox(width: 6),

                      // Thermal Print (2" / 3")
                      _ActionIconButton(
                        icon: Icons.receipt_long_rounded,
                        color: const Color(0xFF3B82F6),
                        bgColor: const Color(0xFF3B82F6)
                            .withValues(alpha: isDark ? 0.18 : 0.10),
                        tooltip: 'Thermal Receipt (2" / 3")',
                        onTap: () => onAction('thermal'),
                      ),

                      // Collect Payment if pending/partial
                      if (status != 'Paid') ...[
                        const SizedBox(width: 6),
                        _ActionIconButton(
                          icon: Icons.payments_rounded,
                          color: const Color(0xFFF59E0B),
                          bgColor: const Color(0xFFF59E0B)
                              .withValues(alpha: isDark ? 0.18 : 0.12),
                          tooltip: 'Record Payment',
                          onTap: () => onAction('pay'),
                        ),
                      ],

                      // More Actions
                      PopupMenuButton<String>(
                        onSelected: onAction,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        color: isDark
                            ? AppColors.darkSurfaceElevated
                            : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: isDark
                                ? AppColors.darkBorder
                                : Colors.transparent,
                          ),
                        ),
                        icon: Icon(Icons.more_vert_rounded,
                            color: isDark
                                ? AppColors.darkText50
                                : Colors.grey,
                            size: 18),
                        itemBuilder: (_) => [
                          _menuItem(
                            'view',
                            'View Bill',
                            Icons.visibility_rounded,
                            isDark: isDark,
                          ),
                          _menuItem(
                            'thermal',
                            'Thermal Receipt (2"/3")',
                            Icons.receipt_long_rounded,
                            isDark: isDark,
                          ),
                          _menuItem(
                            'whatsapp',
                            'Share on WhatsApp',
                            Icons.chat_bubble_rounded,
                            isDark: isDark,
                          ),
                          if (status != 'Paid')
                            _menuItem(
                              'pay',
                              'Record Payment',
                              Icons.payments_rounded,
                              isDark: isDark,
                            ),
                          _menuItem(
                            'edit',
                            'Edit Bill',
                            Icons.edit_rounded,
                            isDark: isDark,
                          ),
                          _menuItem(
                            'download',
                            'Download A4 PDF',
                            Icons.download_rounded,
                            isDark: isDark,
                          ),
                          _menuItem(
                            'print',
                            'Print A4 PDF',
                            Icons.print_rounded,
                            isDark: isDark,
                          ),
                          const PopupMenuDivider(
                            height: 1,
                          ),
                          _menuItem(
                            'delete',
                            'Delete',
                            Icons.delete_outline_rounded,
                            isDestructive: true,
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),

              // Subtle Progress Bar for Partial Payments
              if (status == 'Partial') ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: total > 0
                        ? (paidAmount / total).clamp(0.0, 1.0)
                        : 0,
                    backgroundColor:
                        isDark ? Colors.white12 : Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFF59E0B)),
                    minHeight: 3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    String label,
    IconData icon, {
    bool isDestructive = false,
    bool isDark = false,
  }) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: isDestructive
                ? Colors.redAccent
                : (isDark ? AppColors.darkText70 : Colors.grey.shade700),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDestructive
                  ? Colors.redAccent
                  : (isDark ? AppColors.darkText100 : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bgColor;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionIconButton({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}

class _FilterIconButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _FilterIconButton({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary
              : (isDark ? AppColors.darkSurface : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? AppColors.primary
                : (isDark
                    ? AppColors.darkBorder
                    : AppColors.outlineVariant.withValues(alpha: 0.15)),
          ),
          boxShadow: [
            BoxShadow(
              color: active
                  ? AppColors.primary.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(
          icon,
          size: 20,
          color: active
              ? Colors.white
              : (isDark ? AppColors.darkText70 : Colors.grey.shade700),
        ),
      ),
    );
  }
}
