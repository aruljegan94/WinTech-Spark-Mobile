import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/theme.dart';
import '../../core/models/models.dart';
import '../../services/invoice_service.dart';
import '../../services/hive_service.dart';
import 'invoice_detail_screen.dart';
import 'widgets/thermal_print_dialog.dart';

class CreateInvoiceScreen extends StatefulWidget {
  final Map<String, dynamic>? editData;
  const CreateInvoiceScreen({super.key, this.editData});

  @override
  State<CreateInvoiceScreen> createState() => _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends State<CreateInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fmt = NumberFormat('#,##,##0.00', 'en_IN');

  String? _selectedCustomerId;
  final _customerCtrl = TextEditingController();
  final _customerMobileCtrl = TextEditingController();
  final _customerAddressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  final _itemNameCtrl = TextEditingController();
  final _itemQtyCtrl = TextEditingController(text: '1');
  final _itemPriceCtrl = TextEditingController();
  final _itemGstCtrl = TextEditingController(text: '18');

  String _paymentMode = 'Cash';
  String _paymentStatus = 'Paid';
  double _paidAmount = 0;
  bool _isSaving = false;
  String _invoiceNumberPreview = 'INV-...';

  final List<SaleItem> _cartItems = [];

  // Computed totals
  double get _subtotal =>
      _cartItems.fold(0, (sum, i) => sum + (i.price * i.quantity));
  double get _gstAmount => _cartItems.fold(
      0, (sum, i) => sum + (i.price * i.quantity * i.gstPercentage / 100));
  double get _total => _subtotal + _gstAmount;
  double get _balanceDue =>
      _paymentStatus == 'Paid' ? 0.0 : (_total - _paidAmount).clamp(0.0, _total);

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    if (widget.editData != null) {
      final d = widget.editData!;
      _selectedCustomerId = d['customerId'];
      _customerCtrl.text = d['customerName'] ?? '';
      _customerMobileCtrl.text = d['customerMobile'] ?? '';
      _customerAddressCtrl.text = d['customerAddress'] ?? '';
      _notesCtrl.text = d['notes'] ?? '';
      _paymentMode = d['paymentMode'] ?? 'Cash';
      _paymentStatus = d['paymentStatus'] ?? d['status'] ?? 'Paid';
      _paidAmount = (d['paidAmount'] ?? d['amountPaid'] ?? 0).toDouble();
      _invoiceNumberPreview = d['invoiceNumber'] ?? 'INV';

      for (final item in (d['items'] as List? ?? [])) {
        _cartItems.add(SaleItem(
          productId: item['productId'] ?? const Uuid().v4(),
          productName: item['productName'] ?? '',
          quantity: (item['quantity'] ?? 1) is int
              ? item['quantity']
              : (item['quantity'] as num).toInt(),
          price: (item['price'] ?? 0).toDouble(),
          gstPercentage: (item['gstPercentage'] ?? 18).toDouble(),
          total: (item['total'] ?? 0).toDouble(),
        ));
      }
    } else {
      final nextNo = await InvoiceService.getNextInvoiceNumber();
      if (mounted) {
        setState(() => _invoiceNumberPreview = nextNo);
      }
    }
  }

  @override
  void dispose() {
    _customerCtrl.dispose();
    _customerMobileCtrl.dispose();
    _customerAddressCtrl.dispose();
    _notesCtrl.dispose();
    _itemNameCtrl.dispose();
    _itemQtyCtrl.dispose();
    _itemPriceCtrl.dispose();
    _itemGstCtrl.dispose();
    super.dispose();
  }

  void _addItem({String? matchedProductId}) {
    final name = _itemNameCtrl.text.trim();
    final qty = int.tryParse(_itemQtyCtrl.text) ?? 1;
    final price = double.tryParse(_itemPriceCtrl.text) ?? 0;
    final gst = double.tryParse(_itemGstCtrl.text) ?? 18;

    if (name.isEmpty || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid item name and price')),
      );
      return;
    }

    String productId = matchedProductId ?? '';
    if (productId.isEmpty) {
      final allProducts = HiveService.getAllProducts();
      try {
        final found = allProducts.firstWhere(
          (p) => p.productName.trim().toLowerCase() == name.toLowerCase(),
        );
        productId = found.id;
      } catch (_) {
        productId = const Uuid().v4();
      }
    }

    setState(() {
      _cartItems.add(SaleItem(
        productId: productId,
        productName: name,
        quantity: qty,
        price: price,
        gstPercentage: gst,
        total: price * qty * (1 + gst / 100),
      ));
      _itemNameCtrl.clear();
      _itemQtyCtrl.text = '1';
      _itemPriceCtrl.clear();
      _itemGstCtrl.text = '18';
    });
  }

  void _addOrIncrementProductToCart(Product product) {
    setState(() {
      final existingIndex =
          _cartItems.indexWhere((item) => item.productId == product.id);
      if (existingIndex >= 0) {
        final existing = _cartItems[existingIndex];
        final newQty = existing.quantity + 1;
        _cartItems[existingIndex] = SaleItem(
          productId: existing.productId,
          productName: existing.productName,
          quantity: newQty,
          price: existing.price,
          gstPercentage: existing.gstPercentage,
          total: existing.price * newQty * (1 + existing.gstPercentage / 100),
        );
      } else {
        _cartItems.add(SaleItem(
          productId: product.id,
          productName: product.productName,
          quantity: 1,
          price: product.sellingPrice,
          gstPercentage: product.gstPercentage,
          total: product.sellingPrice * (1 + product.gstPercentage / 100),
        ));
      }
    });
  }

  Future<void> _saveInvoice({
    bool openWhatsApp = false,
    bool printImmediately = false,
  }) async {
    if (_cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one item to invoice')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final paid = _paymentStatus == 'Paid'
          ? _total
          : _paymentStatus == 'Pending'
              ? 0.0
              : _paidAmount;

      final result = await InvoiceService.saveInvoice(
        docId: widget.editData?['_docId'] ?? widget.editData?['id'],
        existingInvoiceNumber: widget.editData?['invoiceNumber'] ??
            (_invoiceNumberPreview.startsWith('INV-')
                ? _invoiceNumberPreview
                : null),
        originalDate: widget.editData?['date'],
        items: _cartItems,
        subtotal: _subtotal,
        gstAmount: _gstAmount,
        total: _total,
        paymentMode: _paymentMode,
        paymentStatus: _paymentStatus,
        customerId: _selectedCustomerId,
        customerName: _customerCtrl.text.trim().isNotEmpty
            ? _customerCtrl.text.trim()
            : 'Walk-in Customer',
        customerMobile: _customerMobileCtrl.text.trim(),
        customerAddress: _customerAddressCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
        paidAmount: paid,
      );

      final invoiceMap = {
        '_docId': result['docId'],
        'invoiceNumber': result['invoiceNumber'],
        'customerId': _selectedCustomerId,
        'customerName': _customerCtrl.text.trim().isNotEmpty
            ? _customerCtrl.text.trim()
            : 'Walk-in Customer',
        'customerMobile': _customerMobileCtrl.text.trim(),
        'customerAddress': _customerAddressCtrl.text.trim(),
        'date': result['date'],
        'paymentMode': _paymentMode,
        'paymentStatus': _paymentStatus,
        'status': _paymentStatus,
        'paidAmount': paid,
        'amountPaid': paid,
        'items': _cartItems
            .map((i) => {
                  'productId': i.productId,
                  'productName': i.productName,
                  'quantity': i.quantity,
                  'price': i.price,
                  'gstPercentage': i.gstPercentage,
                  'total': i.total,
                })
            .toList(),
        'subtotal': _subtotal,
        'gstAmount': _gstAmount,
        'total': _total,
        'notes': _notesCtrl.text.trim(),
      };

      if (!mounted) return;

      if (openWhatsApp) {
        await InvoiceService.shareInvoiceViaWhatsApp(invoiceMap);
      }

      if (!mounted) return;

      if (printImmediately) {
        await ThermalPrintDialog.show(context, invoice: invoiceMap);
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => InvoiceDetailScreen(invoice: invoiceMap),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.editData != null ? 'Edit Invoice' : 'New Tax Invoice',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Row(
              children: [
                const Icon(Icons.sync_rounded, color: Colors.green, size: 12),
                const SizedBox(width: 4),
                Text(
                  _invoiceNumberPreview,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _showScanner(context),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: 'Scan Barcodes Continuously',
          ),
          TextButton.icon(
            onPressed: _isSaving ? null : () => _saveInvoice(openWhatsApp: false),
            icon: _isSaving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Customer Details Section ─────────────────────────────
                    _buildCustomerSection(),
                    const SizedBox(height: 20),

                    // ── Add Item Section ─────────────────────────────────────
                    _buildAddItemSection(),
                    const SizedBox(height: 20),

                    // ── Cart Items List ──────────────────────────────────────
                    if (_cartItems.isNotEmpty) ...[
                      _sectionHeader('Invoice Items (${_cartItems.length})'),
                      const SizedBox(height: 8),
                      ..._cartItems.asMap().entries.map((e) => _buildCartItemCard(e.key, e.value)),
                      const SizedBox(height: 20),
                    ],

                    // ── Payment Details Section ──────────────────────────────
                    _buildPaymentSection(),
                    const SizedBox(height: 20),

                    // ── Notes Section ────────────────────────────────────────
                    _buildNotesSection(),
                  ],
                ),
              ),
            ),

            // ── Sticky Checkout Bar ──────────────────────────────────────────
            _buildBottomCheckoutBar(),
          ],
        ),
      ),
    );
  }

  // ── Customer Card & Pickers ────────────────────────────────────────────────
  Widget _buildCustomerSection() {
    return _SectionContainer(
      title: 'CUSTOMER INFORMATION',
      action: TextButton.icon(
        onPressed: _showCustomerPickerSheet,
        icon: const Icon(Icons.people_alt_rounded, size: 16),
        label: const Text('Pick Customer', style: TextStyle(fontSize: 12)),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        ),
      ),
      child: Column(
        children: [
          TextFormField(
            controller: _customerCtrl,
            decoration: _inputDeco(
              label: 'Customer Name',
              icon: Icons.person_rounded,
              hint: 'e.g. John Doe or Walk-in Customer',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _customerMobileCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: _inputDeco(
                    label: 'Mobile Number',
                    icon: Icons.phone_android_rounded,
                    hint: '10-digit number',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _customerAddressCtrl,
                  decoration: _inputDeco(
                    label: 'City / Address',
                    icon: Icons.location_on_rounded,
                    hint: 'Optional',
                  ),
                ),
              ),
            ],
          ),
          if (_selectedCustomerId != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.link_rounded, size: 14, color: Colors.green),
                const SizedBox(width: 4),
                const Text(
                  'Linked to Customer Database',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.green,
                      fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedCustomerId = null;
                      _customerCtrl.clear();
                      _customerMobileCtrl.clear();
                      _customerAddressCtrl.clear();
                    });
                  },
                  child: const Text('Unlink',
                      style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Add Item Section ───────────────────────────────────────────────────────
  Widget _buildAddItemSection() {
    return _SectionContainer(
      title: 'ADD PRODUCTS',
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: _showProductCatalogSheet,
            icon: const Icon(Icons.inventory_2_rounded,
                color: AppColors.primary, size: 20),
            tooltip: 'Browse Inventory',
          ),
          IconButton(
            onPressed: () => _showScanner(context),
            icon: const Icon(Icons.qr_code_scanner_rounded,
                color: AppColors.primary, size: 20),
            tooltip: 'Scan Barcode',
          ),
        ],
      ),
      child: Column(
        children: [
          TextFormField(
            controller: _itemNameCtrl,
            decoration: _inputDeco(
              label: 'Item Description / Name',
              icon: Icons.label_outline_rounded,
              hint: 'Enter item or scan barcode',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _itemPriceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: _inputDeco(
                    label: 'Price (₹)',
                    icon: Icons.currency_rupee_rounded,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _itemQtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: _inputDeco(
                    label: 'Qty',
                    icon: Icons.numbers_rounded,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _itemGstCtrl,
                  keyboardType: TextInputType.number,
                  decoration: _inputDeco(
                    label: 'GST%',
                    icon: Icons.percent_rounded,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _addItem(),
              icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
              label: const Text('Add to Bill'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: AppColors.primary, width: 1.5),
                foregroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Cart Items List Card ───────────────────────────────────────────────────
  Widget _buildCartItemCard(int idx, SaleItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  '₹${_fmt.format(item.price)} × ${item.quantity}  (+${item.gstPercentage.toStringAsFixed(0)}% GST)',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove_circle_outline_rounded,
                    size: 20, color: Colors.grey),
                onPressed: () {
                  if (item.quantity > 1) {
                    setState(() {
                      final updated = SaleItem(
                        productId: item.productId,
                        productName: item.productName,
                        quantity: item.quantity - 1,
                        price: item.price,
                        gstPercentage: item.gstPercentage,
                        total: item.price *
                            (item.quantity - 1) *
                            (1 + item.gstPercentage / 100),
                      );
                      _cartItems[idx] = updated;
                    });
                  } else {
                    setState(() => _cartItems.removeAt(idx));
                  }
                },
              ),
              Text(
                '${item.quantity}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_circle_outline_rounded,
                    size: 20, color: AppColors.primary),
                onPressed: () {
                  setState(() {
                    final updated = SaleItem(
                      productId: item.productId,
                      productName: item.productName,
                      quantity: item.quantity + 1,
                      price: item.price,
                      gstPercentage: item.gstPercentage,
                      total: item.price *
                          (item.quantity + 1) *
                          (1 + item.gstPercentage / 100),
                    );
                    _cartItems[idx] = updated;
                  });
                },
              ),
              const SizedBox(width: 8),
              Text(
                '₹${_fmt.format(item.total)}',
                style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                    fontSize: 14),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 18, color: Colors.redAccent),
                onPressed: () => setState(() => _cartItems.removeAt(idx)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Payment Section ────────────────────────────────────────────────────────
  Widget _buildPaymentSection() {
    return _SectionContainer(
      title: 'PAYMENT DETAILS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Payment Mode Selector
          Row(
            children: ['Cash', 'UPI', 'Card', 'Bank'].map((mode) {
              final isSelected = _paymentMode == mode;
              IconData icon = Icons.payments_outlined;
              if (mode == 'UPI') icon = Icons.qr_code_2_rounded;
              if (mode == 'Card') icon = Icons.credit_card_rounded;
              if (mode == 'Bank') icon = Icons.account_balance_rounded;

              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _paymentMode = mode),
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.12)
                          : AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected
                          ? Border.all(color: AppColors.primary, width: 1.5)
                          : null,
                    ),
                    child: Column(
                      children: [
                        Icon(icon,
                            size: 18,
                            color: isSelected ? AppColors.primary : Colors.grey),
                        const SizedBox(height: 4),
                        Text(
                          mode,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? AppColors.primary
                                : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Payment Status Selector
          Row(
            children: ['Paid', 'Partial', 'Pending'].map((status) {
              final isSelected = _paymentStatus == status;
              Color col = Colors.green;
              if (status == 'Partial') col = Colors.orange;
              if (status == 'Pending') col = Colors.redAccent;

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _paymentStatus = status;
                      if (status == 'Paid') _paidAmount = _total;
                      if (status == 'Pending') _paidAmount = 0.0;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? col.withValues(alpha: 0.15)
                          : AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected
                          ? Border.all(color: col, width: 1.5)
                          : null,
                    ),
                    child: Text(
                      status,
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

          // If Partial Payment, Show Amount Paid Input
          if (_paymentStatus == 'Partial') ...[
            const SizedBox(height: 16),
            TextFormField(
              initialValue: _paidAmount > 0 ? _paidAmount.toString() : '',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: _inputDeco(
                label: 'Amount Collected Today (₹)',
                icon: Icons.currency_rupee_rounded,
                hint: 'e.g. 500',
              ),
              onChanged: (v) {
                setState(() {
                  _paidAmount = double.tryParse(v) ?? 0;
                });
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Balance Due to collect later: ₹${_fmt.format(_balanceDue)}',
              style: const TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Notes Section ──────────────────────────────────────────────────────────
  Widget _buildNotesSection() {
    return _SectionContainer(
      title: 'REMARKS & NOTES',
      child: TextFormField(
        controller: _notesCtrl,
        maxLines: 2,
        decoration: _inputDeco(
          label: 'Notes / Vehicle Reg # / Terms',
          icon: Icons.notes_rounded,
          hint: 'e.g. TN-09-AB-1234, Brake service',
        ),
      ),
    );
  }

  // ── Bottom Sticky Checkout Bar ─────────────────────────────────────────────
  Widget _buildBottomCheckoutBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('GRAND TOTAL',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            letterSpacing: 1.2)),
                    Text(
                      '₹${_fmt.format(_total)}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                Text(
                  'Tax: ₹${_fmt.format(_gstAmount)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // WhatsApp Button
                IconButton.outlined(
                  onPressed:
                      _isSaving ? null : () => _saveInvoice(openWhatsApp: true),
                  tooltip: 'Share on WhatsApp',
                  icon: const Icon(Icons.chat_bubble_rounded,
                      color: Color(0xFF1EBE5D), size: 20),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(14),
                    side: const BorderSide(color: Color(0xFF25D366), width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Save Only Button
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    onPressed: _isSaving
                        ? null
                        : () => _saveInvoice(openWhatsApp: false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.primary, width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Save',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Save & Print Button (Hero Retail Action)
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving
                        ? null
                        : () => _saveInvoice(printImmediately: true),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.print_rounded,
                            size: 18, color: Colors.white),
                    label: const Text(
                      'Save & Print',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
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

  // ── Customer Database Picker Sheet ─────────────────────────────────────────
  void _showCustomerPickerSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) => Container(
            height: MediaQuery.of(context).size.height * 0.75,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Select Customer',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  onChanged: (v) => setSheetState(() => query = v.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search customer by name or phone…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: AppColors.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: StreamBuilder<List<Customer>>(
                    stream: InvoiceService.streamCustomers(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      var customers = snap.data ?? [];
                      if (query.isNotEmpty) {
                        customers = customers.where((c) {
                          return c.name.toLowerCase().contains(query) ||
                              c.mobile.contains(query);
                        }).toList();
                      }

                      if (customers.isEmpty) {
                        return const Center(
                          child: Text('No matching customers found.',
                              style: TextStyle(color: Colors.grey)),
                        );
                      }

                      return ListView.separated(
                        itemCount: customers.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final c = customers[i];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  AppColors.primary.withValues(alpha: 0.1),
                              child: Text(
                                c.name.isNotEmpty ? c.name[0].toUpperCase() : 'C',
                                style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(c.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(
                                '${c.mobile}${c.pendingDue > 0 ? " • Due: ₹${c.pendingDue.toStringAsFixed(0)}" : ""}'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () {
                              setState(() {
                                _selectedCustomerId = c.id;
                                _customerCtrl.text = c.name;
                                _customerMobileCtrl.text = c.mobile;
                                _customerAddressCtrl.text = c.address ?? '';
                              });
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Browse Product Catalog Sheet ───────────────────────────────────────────
  void _showProductCatalogSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final allProducts = HiveService.getAllProducts();
            var filtered = allProducts;
            if (query.isNotEmpty) {
              filtered = filtered
                  .where((p) =>
                      p.productName.toLowerCase().contains(query) ||
                      p.category.toLowerCase().contains(query) ||
                      (p.barcode != null && p.barcode!.contains(query)))
                  .toList();
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Select Product from Inventory',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    onChanged: (v) => setSheetState(() => query = v.toLowerCase()),
                    decoration: InputDecoration(
                      hintText: 'Search product name, category, or barcode…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: AppColors.surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text('No products found',
                                style: TextStyle(color: Colors.grey)))
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final p = filtered[i];
                              final isLow = p.stockQuantity <= 5;
                              return ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isLow
                                        ? Colors.orange.withValues(alpha: 0.1)
                                        : Colors.green.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.inventory_2_rounded,
                                      color: isLow ? Colors.orange : Colors.green,
                                      size: 20),
                                ),
                                title: Text(p.productName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                    '${p.category} • In Stock: ${p.stockQuantity}'),
                                trailing: Text(
                                  '₹${_fmt.format(p.sellingPrice)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                      color: AppColors.primary),
                                ),
                                onTap: () {
                                  setState(() {
                                    _itemNameCtrl.text = p.productName;
                                    _itemPriceCtrl.text =
                                        p.sellingPrice.toString();
                                    _itemGstCtrl.text =
                                        p.gstPercentage.toString();
                                    _itemQtyCtrl.text = '1';
                                  });
                                  Navigator.pop(ctx);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Barcode Scanner Sheet (Continuous Auto-Cart) ───────────────────────────
  void _showScanner(BuildContext context) {
    DateTime? lastScanTime;
    String? lastScannedBarcode;
    String? feedbackMessage;
    bool feedbackSuccess = true;
    final scannerController = MobileScannerController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final isDark = Theme.of(sheetCtx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              height: MediaQuery.of(sheetCtx).size.height * 0.80,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : Colors.grey.shade200,
                ),
              ),
              child: Column(
                children: [
                  // Handle & Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Column(
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white24
                                  : Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.qr_code_scanner_rounded,
                                  color: AppColors.primary, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Continuous Barcode Scanner',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.white
                                          : AppColors.onSurface,
                                    ),
                                  ),
                                  Text(
                                    'Point camera at barcode to auto-add to cart',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.white54
                                          : AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => scannerController.toggleTorch(),
                              icon: const Icon(Icons.flash_on_rounded),
                              tooltip: 'Toggle Flashlight',
                            ),
                            IconButton(
                              onPressed: () {
                                scannerController.dispose();
                                Navigator.pop(sheetCtx);
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Scanner Viewport
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.black,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          MobileScanner(
                            controller: scannerController,
                            onDetect: (capture) {
                              final List<Barcode> barcodes = capture.barcodes;
                              if (barcodes.isEmpty) return;
                              final code = barcodes.first.rawValue?.trim();
                              if (code == null || code.isEmpty) return;

                              final now = DateTime.now();
                              if (lastScannedBarcode == code &&
                                  lastScanTime != null &&
                                  now
                                          .difference(lastScanTime!)
                                          .inMilliseconds <
                                      1400) {
                                return; // Debounce same barcode within 1.4s
                              }

                              lastScanTime = now;
                              lastScannedBarcode = code;

                              final product =
                                  HiveService.getProductByBarcode(code);
                              if (product != null) {
                                HapticFeedback.mediumImpact();
                                _addOrIncrementProductToCart(product);
                                final inCart = _cartItems.firstWhere(
                                    (i) => i.productId == product.id);

                                setSheetState(() {
                                  feedbackSuccess = true;
                                  feedbackMessage =
                                      'Added "${product.productName}" (Qty: ${inCart.quantity}) • ₹${product.sellingPrice.toStringAsFixed(0)}';
                                });
                              } else {
                                HapticFeedback.vibrate();
                                setSheetState(() {
                                  feedbackSuccess = false;
                                  feedbackMessage =
                                      'Barcode "$code" not found in inventory';
                                });
                              }
                            },
                          ),

                          // Target Viewfinder Overlay
                          Container(
                            width: 250,
                            height: 160,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppColors.primary,
                                width: 2.5,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Feedback / Status Banner
                  if (feedbackMessage != null)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: feedbackSuccess
                            ? (isDark
                                ? const Color(0xFF0F3820)
                                : const Color(0xFFE8F5E9))
                            : (isDark
                                ? const Color(0xFF3B1E08)
                                : const Color(0xFFFFF3E0)),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: feedbackSuccess ? Colors.green : Colors.orange,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            feedbackSuccess
                                ? Icons.check_circle_rounded
                                : Icons.info_outline_rounded,
                            color:
                                feedbackSuccess ? Colors.green : Colors.orange,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              feedbackMessage!,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: feedbackSuccess
                                    ? (isDark
                                        ? Colors.greenAccent
                                        : Colors.green.shade800)
                                    : (isDark
                                        ? Colors.orangeAccent
                                        : Colors.orange.shade900),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Bottom Cart Preview & Done Action
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurfaceElevated
                          : Colors.grey.shade50,
                      border: Border(
                        top: BorderSide(
                          color: isDark
                              ? AppColors.darkBorder
                              : Colors.grey.shade200,
                        ),
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${_cartItems.length} Products in Cart',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: isDark
                                        ? Colors.white
                                        : AppColors.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '₹${_fmt.format(_total)} Total (incl. GST)',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () {
                              scannerController.dispose();
                              Navigator.pop(sheetCtx);
                            },
                            icon: const Icon(Icons.done_all_rounded, size: 18),
                            label: const Text('Done Scanning'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
        color: Colors.grey,
      ),
    );
  }

  InputDecoration _inputDeco({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 20, color: AppColors.primary),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.25)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.25)),
      ),
    );
  }
}

class _SectionContainer extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? action;

  const _SectionContainer({
    required this.title,
    required this.child,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: Colors.grey,
              ),
            ),
            if (action != null) action!,
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.15)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ],
    );
  }
}
