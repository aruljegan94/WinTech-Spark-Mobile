import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/models/models.dart';
import '../../services/printer_service.dart';
import '../../services/hive_service.dart';
import '../../services/sync_service.dart';
import 'add_product_dialog.dart';
import 'scanner_screen.dart';
import 'widgets/stock_replenish_sheet.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _printerService = ThermalPrinterService();
  final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
  final _kpiFmt = NumberFormat('#,##,##0', 'en_IN');

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'All';
  String _stockFilter = 'All'; // 'All', 'In Stock', 'Low Stock', 'Out of Stock'

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Quick Barcode Scan & Replenish Flow ─────────────────────────────────────
  Future<void> _handleScanToReplenish() async {
    final barcode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );

    if (barcode == null || !mounted) return;

    final existingProduct = HiveService.getProductByBarcode(barcode);

    if (existingProduct != null) {
      if (!mounted) return;
      StockReplenishSheet.show(
        context,
        product: existingProduct,
        onScanNext: () {
          // Re-trigger scanning for rapid continuous replenishment
          _handleScanToReplenish();
        },
      );
    } else {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.inventory_2_outlined, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Product Not Found', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: Text(
            'No existing item matches barcode: "$barcode".\n\nWould you like to register a new product with this SKU?',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                showDialog(
                  context: context,
                  builder: (_) => AddProductDialog(initialBarcode: barcode),
                );
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Create Product'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }
  }

  // ── Quick +/- Delta Stepper on Card ─────────────────────────────────────────
  Future<void> _adjustQuickDelta(Product product, int delta) async {
    final newStock = (product.stockQuantity + delta).clamp(0, 999999);
    await SyncService.updateProductStock(product.id, newStock);
  }

  // ── Delete Confirmation Dialog ──────────────────────────────────────────────
  void _confirmDelete(Product product) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Product'),
        content: Text(
          'Are you sure you want to remove "${product.productName}" from the catalog?\nThis action syncs to cloud inventory.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await SyncService.deleteProduct(product.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${product.productName} removed'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<Box<Product>>(
      valueListenable:
          Hive.box<Product>(HiveService.productBoxName).listenable(),
      builder: (context, box, _) {
        final allProducts = box.values.toList();

        // ── Compute KPI Metrics (Matching Web App) ──────────────────────────
        int lowStockCount = 0;
        int outOfStockCount = 0;
        double totalStockValue = 0;
        final Set<String> categories = {'All'};

        for (final p in allProducts) {
          if (p.stockQuantity <= 0) {
            outOfStockCount++;
          } else if (p.stockQuantity < 10) {
            lowStockCount++;
          }
          totalStockValue += (p.purchasePrice) * (p.stockQuantity);
          if (p.category.trim().isNotEmpty) {
            categories.add(p.category.trim());
          }
        }

        // ── Filter and Sort Products ────────────────────────────────────────
        final filteredProducts = allProducts.where((p) {
          // 1. Search Query
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            final nameMatch = p.productName.toLowerCase().contains(q);
            final catMatch = p.category.toLowerCase().contains(q);
            final barcodeMatch =
                p.barcode?.toLowerCase().contains(q) ?? false;
            if (!nameMatch && !catMatch && !barcodeMatch) return false;
          }

          // 2. Category Filter
          if (_selectedCategory != 'All' &&
              p.category.trim() != _selectedCategory) {
            return false;
          }

          // 3. Stock Filter
          if (_stockFilter == 'Low Stock') {
            return p.stockQuantity > 0 && p.stockQuantity < 10;
          } else if (_stockFilter == 'Out of Stock') {
            return p.stockQuantity <= 0;
          } else if (_stockFilter == 'In Stock') {
            return p.stockQuantity >= 10;
          }

          return true;
        }).toList();

        return RefreshIndicator(
          onRefresh: () async {
            await SyncService.uploadUnsyncedData();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 1. Page Header with Real-Time Sync Indicator ────────────
                _buildHeader(isDark, allProducts.length),

                const SizedBox(height: 16),

                // ── 2. Dual Action Cyber Bento Cards ────────────────────────
                _buildActionCards(isDark),

                const SizedBox(height: 18),

                // ── 3. Web-Aligned 4x KPI Summary Strip ─────────────────────
                _buildKpiStrip(
                  isDark: isDark,
                  totalProducts: allProducts.length,
                  stockValue: totalStockValue,
                  lowStock: lowStockCount,
                  outStock: outOfStockCount,
                ),

                const SizedBox(height: 18),

                // ── 4. Search and Filters Hub ───────────────────────────────
                _buildSearchAndFilters(
                  isDark: isDark,
                  categories: categories.toList(),
                  lowCount: lowStockCount,
                  outCount: outOfStockCount,
                ),

                const SizedBox(height: 16),

                // ── 5. Product Catalog List ─────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'PRODUCT CATALOG (${filteredProducts.length})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                        color: isDark
                            ? AppColors.darkText50
                            : AppColors.lightText50,
                      ),
                    ),
                    if (_searchQuery.isNotEmpty ||
                        _selectedCategory != 'All' ||
                        _stockFilter != 'All')
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _searchCtrl.clear();
                            _searchQuery = '';
                            _selectedCategory = 'All';
                            _stockFilter = 'All';
                          });
                        },
                        child: Text(
                          'Clear Filters',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? AppColors.primaryLight
                                : AppColors.primary,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                if (filteredProducts.isEmpty)
                  _buildEmptyState(isDark)
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredProducts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final product = filteredProducts[index];
                      return _buildProductCard(
                        context: context,
                        product: product,
                        isDark: isDark,
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Header Bar ─────────────────────────────────────────────────────────────
  Widget _buildHeader(bool isDark, int totalCount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Inventory',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.6,
                color: isDark ? AppColors.darkText100 : AppColors.lightText100,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Monitor & replenish your store assets',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkText50 : AppColors.lightText50,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.primaryDark.withValues(alpha: 0.35)
                : AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? AppColors.primaryLight.withValues(alpha: 0.30)
                  : AppColors.primary.withValues(alpha: 0.20),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.primaryLight : AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Live Cloud Sync',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.primaryLight : AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Dual Action Cyber Bento Cards ──────────────────────────────────────────
  Widget _buildActionCards(bool isDark) {
    return Row(
      children: [
        // Scan to Add / Update Stock (Electric Neon Gradient)
        Expanded(
          child: InkWell(
            onTap: _handleScanToReplenish,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: AppColors.cyberVioletGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: CyberShadows.shadow70(isDark),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.qr_code_scanner_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Scan to Stock',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Replenish or add via camera',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 10.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(width: 12),

        // Add New Product (Obsidian/Frost Cyber Panel)
        Expanded(
          child: InkWell(
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => const AddProductDialog(),
              );
            },
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
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: AppColors.primary
                          .withValues(alpha: isDark ? 0.25 : 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.add_box_rounded,
                      color: isDark
                          ? AppColors.primaryLight
                          : AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'New Product',
                    style: TextStyle(
                      color: isDark
                          ? AppColors.darkText100
                          : AppColors.lightText100,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Create SKU & price profile',
                    style: TextStyle(
                      color: isDark
                          ? AppColors.darkText50
                          : AppColors.lightText50,
                      fontSize: 10.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Web-Aligned 4x KPI Summary Strip ───────────────────────────────────────
  Widget _buildKpiStrip({
    required bool isDark,
    required int totalProducts,
    required double stockValue,
    required int lowStock,
    required int outStock,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? AppColors.darkBorder
              : AppColors.primary.withValues(alpha: 0.12),
        ),
        boxShadow: CyberShadows.shadow30(isDark),
      ),
      child: Row(
        children: [
          // Total Items
          _buildKpiItem(
            isDark: isDark,
            label: 'PRODUCTS',
            value: '$totalProducts',
            color: isDark ? AppColors.primaryLight : AppColors.primary,
          ),
          _buildKpiDivider(isDark),

          // Stock Valuation
          _buildKpiItem(
            isDark: isDark,
            label: 'VALUATION',
            value: '₹${_kpiFmt.format(stockValue)}',
            color: const Color(0xFF06B6D4),
          ),
          _buildKpiDivider(isDark),

          // Low Stock Count
          _buildKpiItem(
            isDark: isDark,
            label: 'LOW STOCK',
            value: '$lowStock',
            color: const Color(0xFFF59E0B),
            isAlert: lowStock > 0,
          ),
          _buildKpiDivider(isDark),

          // Out of Stock Count
          _buildKpiItem(
            isDark: isDark,
            label: 'OUT STOCK',
            value: '$outStock',
            color: const Color(0xFFEF4444),
            isAlert: outStock > 0,
          ),
        ],
      ),
    );
  }

  Widget _buildKpiItem({
    required bool isDark,
    required String label,
    required String value,
    required Color color,
    bool isAlert = false,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: isDark ? AppColors.darkText50 : AppColors.lightText50,
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiDivider(bool isDark) {
    return Container(
      width: 1,
      height: 24,
      color: isDark
          ? AppColors.darkBorder
          : AppColors.primary.withValues(alpha: 0.1),
    );
  }

  // ── Search & Filter Controls ───────────────────────────────────────────────
  Widget _buildSearchAndFilters({
    required bool isDark,
    required List<String> categories,
    required int lowCount,
    required int outCount,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search TextField with Scan Button inside
        Container(
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
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _searchQuery = v.trim()),
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.darkText100 : AppColors.lightText100,
            ),
            decoration: InputDecoration(
              hintText: 'Search products, SKU or category…',
              hintStyle: TextStyle(
                fontSize: 12.5,
                color: isDark ? AppColors.darkText30 : AppColors.lightText30,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 20,
                color: isDark ? AppColors.darkText50 : AppColors.lightText50,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searchQuery.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      color: isDark
                          ? AppColors.darkText50
                          : AppColors.lightText50,
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                    tooltip: 'Scan Barcode to Filter',
                    color: isDark ? AppColors.primaryLight : AppColors.primary,
                    onPressed: () async {
                      final code = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ScannerScreen()),
                      );
                      if (code != null && mounted) {
                        setState(() {
                          _searchCtrl.text = code;
                          _searchQuery = code;
                        });
                      }
                    },
                  ),
                ],
              ),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Stock Status Filter Chips: All, In Stock, Low Stock, Out of Stock
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip(
                label: 'All Items',
                isSelected: _stockFilter == 'All',
                onSelected: () => setState(() => _stockFilter = 'All'),
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                label: 'In Stock',
                isSelected: _stockFilter == 'In Stock',
                onSelected: () => setState(() => _stockFilter = 'In Stock'),
                isDark: isDark,
                activeColor: const Color(0xFF10B981),
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                label: 'Low Stock ($lowCount)',
                isSelected: _stockFilter == 'Low Stock',
                onSelected: () => setState(() => _stockFilter = 'Low Stock'),
                isDark: isDark,
                activeColor: const Color(0xFFF59E0B),
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                label: 'Out of Stock ($outCount)',
                isSelected: _stockFilter == 'Out of Stock',
                onSelected: () =>
                    setState(() => _stockFilter = 'Out of Stock'),
                isDark: isDark,
                activeColor: const Color(0xFFEF4444),
              ),
            ],
          ),
        ),

        // Category Filter Chips (if more than 1 category)
        if (categories.length > 2) ...[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories.map((cat) {
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(cat),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() => _selectedCategory = cat);
                    },
                    selectedColor: AppColors.primary.withValues(alpha: 0.25),
                    backgroundColor: isDark
                        ? AppColors.darkSurfaceElevated
                        : const Color(0xFFF1EFFB),
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected
                          ? (isDark
                              ? AppColors.primaryLight
                              : AppColors.primary)
                          : (isDark
                              ? AppColors.darkText70
                              : AppColors.lightText70),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    side: BorderSide(
                      color: isSelected
                          ? AppColors.primary
                          : Colors.transparent,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
    required bool isDark,
    Color? activeColor,
  }) {
    final color = activeColor ?? AppColors.primary;
    return GestureDetector(
      onTap: onSelected,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: isDark ? 0.35 : 0.15)
              : (isDark
                  ? AppColors.darkSurfaceElevated
                  : const Color(0xFFF8F7FD)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? color
                : (isDark
                    ? AppColors.darkBorder
                    : AppColors.outlineVariant),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected
                ? (isDark ? Colors.white : color)
                : (isDark ? AppColors.darkText70 : AppColors.lightText70),
          ),
        ),
      ),
    );
  }

  // ── Product Item Card ──────────────────────────────────────────────────────
  Widget _buildProductCard({
    required BuildContext context,
    required Product product,
    required bool isDark,
  }) {
    final stock = product.stockQuantity;
    final isLowStock = stock <= 10 && stock > 0;
    final isOutOfStock = stock <= 0;

    final Color statusColor = isOutOfStock
        ? const Color(0xFFEF4444)
        : (isLowStock ? const Color(0xFFF59E0B) : const Color(0xFF10B981));
    final String statusLabel = isOutOfStock
        ? 'Out of Stock'
        : (isLowStock ? 'Low Stock' : 'In Stock');

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? (isOutOfStock
                  ? const Color(0xFFEF4444).withValues(alpha: 0.3)
                  : AppColors.darkBorder)
              : AppColors.primary.withValues(alpha: 0.12),
        ),
        boxShadow: CyberShadows.shadow50(isDark),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Category + Status Badge + Menu
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary
                          .withValues(alpha: isDark ? 0.25 : 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      product.category,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.primaryLight
                            : AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor
                          .withValues(alpha: isDark ? 0.22 : 0.12),
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
              // Quick 3-Dots Menu
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_horiz_rounded,
                  color: isDark ? AppColors.darkText50 : AppColors.lightText50,
                  size: 20,
                ),
                color: isDark ? AppColors.darkSurfaceElevated : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                onSelected: (val) {
                  if (val == 'replenish') {
                    StockReplenishSheet.show(context, product: product);
                  } else if (val == 'edit') {
                    showDialog(
                      context: context,
                      builder: (_) => AddProductDialog(productToEdit: product),
                    );
                  } else if (val == 'label') {
                    _printerService.printLabel(product);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Printing label for ${product.productName}'),
                        backgroundColor: AppColors.primary,
                      ),
                    );
                  } else if (val == 'delete') {
                    _confirmDelete(product);
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'replenish',
                    child: Row(
                      children: [
                        Icon(Icons.inventory_2_rounded,
                            size: 18, color: AppColors.primary),
                        SizedBox(width: 10),
                        Text('Adjust Stock Level'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('Edit Product'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'label',
                    child: Row(
                      children: [
                        Icon(Icons.qr_code_2_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('Print Barcode Label'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded,
                            size: 18, color: AppColors.error),
                        SizedBox(width: 10),
                        Text('Delete',
                            style: TextStyle(color: AppColors.error)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Middle: Product Name & SKU
          GestureDetector(
            onTap: () => StockReplenishSheet.show(context, product: product),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.productName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color:
                        isDark ? AppColors.darkText100 : AppColors.lightText100,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      'SKU: ',
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            isDark ? AppColors.darkText50 : AppColors.lightText50,
                      ),
                    ),
                    Text(
                      product.barcode?.isNotEmpty == true
                          ? product.barcode!
                          : 'No Barcode',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: product.barcode?.isNotEmpty == true
                            ? (isDark
                                ? AppColors.darkText70
                                : AppColors.lightText70)
                            : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Bottom Bar: Stock Counter & Price
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Stock Counter Stepper ([- / +])
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurfaceElevated
                      : const Color(0xFFF1EFFB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? AppColors.darkBorder
                        : AppColors.primary.withValues(alpha: 0.12),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_rounded, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 28, minHeight: 28),
                      color: isDark
                          ? AppColors.darkText70
                          : AppColors.lightText70,
                      onPressed: () => _adjustQuickDelta(product, -1),
                    ),
                    InkWell(
                      onTap: () =>
                          StockReplenishSheet.show(context, product: product),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '$stock UNITS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: isDark
                                ? AppColors.darkText100
                                : AppColors.lightText100,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_rounded, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 28, minHeight: 28),
                      color: isDark
                          ? AppColors.primaryLight
                          : AppColors.primary,
                      onPressed: () => _adjustQuickDelta(product, 1),
                    ),
                  ],
                ),
              ),

              // Price & Quick Label Button
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _currency.format(product.sellingPrice),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: isDark
                              ? AppColors.primaryLight
                              : AppColors.primary,
                        ),
                      ),
                      if (product.purchasePrice > 0)
                        Text(
                          'Cost: ${_currency.format(product.purchasePrice)}',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: isDark
                                ? AppColors.darkText50
                                : AppColors.lightText50,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: () =>
                        StockReplenishSheet.show(context, product: product),
                    tooltip: 'Quick Stock Replenish',
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary
                          .withValues(alpha: isDark ? 0.25 : 0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.all(8),
                      minimumSize: Size.zero,
                    ),
                    icon: Icon(
                      Icons.tune_rounded,
                      size: 16,
                      color: isDark
                          ? AppColors.primaryLight
                          : AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Empty State ────────────────────────────────────────────────────────────
  Widget _buildEmptyState(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? AppColors.darkBorder
              : AppColors.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: 40,
              color: isDark ? AppColors.primaryLight : AppColors.primary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _searchQuery.isNotEmpty
                ? 'No products matching "$_searchQuery"'
                : 'No products in inventory yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkText100 : AppColors.lightText100,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            _searchQuery.isNotEmpty
                ? 'Try clearing the search query or changing filters'
                : 'Scan barcodes or tap "New Product" to begin building your catalog',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.darkText50 : AppColors.lightText50,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: () {
              if (_searchQuery.isNotEmpty) {
                setState(() {
                  _searchCtrl.clear();
                  _searchQuery = '';
                  _selectedCategory = 'All';
                  _stockFilter = 'All';
                });
              } else {
                showDialog(
                  context: context,
                  builder: (_) => const AddProductDialog(),
                );
              }
            },
            icon: Icon(
              _searchQuery.isNotEmpty
                  ? Icons.clear_rounded
                  : Icons.add_rounded,
              size: 18,
            ),
            label: Text(
              _searchQuery.isNotEmpty ? 'Reset Filters' : 'Add First Product',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
