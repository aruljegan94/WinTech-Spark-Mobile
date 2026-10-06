import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme.dart';
import '../../core/models/models.dart';
import '../../services/hive_service.dart';
import '../../services/sync_service.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final _currencyFormatter =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹');
  final _searchController = TextEditingController();

  String _selectedCategory = 'All';
  String _selectedDateFilter = 'This Month';
  String _searchQuery = '';

  static const List<Map<String, dynamic>> _categoriesMeta = [
    {'name': 'All', 'icon': Icons.apps_rounded, 'color': AppColors.primary},
    {'name': 'Fuel', 'icon': Icons.local_gas_station_rounded, 'color': Color(0xFFF97316)},
    {'name': 'Rent', 'icon': Icons.home_work_rounded, 'color': Color(0xFF3B82F6)},
    {'name': 'Salary', 'icon': Icons.badge_rounded, 'color': Color(0xFF8B5CF6)},
    {'name': 'Tea & Snacks', 'icon': Icons.coffee_rounded, 'color': Color(0xFFB45309)},
    {'name': 'Utilities', 'icon': Icons.bolt_rounded, 'color': Color(0xFFEAB308)},
    {'name': 'Inventory', 'icon': Icons.inventory_2_rounded, 'color': Color(0xFF06B6D4)},
    {'name': 'Others', 'icon': Icons.receipt_long_rounded, 'color': Color(0xFF64748B)},
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _getCategoryMeta(String type) {
    return _categoriesMeta.firstWhere(
      (c) => (c['name'] as String).toLowerCase() == type.toLowerCase(),
      orElse: () => {
        'name': type,
        'icon': Icons.receipt_long_rounded,
        'color': const Color(0xFF64748B)
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      body: ValueListenableBuilder<Box<Expense>>(
        valueListenable:
            Hive.box<Expense>(HiveService.expenseBoxName).listenable(),
        builder: (context, box, _) {
          final allExpenses = box.values.toList();
          final now = DateTime.now();

          // ── KPI Calculations ──────────────────────────────────────────
          double monthTotal = 0;
          double todayTotal = 0;
          final Map<String, double> catTotals = {};

          for (final e in allExpenses) {
            final isSameYear = e.date.year == now.year;
            final isSameMonth = isSameYear && e.date.month == now.month;
            final isSameDay = isSameMonth && e.date.day == now.day;

            if (isSameMonth) {
              monthTotal += e.amount;
              catTotals[e.expenseType] =
                  (catTotals[e.expenseType] ?? 0) + e.amount;
            }
            if (isSameDay) {
              todayTotal += e.amount;
            }
          }

          String topCatName = 'None';
          double topCatAmount = 0;
          catTotals.forEach((k, v) {
            if (v > topCatAmount) {
              topCatAmount = v;
              topCatName = k;
            }
          });

          // ── Filtering ──────────────────────────────────────────────────
          var filtered = allExpenses.where((e) {
            // Category filter
            if (_selectedCategory != 'All' &&
                e.expenseType.toLowerCase() != _selectedCategory.toLowerCase()) {
              return false;
            }

            // Date filter
            if (_selectedDateFilter == 'Today') {
              if (e.date.year != now.year ||
                  e.date.month != now.month ||
                  e.date.day != now.day) {
                return false;
              }
            } else if (_selectedDateFilter == 'This Week') {
              final diff = now.difference(e.date).inDays;
              if (diff > 7) return false;
            } else if (_selectedDateFilter == 'This Month') {
              if (e.date.year != now.year || e.date.month != now.month) {
                return false;
              }
            }

            // Search query
            if (_searchQuery.isNotEmpty) {
              final matchesType = e.expenseType
                  .toLowerCase()
                  .contains(_searchQuery.toLowerCase());
              final matchesNotes = (e.notes ?? '')
                  .toLowerCase()
                  .contains(_searchQuery.toLowerCase());
              if (!matchesType && !matchesNotes) return false;
            }

            return true;
          }).toList();

          // Sort newest first
          filtered.sort((a, b) => b.date.compareTo(a.date));

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Header & KPI Cards ──────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(20, 16, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Expenses Hub',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                  color: isDark
                                      ? AppColors.darkText100
                                      : AppColors.lightText100,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Track operational costs & spendings',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? AppColors.darkText50
                                      : AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          // Add Expense Fast Button
                          IconButton.filled(
                            onPressed: () => _showAddExpenseModal(context),
                            tooltip: 'Add New Expense',
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(12),
                            ),
                            icon: const Icon(Icons.add_rounded, size: 22),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Month & Today Summary Cards ──────────────────────
                      _buildSummaryKpiCard(
                        isDark: isDark,
                        monthTotal: monthTotal,
                        todayTotal: todayTotal,
                        topCategory: topCatName,
                        transactionCount: allExpenses.length,
                      ),
                      const SizedBox(height: 16),

                      // ── Live Search Bar ──────────────────────────────────
                      TextField(
                        controller: _searchController,
                        onChanged: (val) =>
                            setState(() => _searchQuery = val.trim()),
                        style: TextStyle(
                          color: isDark
                              ? AppColors.darkText100
                              : AppColors.lightText100,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search expense type, note, vendor…',
                          hintStyle: TextStyle(
                            color: isDark
                                ? AppColors.darkText50
                                : Colors.grey.shade400,
                            fontSize: 13,
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: isDark ? AppColors.darkText70 : Colors.grey,
                            size: 20,
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded,
                                      size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: isDark
                              ? AppColors.darkSurface
                              : Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: isDark
                                  ? AppColors.darkBorder
                                  : AppColors.outlineVariant
                                      .withValues(alpha: 0.25),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: isDark
                                  ? AppColors.darkBorder
                                  : AppColors.outlineVariant
                                      .withValues(alpha: 0.25),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // ── Date Quick Filters ───────────────────────────────
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            'This Month',
                            'Today',
                            'This Week',
                            'All Time',
                          ].map((f) {
                            final isSelected = _selectedDateFilter == f;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(f),
                                selected: isSelected,
                                onSelected: (val) {
                                  if (val) {
                                    setState(() => _selectedDateFilter = f);
                                  }
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
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Category Filters ─────────────────────────────────
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: _categoriesMeta.map((cat) {
                            final name = cat['name'] as String;
                            final icon = cat['icon'] as IconData;
                            final color = cat['color'] as Color;
                            final isSelected = _selectedCategory == name;

                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                avatar: Icon(
                                  icon,
                                  size: 14,
                                  color: isSelected ? Colors.white : color,
                                ),
                                label: Text(name),
                                selected: isSelected,
                                onSelected: (val) {
                                  setState(() => _selectedCategory = name);
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
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Recent Title
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'TRANSACTIONS (${filtered.length})',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                              color: isDark
                                  ? AppColors.darkText50
                                  : AppColors.lightText50,
                            ),
                          ),
                          Text(
                            'Showing ${_selectedDateFilter.toLowerCase()}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.darkText50
                                  : Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ── Transactions Feed ─────────────────────────────────────────
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.primary
                                  .withValues(alpha: isDark ? 0.20 : 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.receipt_long_rounded,
                              size: 40,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'No expenses found',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppColors.darkText100
                                  : AppColors.lightText100,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'No results matching "$_searchQuery"'
                                : 'Tap the "+" button to record an expense.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppColors.darkText50
                                  : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => _showAddExpenseModal(context),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add Expense'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 10),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final expense = filtered[index];
                        return _buildExpenseCard(expense, isDark);
                      },
                      childCount: filtered.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ── Summary KPI Hero Card ─────────────────────────────────────────────────
  Widget _buildSummaryKpiCard({
    required bool isDark,
    required double monthTotal,
    required double todayTotal,
    required String topCategory,
    required int transactionCount,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3B0764), Color(0xFF6B21A8), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: CyberShadows.shadow70(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'TOTAL SPENT THIS MONTH',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '$transactionCount Records',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _currencyFormatter.format(monthTotal),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // Today
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TODAY',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _currencyFormatter.format(todayTotal),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Top Category
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TOP CATEGORY',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        topCategory,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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

  // ── Expense Transaction Card ──────────────────────────────────────────────
  Widget _buildExpenseCard(Expense expense, bool isDark) {
    final meta = _getCategoryMeta(expense.expenseType);
    final icon = meta['icon'] as IconData;
    final color = meta['color'] as Color;
    final dateStr = DateFormat('dd MMM yyyy • hh:mm a').format(expense.date);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? AppColors.darkBorder
              : AppColors.outlineVariant.withValues(alpha: 0.15),
        ),
        boxShadow: CyberShadows.shadow30(isDark),
      ),
      child: Row(
        children: [
          // Category Icon Container
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.22 : 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: color.withValues(alpha: isDark ? 0.35 : 0.20),
              ),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      expense.expenseType,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isDark
                            ? AppColors.darkText100
                            : AppColors.lightText100,
                      ),
                    ),
                  ],
                ),
                if (expense.notes?.isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(
                    expense.notes!,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? AppColors.darkText70
                          : Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  dateStr,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? AppColors.darkText50 : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),

          // Amount & Delete Button
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '-${_currencyFormatter.format(expense.amount)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: Color(0xFFEF4444),
                ),
              ),
              const SizedBox(height: 2),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Delete Expense',
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: isDark ? AppColors.darkText50 : Colors.grey.shade400,
                ),
                onPressed: () => _confirmDeleteExpense(context, expense),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Delete Expense Flow ───────────────────────────────────────────────────
  void _confirmDeleteExpense(BuildContext context, Expense expense) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurfaceElevated : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete Expense?',
          style: TextStyle(
            color: isDark ? AppColors.darkText100 : AppColors.lightText100,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${expense.expenseType}" (${_currencyFormatter.format(expense.amount)})?',
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
              Navigator.pop(ctx);
              final messenger = ScaffoldMessenger.of(context);
              final id = expense.id;
              // Remove locally
              await expense.delete();
              // Remove on Firestore
              SyncService.expensesCol.doc(id).delete().catchError((_) {});

              if (!mounted) return;
              messenger.showSnackBar(
                SnackBar(
                  content: Text('Expense deleted: ${expense.expenseType}'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ── Enhanced Add Expense Modal ────────────────────────────────────────────
  void _showAddExpenseModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AddExpenseForm(),
    );
  }
}

class AddExpenseForm extends StatefulWidget {
  const AddExpenseForm({super.key});

  @override
  State<AddExpenseForm> createState() => _AddExpenseFormState();
}

class _AddExpenseFormState extends State<AddExpenseForm> {
  String _selectedCategory = 'Fuel';
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  static const List<Map<String, dynamic>> _quickCategories = [
    {'name': 'Fuel', 'icon': Icons.local_gas_station_rounded, 'color': Color(0xFFF97316)},
    {'name': 'Rent', 'icon': Icons.home_work_rounded, 'color': Color(0xFF3B82F6)},
    {'name': 'Salary', 'icon': Icons.badge_rounded, 'color': Color(0xFF8B5CF6)},
    {'name': 'Tea & Snacks', 'icon': Icons.coffee_rounded, 'color': Color(0xFFB45309)},
    {'name': 'Utilities', 'icon': Icons.bolt_rounded, 'color': Color(0xFFEAB308)},
    {'name': 'Inventory', 'icon': Icons.inventory_2_rounded, 'color': Color(0xFF06B6D4)},
    {'name': 'Others', 'icon': Icons.receipt_long_rounded, 'color': Color(0xFF64748B)},
  ];

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _addPresetAmount(double amount) {
    final current = double.tryParse(_amountController.text.trim()) ?? 0;
    final updated = current + amount;
    _amountController.text = updated.toStringAsFixed(0);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _saveExpense() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid expense amount.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final expense = Expense(
      id: const Uuid().v4(),
      date: _selectedDate,
      expenseType: _selectedCategory,
      amount: amount,
      notes: _notesController.text.trim(),
    );

    // Save locally
    await HiveService.addExpense(expense);

    // Sync with Firestore Web App
    SyncService.uploadUnsyncedData();

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Recorded $_selectedCategory expense of ₹${amount.toStringAsFixed(0)}'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final keyboardPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + keyboardPadding),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary
                            .withValues(alpha: isDark ? 0.25 : 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.add_shopping_cart_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Record New Expense',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.darkText100
                            : AppColors.lightText100,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Amount Field
            TextField(
              controller: _amountController,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: isDark ? AppColors.darkText100 : Colors.black87,
              ),
              decoration: InputDecoration(
                labelText: 'Amount (₹) *',
                hintText: '0.00',
                prefixText: '₹ ',
                prefixStyle: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
                filled: true,
                fillColor: isDark
                    ? AppColors.darkSurfaceElevated
                    : AppColors.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Quick Preset Amount Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [100.0, 500.0, 1000.0, 2000.0, 5000.0].map((amt) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text('+₹${amt.toInt()}'),
                      onPressed: () => _addPresetAmount(amt),
                      backgroundColor: isDark
                          ? AppColors.darkSurfaceElevated
                          : AppColors.surfaceContainerLow,
                      labelStyle: TextStyle(
                        color: isDark
                            ? AppColors.primaryLight
                            : AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 18),

            // Category Picker
            Text(
              'Category *',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkText70 : AppColors.lightText70,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _quickCategories.map((cat) {
                  final name = cat['name'] as String;
                  final icon = cat['icon'] as IconData;
                  final color = cat['color'] as Color;
                  final isSelected = _selectedCategory == name;

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(
                        icon,
                        size: 14,
                        color: isSelected ? Colors.white : color,
                      ),
                      label: Text(name),
                      selected: isSelected,
                      onSelected: (val) {
                        if (val) setState(() => _selectedCategory = name);
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
                }).toList(),
              ),
            ),
            const SizedBox(height: 18),

            // Date & Notes Row
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkSurfaceElevated
                            : AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? AppColors.darkBorder
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 16,
                            color: isDark
                                ? AppColors.primaryLight
                                : AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              DateFormat('dd MMM yyyy').format(_selectedDate),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? AppColors.darkText100
                                    : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Notes / Vendor Field
            TextField(
              controller: _notesController,
              style: TextStyle(
                color: isDark ? AppColors.darkText100 : Colors.black87,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                labelText: 'Notes / Description (Optional)',
                hintText: 'e.g. Paid cash for office diesel generator',
                hintStyle: TextStyle(
                  color: isDark ? AppColors.darkText50 : Colors.grey.shade400,
                  fontSize: 12,
                ),
                filled: true,
                fillColor: isDark
                    ? AppColors.darkSurfaceElevated
                    : AppColors.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Save Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _saveExpense,
                icon: const Icon(Icons.check_circle_rounded, size: 20),
                label: const Text(
                  'Record Expense',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
