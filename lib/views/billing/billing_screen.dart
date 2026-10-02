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
    return Scaffold(
      backgroundColor: AppColors.surface,
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
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (v) =>
                              setState(() => _searchQuery = v.toLowerCase()),
                          decoration: InputDecoration(
                            hintText: 'Search invoice, customer or mobile…',
                            hintStyle: TextStyle(
                                color: Colors.grey.shade400, fontSize: 13),
                            prefixIcon: const Icon(Icons.search_rounded,
                                size: 20, color: Colors.grey),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded,
                                        size: 18, color: Colors.grey),
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
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.date_range_rounded,
                                color: AppColors.primary, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              '${DateFormat('dd MMM').format(_dateFrom!)} - ${DateFormat('dd MMM yyyy').format(_dateTo!)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => setState(() {
                                _dateFrom = null;
                                _dateTo = null;
                              }),
                              child: const Icon(Icons.cancel_rounded,
                                  size: 14, color: AppColors.primary),
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
              ),

              const SizedBox(height: 4),

              // ── Invoice Cards List ──────────────────────────────────
              Expanded(
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const Center(child: CircularProgressIndicator())
                    : filteredDocs.isEmpty
                        ? _buildEmptyState()
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
          if (tab == 'Paid') activeColor = Colors.green;
          if (tab == 'Pending') activeColor = Colors.redAccent;
          if (tab == 'Partial') activeColor = Colors.orange;

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
                      color: isSelected ? Colors.white : Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.25)
                          : Colors.grey.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : Colors.grey.shade800,
                      ),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.white,
              selectedColor: activeColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected
                      ? activeColor
                      : AppColors.outlineVariant.withValues(alpha: 0.25),
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.payments_rounded,
                        color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Record Payment',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${data['invoiceNumber']} • Total: ₹${_fmt.format(total)}',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: ctrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Amount Paid (₹)',
                  prefixIcon: const Icon(Icons.currency_rupee_rounded),
                  filled: true,
                  fillColor: AppColors.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
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
                  Color col = Colors.green;
                  if (s == 'Partial') col = Colors.orange;
                  if (s == 'Pending') col = Colors.redAccent;

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
                              ? col.withValues(alpha: 0.15)
                              : Colors.grey.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected
                              ? Border.all(color: col, width: 1.5)
                              : null,
                        ),
                        child: Text(
                          s,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? col : Colors.grey.shade700,
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
                    if (mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Payment updated & synced!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Invoice'),
        content: Text(
            'Are you sure you want to delete invoice ${data['invoiceNumber']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await InvoiceService.deleteInvoice(data['_docId']);
              if (mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Invoice deleted'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.receipt_long_rounded,
                size: 56, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          const Text(
            'No invoices found',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap "New Bill" below to generate your first invoice',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
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

    Color statusColor = const Color(0xFF2E7D32);
    Color statusBg = const Color(0xFFE8F5E9);
    if (status == 'Partial') {
      statusColor = const Color(0xFFEF6C00);
      statusBg = const Color(0xFFFFF3E0);
    } else if (status == 'Pending') {
      statusColor = const Color(0xFFC62828);
      statusBg = const Color(0xFFFFEBEE);
    }

    final customerName = (data['customerName'] ?? '').toString().trim();
    final customerMobile = (data['customerMobile'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status == 'Paid'
              ? AppColors.outlineVariant.withValues(alpha: 0.15)
              : statusColor.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onAction('view'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top Row: Invoice # + Status Badge + Date + Net Total ─────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Invoice Number Monospace Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      data['invoiceNumber'] ?? 'INV',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Status Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
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
                  const SizedBox(width: 8),

                  // Date
                  Text(
                    DateFormat('dd MMM, hh:mm a').format(invoiceDate),
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 11,
                    ),
                  ),

                  const Spacer(),

                  // Net Total with FittedBox (Handles large numbers gracefully)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        '₹${fmt.format(total)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),

              // ── Bottom Row: Customer & items info + Action Buttons ───────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Customer Info (Left)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customerName.isNotEmpty
                              ? customerName
                              : 'Walk-in Customer',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Row(
                          children: [
                            if (customerMobile.isNotEmpty) ...[
                              Text(
                                customerMobile,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 11,
                                ),
                              ),
                              Text(' • ',
                                  style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 11)),
                            ],
                            Flexible(
                              child: Text(
                                itemsCount > 0
                                    ? '$itemsCount item${itemsCount > 1 ? 's' : ''}${firstItemName.isNotEmpty ? ' • $firstItemName' : ''}'
                                    : 'No items',
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (status != 'Paid') ...[
                              Text(' • ',
                                  style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 11)),
                              Text(
                                'Due: ₹${fmt.format(balance)}',
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        ),
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
                        color: const Color(0xFF1EBE5D),
                        bgColor:
                            const Color(0xFF25D366).withValues(alpha: 0.12),
                        tooltip: 'Share on WhatsApp',
                        onTap: () => onAction('whatsapp'),
                      ),
                      const SizedBox(width: 6),

                      // Thermal Print (2" / 3")
                      _ActionIconButton(
                        icon: Icons.receipt_long_rounded,
                        color: const Color(0xFF1A73E8),
                        bgColor:
                            const Color(0xFF1A73E8).withValues(alpha: 0.1),
                        tooltip: 'Thermal Print (2" / 3")',
                        onTap: () => onAction('thermal'),
                      ),

                      // Collect Payment if pending
                      if (status != 'Paid') ...[
                        const SizedBox(width: 6),
                        _ActionIconButton(
                          icon: Icons.payments_rounded,
                          color: Colors.orange.shade800,
                          bgColor: Colors.orange.withValues(alpha: 0.12),
                          tooltip: 'Record Payment',
                          onTap: () => onAction('pay'),
                        ),
                      ],

                      // More Actions
                      PopupMenuButton<String>(
                        onSelected: onAction,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        icon: const Icon(Icons.more_vert_rounded,
                            color: Colors.grey, size: 18),
                        itemBuilder: (_) => [
                          _menuItem(
                              'view', 'View Bill', Icons.visibility_rounded),
                          _menuItem('thermal', 'Thermal Receipt (2"/3")',
                              Icons.receipt_long_rounded),
                          _menuItem('whatsapp', 'Share on WhatsApp',
                              Icons.chat_bubble_rounded),
                          if (status != 'Paid')
                            _menuItem('pay', 'Record Payment',
                                Icons.payments_rounded),
                          _menuItem('edit', 'Edit Bill', Icons.edit_rounded),
                          _menuItem('download', 'Download A4 PDF',
                              Icons.download_rounded),
                          _menuItem(
                              'print', 'Print A4 PDF', Icons.print_rounded),
                          const PopupMenuDivider(),
                          _menuItem('delete', 'Delete',
                              Icons.delete_outline_rounded,
                              isDestructive: true),
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
                    value:
                        total > 0 ? (paidAmount / total).clamp(0.0, 1.0) : 0,
                    backgroundColor: Colors.grey.shade200,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.orange),
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

  PopupMenuItem<String> _menuItem(String value, String label, IconData icon,
      {bool isDestructive = false}) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon,
              size: 18,
              color: isDestructive ? Colors.red : Colors.grey.shade700),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDestructive ? Colors.red : Colors.black87,
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: active
                  ? AppColors.primary.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(
          icon,
          size: 20,
          color: active ? Colors.white : Colors.grey.shade700,
        ),
      ),
    );
  }
}
