import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme.dart';
import '../../core/models/models.dart';
import '../../services/hive_service.dart';
import '../../services/sync_service.dart';
import '../../services/invoice_service.dart';
import '../../services/alert_service.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final _currencyFormatter =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹');

  String _selectedFilter = 'all'; // 'all', 'low_stock', 'unpaid', 'tasks'
  final Set<String> _readyAlertIds = {};
  final Set<String> _dismissedAlertIds = {};
  List<Map<String, dynamic>> _customTasks = [];
  late Stream<QuerySnapshot> _salesStream;

  @override
  void initState() {
    super.initState();
    // Initialize preferences synchronously without setState in initState
    _readyAlertIds.addAll(AlertService.readyAlertIds);
    _dismissedAlertIds.addAll(AlertService.dismissedAlertIds);
    _customTasks = List<Map<String, dynamic>>.from(AlertService.customTasks);

    // Cache stream instance to prevent re-subscriptions on build passes
    try {
      _salesStream = SyncService.salesCol
          .orderBy('date', descending: true)
          .snapshots();
    } catch (_) {
      _salesStream = SyncService.salesCol.snapshots();
    }
  }

  Future<void> _saveAlertPreferences() async {
    await AlertService.saveReadyAlertIds(_readyAlertIds);
    await AlertService.saveDismissedAlertIds(_dismissedAlertIds);
    await AlertService.saveCustomTasks(_customTasks);
  }

  void _toggleAlertReady(String id) {
    setState(() {
      if (_readyAlertIds.contains(id)) {
        _readyAlertIds.remove(id);
      } else {
        _readyAlertIds.add(id);
      }
    });
    _saveAlertPreferences();

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _readyAlertIds.contains(id)
              ? 'Alert marked as Ready / Resolved!'
              : 'Alert restored to active.',
        ),
        duration: const Duration(seconds: 2),
        backgroundColor:
            _readyAlertIds.contains(id) ? Colors.green : AppColors.primary,
      ),
    );
  }

  void _dismissAlert(String id, String label) {
    setState(() {
      _dismissedAlertIds.add(id);
    });
    _saveAlertPreferences();

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cleared alert "$label"'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: const Color(0xFF69F0AE),
          onPressed: () {
            setState(() {
              _dismissedAlertIds.remove(id);
            });
            _saveAlertPreferences();
          },
        ),
      ),
    );
  }

  void _clearAllReadyAlerts() {
    if (_readyAlertIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No alerts are currently marked as ready to clear.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final clearedCount = _readyAlertIds.length;
    setState(() {
      _dismissedAlertIds.addAll(_readyAlertIds);
      _readyAlertIds.clear();
      _customTasks.removeWhere((t) => t['isReady'] == true);
    });
    _saveAlertPreferences();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cleared $clearedCount resolved alerts!'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: Text(
          'Store Alerts & Tasks',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: isDark ? AppColors.darkText100 : AppColors.lightText100,
          ),
        ),
        actions: [
          // Clear All Ready Button
          IconButton(
            tooltip: 'Clear All Ready Alerts',
            icon: Icon(
              Icons.cleaning_services_rounded,
              color: isDark ? const Color(0xFF69F0AE) : const Color(0xFF059669),
            ),
            onPressed: _clearAllReadyAlerts,
          ),
          // Add Store Task Button
          IconButton(
            tooltip: 'Add Store Task',
            icon: Icon(
              Icons.add_task_rounded,
              color: isDark ? AppColors.primaryLight : AppColors.primary,
            ),
            onPressed: () => _showAddTaskDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Quick Filter Tabs / Chips ──────────────────────────────────────
          _buildFilterChips(isDark),

          // ── Scrollable Body ───────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
              child: _buildFilteredContent(isDark),
            ),
          ),
        ],
      ),
    );
  }

  // ── Filter Chips Bar ────────────────────────────────────────────────────────
  Widget _buildFilterChips(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppColors.darkBorder
                : AppColors.outlineVariant.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: ValueListenableBuilder<Box<Product>>(
        valueListenable:
            Hive.box<Product>(HiveService.productBoxName).listenable(),
        builder: (context, productBox, _) {
          final threshold = AlertService.lowStockThreshold;
          final lowStockCount = productBox.values.where((p) {
            return p.stockQuantity <= threshold &&
                !_dismissedAlertIds.contains(p.id) &&
                !_readyAlertIds.contains(p.id);
          }).length;

          final pendingTasksCount = _customTasks.where((t) {
            final id = t['id'] as String? ?? '';
            final isReady = t['isReady'] == true || _readyAlertIds.contains(id);
            final isDismissed = _dismissedAlertIds.contains(id);
            return !isReady && !isDismissed;
          }).length;

          final totalActive = lowStockCount + pendingTasksCount;

          final filters = [
            {'id': 'all', 'label': 'All Alerts', 'count': totalActive},
            {'id': 'low_stock', 'label': 'Low Stock', 'count': lowStockCount},
            {'id': 'unpaid', 'label': 'Pending Bills', 'count': null},
            {'id': 'tasks', 'label': 'Store Tasks', 'count': pendingTasksCount},
          ];

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: filters.map((f) {
                final isSelected = _selectedFilter == f['id'];
                final count = f['count'] as int?;

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: isSelected,
                    onSelected: (val) {
                      setState(() => _selectedFilter = f['id'] as String);
                    },
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          f['label'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? Colors.white
                                : (isDark
                                    ? AppColors.darkText70
                                    : AppColors.lightText70),
                          ),
                        ),
                        if (count != null && count > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.25)
                                  : Colors.redAccent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$count',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    backgroundColor: isDark
                        ? AppColors.darkSurfaceElevated
                        : Colors.grey.shade100,
                    selectedColor: AppColors.primary,
                    checkmarkColor: Colors.white,
                    side: BorderSide(
                      color: isSelected
                          ? AppColors.primary
                          : (isDark
                              ? AppColors.darkBorder
                              : Colors.grey.shade300),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }

  // ── Filtered Content ────────────────────────────────────────────────────────
  Widget _buildFilteredContent(bool isDark) {
    switch (_selectedFilter) {
      case 'low_stock':
        return _buildLowStockSection(isDark);
      case 'unpaid':
        return _buildUnpaidBillsSection(isDark);
      case 'tasks':
        return _buildStoreTasksSection(isDark);
      case 'all':
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStoreTasksSection(isDark, limit: 3),
            const SizedBox(height: 20),
            _buildLowStockSection(isDark, limit: 10),
            const SizedBox(height: 20),
            _buildUnpaidBillsSection(isDark, limit: 5),
          ],
        );
    }
  }

  // ── 1. Store Tasks Section ──────────────────────────────────────────────────
  Widget _buildStoreTasksSection(bool isDark, {int? limit}) {
    final activeTasks = _customTasks.where((t) {
      final id = t['id'] as String;
      return !_dismissedAlertIds.contains(id);
    }).toList();

    final pendingCount = activeTasks.where((t) {
      final id = t['id'] as String;
      return t['isReady'] != true && !_readyAlertIds.contains(id);
    }).length;

    final displayTasks =
        limit != null ? activeTasks.take(limit).toList() : activeTasks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.primary
                        .withValues(alpha: isDark ? 0.25 : 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.assignment_outlined,
                      color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 8),
                Text(
                  'Store Tasks ($pendingCount)',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color:
                        isDark ? AppColors.darkText100 : AppColors.lightText100,
                  ),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: () => _showAddTaskDialog(context),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Task', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor:
                    isDark ? AppColors.primaryLight : AppColors.primary,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (displayTasks.isEmpty)
          _buildEmptyCard(
            isDark: isDark,
            icon: Icons.check_circle_outline_rounded,
            color: Colors.green,
            text: 'All store tasks are completed! Tap "+ Add Task" to set one.',
          )
        else
          ...displayTasks.map((t) => _buildTaskCard(t, isDark)),
      ],
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task, bool isDark) {
    final id = task['id'] as String;
    final title = task['title'] as String? ?? 'Untitled Task';
    final notes = task['notes'] as String? ?? '';
    final priority = task['priority'] as String? ?? 'Normal';
    final isReady = task['isReady'] == true || _readyAlertIds.contains(id);

    Color priorityColor = const Color(0xFF38BDF8);
    if (priority == 'High') priorityColor = const Color(0xFFEF4444);
    if (priority == 'Medium') priorityColor = const Color(0xFFF59E0B);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isReady
              ? Colors.green.withValues(alpha: 0.5)
              : (isDark
                  ? AppColors.darkBorder
                  : AppColors.outlineVariant.withValues(alpha: 0.25)),
          width: isReady ? 1.5 : 1.0,
        ),
        boxShadow: CyberShadows.shadow30(isDark),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ready Checkbox Toggle
          InkWell(
            onTap: () {
              setState(() {
                task['isReady'] = !isReady;
                if (!isReady) {
                  _readyAlertIds.add(id);
                } else {
                  _readyAlertIds.remove(id);
                }
              });
              _saveAlertPreferences();
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isReady
                    ? Colors.green.withValues(alpha: 0.2)
                    : (isDark ? Colors.white10 : Colors.grey.shade100),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isReady ? Colors.green : Colors.grey.shade400,
                  width: 1.5,
                ),
              ),
              child: Icon(
                isReady ? Icons.check : Icons.circle,
                size: 14,
                color: isReady ? Colors.green : Colors.transparent,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: priorityColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        priority.toUpperCase(),
                        style: TextStyle(
                          color: priorityColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 9.0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (isReady)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'RESOLVED',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 9.0,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    decoration: isReady ? TextDecoration.lineThrough : null,
                    color: isDark
                        ? (isReady ? AppColors.darkText50 : AppColors.darkText100)
                        : (isReady ? Colors.grey : AppColors.lightText100),
                  ),
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    notes,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          isDark ? AppColors.darkText50 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Delete Action
          IconButton(
            tooltip: 'Delete Task',
            icon: Icon(
              Icons.delete_outline_rounded,
              color: isDark ? AppColors.darkText50 : Colors.grey.shade500,
              size: 18,
            ),
            onPressed: () {
              setState(() {
                _customTasks.removeWhere((t) => t['id'] == id);
                _readyAlertIds.remove(id);
              });
              _saveAlertPreferences();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Deleted task "$title"'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── 2. Low Stock Warnings Section ──────────────────────────────────────────
  Widget _buildLowStockSection(bool isDark, {int? limit}) {
    return ValueListenableBuilder<Box<Product>>(
      valueListenable:
          Hive.box<Product>(HiveService.productBoxName).listenable(),
      builder: (context, box, _) {
        final threshold = AlertService.lowStockThreshold;
        final lowStockProducts = box.values
            .where((p) =>
                p.stockQuantity <= threshold &&
                !_dismissedAlertIds.contains(p.id))
            .toList()
          ..sort((a, b) => a.stockQuantity.compareTo(b.stockQuantity));

        final activeCount = lowStockProducts
            .where((p) => !_readyAlertIds.contains(p.id))
            .length;

        final displayItems = limit != null
            ? lowStockProducts.take(limit).toList()
            : lowStockProducts;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: isDark ? 0.25 : 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.warning_amber_rounded,
                      color: Colors.redAccent, size: 18),
                ),
                const SizedBox(width: 8),
                Text(
                  'Low Stock Warnings ($activeCount)',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color:
                        isDark ? AppColors.darkText100 : AppColors.lightText100,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (displayItems.isEmpty)
              _buildEmptyCard(
                isDark: isDark,
                icon: Icons.check_circle_outline_rounded,
                color: Colors.green,
                text: 'All product stocks are healthy & up to date!',
              )
            else
              ...displayItems.map((p) => _buildLowStockCard(p, isDark)),
          ],
        );
      },
    );
  }

  Widget _buildLowStockCard(Product product, bool isDark) {
    final isZero = product.stockQuantity <= 0;
    final isReady = _readyAlertIds.contains(product.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isReady
              ? Colors.green.withValues(alpha: 0.5)
              : (isZero
                  ? Colors.red.withValues(alpha: 0.4)
                  : Colors.orange.withValues(alpha: 0.4)),
          width: 1.2,
        ),
        boxShadow: CyberShadows.shadow30(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: isReady
                                ? Colors.green.withValues(alpha: 0.15)
                                : (isZero
                                    ? Colors.red.withValues(alpha: 0.12)
                                    : Colors.orange.withValues(alpha: 0.12)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isReady
                                ? 'RESOLVED / READY'
                                : (isZero
                                    ? 'OUT OF STOCK'
                                    : 'LOW STOCK: ${product.stockQuantity}'),
                            style: TextStyle(
                              color: isReady
                                  ? Colors.green
                                  : (isZero
                                      ? Colors.redAccent
                                      : (isDark
                                          ? const Color(0xFFFBBF24)
                                          : Colors.orange.shade800)),
                              fontWeight: FontWeight.w900,
                              fontSize: 9.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            product.category,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.darkText50
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      product.productName,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.darkText100
                            : AppColors.lightText100,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Price: ${_currencyFormatter.format(product.sellingPrice)} • In Stock: ${product.stockQuantity}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.darkText70
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),

              // Dismiss / Clear Alert
              IconButton(
                tooltip: 'Clear / Delete Alert',
                icon: Icon(
                  Icons.close_rounded,
                  color: isDark ? AppColors.darkText50 : Colors.grey.shade500,
                  size: 18,
                ),
                onPressed: () =>
                    _dismissAlert(product.id, product.productName),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Actions
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () => _toggleAlertReady(product.id),
                icon: Icon(
                  isReady ? Icons.check_circle_rounded : Icons.check_rounded,
                  size: 15,
                ),
                label: Text(isReady ? 'Marked Ready' : 'Mark Ready'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isReady
                      ? Colors.green
                      : (isDark ? Colors.white70 : Colors.grey.shade700),
                  side: BorderSide(
                    color: isReady
                        ? Colors.green
                        : (isDark ? AppColors.darkBorder : Colors.grey.shade300),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showRestockDialog(product),
                icon: const Icon(Icons.add_box_rounded, size: 15),
                label: const Text('Restock'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 3. Unpaid Invoices Section ─────────────────────────────────────────────
  Widget _buildUnpaidBillsSection(bool isDark, {int? limit}) {
    return StreamBuilder<QuerySnapshot>(
      stream: _salesStream,
      builder: (context, snapshot) {
        final allDocs = snapshot.data?.docs ?? [];
        final docs = allDocs.where((d) {
          if (_dismissedAlertIds.contains(d.id)) return false;
          final data = d.data() as Map<String, dynamic>;
          final status = data['paymentStatus'] ?? data['status'];
          return status == 'Pending' || status == 'Partial';
        }).toList();

        final activeCount = docs.where((d) => !_readyAlertIds.contains(d.id)).length;
        final displayDocs = limit != null ? docs.take(limit).toList() : docs;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color:
                        Colors.orange.withValues(alpha: isDark ? 0.25 : 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.receipt_long_rounded,
                      color: Colors.orange, size: 18),
                ),
                const SizedBox(width: 8),
                Text(
                  'Pending Collections ($activeCount)',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color:
                        isDark ? AppColors.darkText100 : AppColors.lightText100,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (displayDocs.isEmpty)
              _buildEmptyCard(
                isDark: isDark,
                icon: Icons.verified_rounded,
                color: Colors.green,
                text: 'No overdue or pending customer payments recorded!',
              )
            else
              ...displayDocs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return _buildUnpaidBillCard(doc.id, data, isDark);
              }),
          ],
        );
      },
    );
  }

  Widget _buildUnpaidBillCard(
      String docId, Map<String, dynamic> data, bool isDark) {
    final invoiceNumber = data['invoiceNumber'] ?? 'INV';
    final customerName = data['customerName'] ?? 'Walk-in Customer';
    final total = (data['total'] ?? 0).toDouble();
    final paid = (data['paidAmount'] ?? data['amountPaid'] ?? 0).toDouble();
    final due = total - paid;
    final status = data['paymentStatus'] ?? data['status'] ?? 'Pending';
    final isReady = _readyAlertIds.contains(docId);

    DateTime date;
    final rawDate = data['date'];
    if (rawDate is String) {
      date = DateTime.tryParse(rawDate) ?? DateTime.now();
    } else {
      date = DateTime.now();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isReady
              ? Colors.green.withValues(alpha: 0.5)
              : (isDark
                  ? AppColors.darkBorder
                  : AppColors.outlineVariant.withValues(alpha: 0.25)),
          width: isReady ? 1.5 : 1.0,
        ),
        boxShadow: CyberShadows.shadow30(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        invoiceNumber,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: isReady
                            ? Colors.green.withValues(alpha: 0.15)
                            : (status == 'Partial'
                                ? Colors.orange.withValues(alpha: 0.15)
                                : Colors.red.withValues(alpha: 0.15)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isReady ? 'RESOLVED' : status.toUpperCase(),
                        style: TextStyle(
                          color: isReady
                              ? Colors.green
                              : (status == 'Partial'
                                  ? Colors.orange
                                  : Colors.redAccent),
                          fontSize: 9.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Clear Alert',
                icon: Icon(
                  Icons.close_rounded,
                  color: isDark ? AppColors.darkText50 : Colors.grey.shade500,
                  size: 18,
                ),
                onPressed: () => _dismissAlert(docId, invoiceNumber),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  customerName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color:
                        isDark ? AppColors.darkText100 : AppColors.lightText100,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Due: ${_currencyFormatter.format(due)}',
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            DateFormat('dd MMM yyyy, hh:mm a').format(date),
            style: TextStyle(
              color: isDark ? AppColors.darkText50 : Colors.grey.shade600,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () => _toggleAlertReady(docId),
                icon: Icon(
                  isReady ? Icons.check_circle_rounded : Icons.check_rounded,
                  size: 15,
                ),
                label: Text(isReady ? 'Marked Ready' : 'Mark Ready'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isReady
                      ? Colors.green
                      : (isDark ? Colors.white70 : Colors.grey.shade700),
                  side: BorderSide(
                    color: isReady
                        ? Colors.green
                        : (isDark ? AppColors.darkBorder : Colors.grey.shade300),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _markPaidDialog(docId, total),
                icon: const Icon(Icons.payment_rounded, size: 15),
                label: const Text('Mark Paid'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Empty State Card ───────────────────────────────────────────────────────
  Widget _buildEmptyCard({
    required bool isDark,
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? AppColors.darkBorder
              : AppColors.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: isDark ? AppColors.darkText70 : Colors.grey.shade600,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Quick Restock Dialog ──────────────────────────────────────────────────
  void _showRestockDialog(Product product) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final qtyCtrl = TextEditingController(text: '10');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurfaceElevated : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Restock ${product.productName}',
          style: TextStyle(
            color: isDark ? AppColors.darkText100 : AppColors.lightText100,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Stock: ${product.stockQuantity}',
              style: TextStyle(
                color: isDark ? AppColors.darkText50 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: TextStyle(
                color: isDark ? AppColors.darkText100 : Colors.black87,
              ),
              decoration: InputDecoration(
                labelText: 'Add Quantity',
                labelStyle: TextStyle(
                  color: isDark ? AppColors.darkText70 : null,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.add_box_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? AppColors.darkText70 : Colors.grey,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final addQty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
              if (addQty > 0) {
                Navigator.of(ctx).pop();
                final messenger = ScaffoldMessenger.of(context);
                product.stockQuantity += addQty;
                await product.save();

                // Auto mark as ready
                _readyAlertIds.add(product.id);
                await _saveAlertPreferences();

                // Update shared Firestore /products
                SyncService.productsCol.doc(product.id).update({
                  'stockQuantity': FieldValue.increment(addQty),
                  'updatedAt': FieldValue.serverTimestamp(),
                }).catchError((_) {});

                if (!mounted) return;
                setState(() {});
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                        'Stock updated for ${product.productName}! New total: ${product.stockQuantity}'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Add & Mark Ready'),
          ),
        ],
      ),
    );
  }

  // ── Mark Paid Dialog ──────────────────────────────────────────────────────
  void _markPaidDialog(String docId, double total) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurfaceElevated : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Confirm Payment',
          style: TextStyle(
            color: isDark ? AppColors.darkText100 : AppColors.lightText100,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Mark this invoice as fully paid (${_currencyFormatter.format(total)})?',
          style: TextStyle(
            color: isDark ? AppColors.darkText70 : Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? AppColors.darkText70 : Colors.grey,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final messenger = ScaffoldMessenger.of(context);
              await InvoiceService.updatePayment(docId, total, 'Paid');
              // Mark as ready
              _readyAlertIds.add(docId);
              await _saveAlertPreferences();

              if (!mounted) return;
              setState(() {});
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Payment recorded and synced! Marked as ready.'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm Paid'),
          ),
        ],
      ),
    );
  }

  // ── Add Custom Store Task Dialog ──────────────────────────────────────────
  void _showAddTaskDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String priority = 'Normal';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final bottomPadding = MediaQuery.of(ctx).viewInsets.bottom;
          return Container(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomPadding),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'New Store Task / Alert',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.darkText100
                            : AppColors.lightText100,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: titleCtrl,
                  autofocus: true,
                  style: TextStyle(
                    color: isDark ? AppColors.darkText100 : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Task Title *',
                    hintText: 'e.g. Call supplier for spare parts delivery',
                    hintStyle: TextStyle(
                      color:
                          isDark ? AppColors.darkText50 : Colors.grey.shade400,
                      fontSize: 13,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  style: TextStyle(
                    color: isDark ? AppColors.darkText100 : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Notes / Details (Optional)',
                    hintText: 'e.g. Due before 5 PM',
                    hintStyle: TextStyle(
                      color:
                          isDark ? AppColors.darkText50 : Colors.grey.shade400,
                      fontSize: 13,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      'Priority:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isDark
                            ? AppColors.darkText70
                            : AppColors.lightText70,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ...['Normal', 'Medium', 'High'].map((p) {
                      final isSelected = priority == p;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(p),
                          selected: isSelected,
                          onSelected: (val) {
                            if (val) setModalState(() => priority = p);
                          },
                          selectedColor: AppColors.primary,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : (isDark
                                    ? AppColors.darkText70
                                    : Colors.black87),
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      final title = titleCtrl.text.trim();
                      if (title.isEmpty) return;

                      setState(() {
                        _customTasks.insert(0, {
                          'id': const Uuid().v4(),
                          'title': title,
                          'notes': notesCtrl.text.trim(),
                          'priority': priority,
                          'isReady': false,
                          'createdAt': DateTime.now().toIso8601String(),
                        });
                      });
                      _saveAlertPreferences();

                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Added task "$title"'),
                          backgroundColor: AppColors.primary,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Create Task / Alert'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
