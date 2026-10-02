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
  final _currencyFormatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Expenses',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Track and manage daily business costs',
              style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 14),
            ),
            const SizedBox(height: 32),
            
            // Add Expense Button
            ElevatedButton(
              onPressed: () => _showAddExpenseModal(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline, color: Colors.white),
                  SizedBox(width: 12),
                  Text('Add New Expense', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            
            const SizedBox(height: 48),
            Text('Recent Expenses', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            
            ValueListenableBuilder<Box<Expense>>(
              valueListenable: Hive.box<Expense>(HiveService.expenseBoxName).listenable(),
              builder: (context, box, _) {
                final expenses = box.values.toList();
                
                if (expenses.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(
                      child: Text('No expenses recorded.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  );
                }

                // Sort by date newest first
                expenses.sort((a, b) => b.date.compareTo(a.date));

                return Column(
                  children: expenses.map((expense) => _buildExpenseItem(expense)).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseItem(Expense expense) {
    final dateStr = DateFormat('dd MMM yyyy').format(expense.date);
    
    IconData icon;
    Color color;
    switch (expense.expenseType.toLowerCase()) {
      case 'fuel':
        icon = Icons.local_gas_station;
        color = Colors.orange;
        break;
      case 'rent':
        icon = Icons.home_work;
        color = Colors.blue;
        break;
      case 'salary':
        icon = Icons.badge;
        color = Colors.purple;
        break;
      case 'utilities':
        icon = Icons.bolt;
        color = Colors.yellow.shade700;
        break;
      case 'tea & snacks':
        icon = Icons.coffee;
        color = Colors.brown;
        break;
      default:
        icon = Icons.receipt;
        color = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(expense.expenseType, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(expense.notes ?? '', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '-${_currencyFormatter.format(expense.amount)}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent, fontSize: 16),
              ),
              Text(dateStr, style: const TextStyle(color: Colors.grey, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

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
  String _selectedType = 'Fuel';
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  final List<String> _categories = ['Fuel', 'Rent', 'Salary', 'tea & snacks', 'Utilities', 'Others'];

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveExpense() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) return;

    final expense = Expense(
      id: const Uuid().v4(),
      date: DateTime.now(),
      expenseType: _selectedType,
      amount: amount,
      notes: _notesController.text,
    );

    // Save locally
    await HiveService.addExpense(expense);
    
    // Sync with PWA Backend
    SyncService.uploadUnsyncedData();

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Add padding bottom for keyboard
    final keyboardPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(32, 32, 32, 32 + keyboardPadding),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add Expense', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            value: _selectedType,
            decoration: const InputDecoration(labelText: 'Expense Type'),
            items: _categories.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedType = val);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveExpense,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Save Expense', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
