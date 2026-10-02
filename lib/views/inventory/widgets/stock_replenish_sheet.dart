import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme.dart';
import '../../../core/models/models.dart';
import '../../../services/sync_service.dart';

class StockReplenishSheet extends StatefulWidget {
  final Product product;
  final VoidCallback? onScanNext;

  const StockReplenishSheet({
    super.key,
    required this.product,
    this.onScanNext,
  });

  static Future<void> show(
    BuildContext context, {
    required Product product,
    VoidCallback? onScanNext,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StockReplenishSheet(
        product: product,
        onScanNext: onScanNext,
      ),
    );
  }

  @override
  State<StockReplenishSheet> createState() => _StockReplenishSheetState();
}

class _StockReplenishSheetState extends State<StockReplenishSheet> {
  final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
  bool _isAddMode = true; // true = Add to stock, false = Set exact stock
  int _adjustAmount = 5;
  late TextEditingController _qtyCtrl;
  late TextEditingController _purchasePriceCtrl;
  late TextEditingController _sellingPriceCtrl;
  bool _showPriceEdit = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: '$_adjustAmount');
    _purchasePriceCtrl =
        TextEditingController(text: '${widget.product.purchasePrice}');
    _sellingPriceCtrl =
        TextEditingController(text: '${widget.product.sellingPrice}');
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _purchasePriceCtrl.dispose();
    _sellingPriceCtrl.dispose();
    super.dispose();
  }

  int get _resultingStock {
    if (_isAddMode) {
      return (widget.product.stockQuantity + _adjustAmount).clamp(0, 999999);
    } else {
      return _adjustAmount.clamp(0, 999999);
    }
  }

  Future<void> _saveStock({bool scanNext = false}) async {
    setState(() => _isSaving = true);
    try {
      final newStock = _resultingStock;

      if (_showPriceEdit) {
        final pPrice =
            double.tryParse(_purchasePriceCtrl.text) ?? widget.product.purchasePrice;
        final sPrice =
            double.tryParse(_sellingPriceCtrl.text) ?? widget.product.sellingPrice;

        final updated = Product(
          id: widget.product.id,
          productName: widget.product.productName,
          category: widget.product.category,
          purchasePrice: pPrice,
          sellingPrice: sPrice,
          stockQuantity: newStock,
          gstPercentage: widget.product.gstPercentage,
          barcode: widget.product.barcode,
        );
        await SyncService.saveOrUpdateProduct(updated);
      } else {
        await SyncService.updateProductStock(widget.product.id, newStock);
      }

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${widget.product.productName} updated to $newStock units',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

      if (scanNext && widget.onScanNext != null) {
        widget.onScanNext!();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
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
    final currentStock = widget.product.stockQuantity;
    final isLowStock = currentStock <= 10;
    final statusColor = currentStock <= 0
        ? const Color(0xFFEF4444)
        : (isLowStock ? const Color(0xFFF59E0B) : const Color(0xFF10B981));
    final statusLabel = currentStock <= 0
        ? 'Out of Stock'
        : (isLowStock ? 'Low Stock' : 'In Stock');

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.outlineVariant,
        ),
        boxShadow: CyberShadows.shadow100(isDark),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        14,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle Bar
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Top Header: Product Name & Category
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.product.productName,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: isDark
                              ? AppColors.darkText100
                              : AppColors.lightText100,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primary
                                  .withValues(alpha: isDark ? 0.25 : 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              widget.product.category,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? AppColors.primaryLight
                                    : AppColors.primary,
                              ),
                            ),
                          ),
                          if (widget.product.barcode != null &&
                              widget.product.barcode!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1E1738)
                                    : const Color(0xFFF1EFFB),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.qr_code_2_rounded,
                                    size: 13,
                                    color: isDark
                                        ? AppColors.darkText50
                                        : AppColors.lightText50,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    widget.product.barcode!,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: isDark
                                          ? AppColors.darkText70
                                          : AppColors.lightText70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
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

            // Current Stock & Price Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkSurfaceElevated
                    : const Color(0xFFF8F7FD),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark
                      ? AppColors.darkBorder
                      : AppColors.primary.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CURRENT STOCK',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: isDark
                              ? AppColors.darkText50
                              : AppColors.lightText50,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '$currentStock',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: isDark
                                  ? AppColors.darkText100
                                  : AppColors.lightText100,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor
                                  .withValues(alpha: isDark ? 0.25 : 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'SELLING PRICE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: isDark
                              ? AppColors.darkText50
                              : AppColors.lightText50,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _currency.format(widget.product.sellingPrice),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: isDark
                              ? AppColors.primaryLight
                              : AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Mode Selector: Add to Stock vs Set Exact Stock
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E1738)
                    : const Color(0xFFF1EFFB),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _isAddMode = true;
                          _adjustAmount = 5;
                          _qtyCtrl.text = '5';
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _isAddMode
                              ? (isDark
                                  ? AppColors.primary
                                  : Colors.white)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _isAddMode ? CyberShadows.shadow30(isDark) : null,
                        ),
                        child: Center(
                          child: Text(
                            '+ Replenish / Add',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _isAddMode
                                  ? (_isDarkOrWhite(isDark))
                                  : (isDark
                                      ? AppColors.darkText50
                                      : AppColors.lightText50),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _isAddMode = false;
                          _adjustAmount = currentStock;
                          _qtyCtrl.text = '$currentStock';
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !_isAddMode
                              ? (isDark
                                  ? AppColors.primary
                                  : Colors.white)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: !_isAddMode ? CyberShadows.shadow30(isDark) : null,
                        ),
                        child: Center(
                          child: Text(
                            'Set Exact Total',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: !_isAddMode
                                  ? (_isDarkOrWhite(isDark))
                                  : (isDark
                                      ? AppColors.darkText50
                                      : AppColors.lightText50),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Stepper and Direct Input Row
            Row(
              children: [
                _buildCircleStepBtn(
                  icon: Icons.remove_rounded,
                  onTap: () {
                    final val = (_adjustAmount - 1).clamp(0, 999999);
                    setState(() {
                      _adjustAmount = val;
                      _qtyCtrl.text = '$val';
                    });
                  },
                  isDark: isDark,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: TextFormField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: isDark
                          ? AppColors.darkText100
                          : AppColors.lightText100,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: isDark
                          ? AppColors.darkSurfaceElevated
                          : const Color(0xFFF8F7FD),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: isDark
                              ? AppColors.darkBorder
                              : AppColors.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: isDark
                              ? AppColors.darkBorder
                              : AppColors.primary.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                    onChanged: (v) {
                      final parsed = int.tryParse(v) ?? 0;
                      setState(() => _adjustAmount = parsed);
                    },
                  ),
                ),
                const SizedBox(width: 14),
                _buildCircleStepBtn(
                  icon: Icons.add_rounded,
                  onTap: () {
                    final val = (_adjustAmount + 1).clamp(0, 999999);
                    setState(() {
                      _adjustAmount = val;
                      _qtyCtrl.text = '$val';
                    });
                  },
                  isDark: isDark,
                  isPrimary: true,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Quick increment chips: +1, +5, +10, +25, +50
            if (_isAddMode)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [1, 5, 10, 20, 50, 100].map((step) {
                    final isCurrent = _adjustAmount == step;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('+$step'),
                        selected: isCurrent,
                        onSelected: (_) {
                          setState(() {
                            _adjustAmount = step;
                            _qtyCtrl.text = '$step';
                          });
                        },
                        selectedColor: AppColors.primary,
                        backgroundColor: isDark
                            ? const Color(0xFF1E1738)
                            : const Color(0xFFF1EFFB),
                        labelStyle: TextStyle(
                          color: isCurrent
                              ? Colors.white
                              : (isDark
                                  ? AppColors.darkText70
                                  : AppColors.lightText70),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

            const SizedBox(height: 16),

            // Result preview banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: isDark ? 0.35 : 0.15),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isAddMode ? 'New Total Stock:' : 'Updated Total Stock:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: isDark ? AppColors.darkText70 : AppColors.lightText70,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        '$_resultingStock UNITS',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: isDark
                              ? AppColors.primaryLight
                              : AppColors.primary,
                        ),
                      ),
                      if (_isAddMode && _adjustAmount > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          '(+$_adjustAmount)',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Expandable Price Update Toggle
            InkWell(
              onTap: () => setState(() => _showPriceEdit = !_showPriceEdit),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      _showPriceEdit
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Update purchase or selling price (optional)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.primaryLight
                            : AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_showPriceEdit) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _purchasePriceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Purchase Price (₹)',
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _sellingPriceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Selling Price (₹)',
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // Action Buttons: Update Stock & Scan Next
            Row(
              children: [
                if (widget.onScanNext != null) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving ? null : () => _saveStock(scanNext: true),
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                      label: const Text('Update & Scan Next'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark
                            ? AppColors.primaryLight
                            : AppColors.primary,
                        side: BorderSide(
                          color: isDark
                              ? AppColors.primaryLight
                              : AppColors.primary,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : () => _saveStock(scanNext: false),
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
                        : const Text(
                            'Update Stock',
                            style: TextStyle(
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
    );
  }

  Color _isDarkOrWhite(bool isDark) {
    if (isDark) {
      return Colors.white;
    }
    return AppColors.primary;
  }

  Widget _buildCircleStepBtn({
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
    bool isPrimary = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isPrimary
              ? AppColors.primary
              : (isDark
                  ? AppColors.darkSurfaceElevated
                  : const Color(0xFFF1EFFB)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isPrimary
                ? AppColors.primary
                : (isDark
                    ? AppColors.darkBorder
                    : AppColors.primary.withValues(alpha: 0.15)),
          ),
        ),
        child: Icon(
          icon,
          color: isPrimary
              ? Colors.white
              : (isDark ? AppColors.darkText100 : AppColors.lightText100),
          size: 24,
        ),
      ),
    );
  }
}
