import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/models/models.dart';
import '../../services/sync_service.dart';
import '../../widgets/compact_barcode_scanner_dialog.dart';

class AddProductDialog extends StatefulWidget {
  final String? initialBarcode;
  final Product? productToEdit;

  const AddProductDialog({
    super.key,
    this.initialBarcode,
    this.productToEdit,
  });

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<AddProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _categoryController;
  late TextEditingController _purchasePriceController;
  late TextEditingController _sellingPriceController;
  late TextEditingController _stockController;
  late TextEditingController _skuController;
  double _gstPercentage = 18.0;
  bool _isSaving = false;

  final List<String> _suggestedCategories = [
    'General',
    'Electronics',
    'Hardware',
    'Groceries',
    'Beverages',
    'Snacks',
    'Stationery',
    'Pharmacy',
    'Apparel',
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.productToEdit;
    _nameController = TextEditingController(text: p?.productName ?? '');
    _categoryController =
        TextEditingController(text: p?.category ?? 'General');
    _purchasePriceController =
        TextEditingController(text: p != null ? '${p.purchasePrice}' : '');
    _sellingPriceController =
        TextEditingController(text: p != null ? '${p.sellingPrice}' : '');
    _stockController =
        TextEditingController(text: p != null ? '${p.stockQuantity}' : '10');
    _skuController = TextEditingController(
      text: p?.barcode ?? widget.initialBarcode ?? '',
    );
    if (p != null) {
      _gstPercentage = p.gstPercentage;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _purchasePriceController.dispose();
    _sellingPriceController.dispose();
    _stockController.dispose();
    _skuController.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    final code = await CompactBarcodeScannerDialog.show(context);
    if (code != null && code.isNotEmpty && mounted) {
      setState(() => _skuController.text = code);
    }
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final name = _nameController.text.trim();
      final category = _categoryController.text.trim().isEmpty
          ? 'General'
          : _categoryController.text.trim();
      final pPrice = double.tryParse(_purchasePriceController.text.trim()) ?? 0;
      final sPrice = double.tryParse(_sellingPriceController.text.trim()) ?? 0;
      final stock = int.tryParse(_stockController.text.trim()) ?? 0;
      final barcode = _skuController.text.trim().isEmpty
          ? null
          : _skuController.text.trim();

      final Product product = widget.productToEdit != null
          ? Product(
              id: widget.productToEdit!.id,
              productName: name,
              category: category,
              purchasePrice: pPrice,
              sellingPrice: sPrice,
              stockQuantity: stock,
              gstPercentage: _gstPercentage,
              barcode: barcode,
            )
          : Product.newItem(
              productName: name,
              category: category,
              purchasePrice: pPrice,
              sellingPrice: sPrice,
              stockQuantity: stock,
              barcode: barcode,
            );

      await SyncService.saveOrUpdateProduct(product);

      if (mounted) {
        Navigator.of(context).pop(product);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.productToEdit != null
                ? 'Product updated successfully!'
                : 'Product added to inventory!'),
            backgroundColor: const Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEdit = widget.productToEdit != null;

    return Dialog(
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: isDark ? AppColors.darkBorder : AppColors.outlineVariant,
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
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
                          child: Icon(
                            isEdit
                                ? Icons.edit_note_rounded
                                : Icons.add_box_rounded,
                            color: isDark
                                ? AppColors.primaryLight
                                : AppColors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          isEdit ? 'Edit Product' : 'Add New Product',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: isDark
                                ? AppColors.darkText100
                                : AppColors.lightText100,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close_rounded,
                        color: isDark
                            ? AppColors.darkText50
                            : AppColors.lightText50,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Product Name
                _buildField(
                  label: 'Product Name *',
                  hint: 'e.g. Wireless Mouse, Paracetamol',
                  controller: _nameController,
                  isDark: isDark,
                  isRequired: true,
                ),
                const SizedBox(height: 14),

                // Barcode / SKU with Quick Scan Button
                Row(
                  children: [
                    Expanded(
                      child: _buildField(
                        label: 'Barcode / SKU',
                        hint: 'Scan or type barcode',
                        controller: _skuController,
                        isDark: isDark,
                        prefixIcon: Icons.qr_code_2_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      margin: const EdgeInsets.only(top: 20),
                      child: IconButton.filled(
                        onPressed: _scanBarcode,
                        tooltip: 'Scan Barcode with Camera',
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.all(12),
                        ),
                        icon: const Icon(Icons.qr_code_scanner_rounded, size: 22),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Category & Suggested Chips
                _buildField(
                  label: 'Category',
                  hint: 'e.g. Electronics, Groceries',
                  controller: _categoryController,
                  isDark: isDark,
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _suggestedCategories.map((cat) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          label: Text(cat),
                          labelStyle: TextStyle(
                            fontSize: 10,
                            color: isDark
                                ? AppColors.darkText70
                                : AppColors.lightText70,
                          ),
                          backgroundColor: isDark
                              ? const Color(0xFF1E1738)
                              : const Color(0xFFF1EFFB),
                          onPressed: () {
                            setState(() => _categoryController.text = cat);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 14),

                // Purchase & Selling Price Row
                Row(
                  children: [
                    Expanded(
                      child: _buildField(
                        label: 'Purchase Price (₹) *',
                        hint: '0.00',
                        controller: _purchasePriceController,
                        isNumber: true,
                        isDark: isDark,
                        isRequired: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildField(
                        label: 'Selling Price (₹) *',
                        hint: '0.00',
                        controller: _sellingPriceController,
                        isNumber: true,
                        isDark: isDark,
                        isRequired: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Stock Quantity & GST Row
                Row(
                  children: [
                    Expanded(
                      child: _buildField(
                        label: 'Stock Quantity *',
                        hint: 'Units in store',
                        controller: _stockController,
                        isNumber: true,
                        isDark: isDark,
                        isRequired: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'GST Rate',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppColors.darkText70
                                  : AppColors.lightText70,
                            ),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<double>(
                            initialValue: _gstPercentage,
                            decoration: InputDecoration(
                              isDense: true,
                              filled: true,
                              fillColor: isDark
                                  ? AppColors.darkSurfaceElevated
                                  : const Color(0xFFF8F7FD),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: isDark
                                      ? AppColors.darkBorder
                                      : AppColors.primary.withValues(alpha: 0.2),
                                ),
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(value: 0.0, child: Text('0%')),
                              DropdownMenuItem(value: 5.0, child: Text('5%')),
                              DropdownMenuItem(value: 12.0, child: Text('12%')),
                              DropdownMenuItem(value: 18.0, child: Text('18%')),
                              DropdownMenuItem(value: 28.0, child: Text('28%')),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _gstPercentage = val);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Submit Buttons
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: isDark
                                ? AppColors.darkText50
                                : AppColors.lightText50,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveProduct,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 2,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                isEdit ? 'Save Changes' : 'Create Product',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required bool isDark,
    bool isNumber = false,
    bool isRequired = false,
    IconData? prefixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isDark ? AppColors.darkText70 : AppColors.lightText70,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: isNumber
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.darkText100 : AppColors.lightText100,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.darkText30 : AppColors.lightText30,
            ),
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon,
                    size: 18,
                    color: isDark ? AppColors.darkText50 : AppColors.lightText50)
                : null,
            filled: true,
            fillColor: isDark
                ? AppColors.darkSurfaceElevated
                : const Color(0xFFF8F7FD),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark
                    ? AppColors.darkBorder
                    : AppColors.primary.withValues(alpha: 0.2),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark
                    ? AppColors.darkBorder
                    : AppColors.primary.withValues(alpha: 0.15),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
          ),
          validator: (v) {
            if (isRequired && (v == null || v.trim().isEmpty)) {
              return 'Required field';
            }
            return null;
          },
        ),
      ],
    );
  }
}
