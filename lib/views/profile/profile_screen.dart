import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/models/models.dart';
import '../../core/models/shop_settings.dart';
import '../../services/auth_service.dart';
import '../../services/hive_service.dart';
import '../../services/theme_service.dart';
import '../../services/sync_service.dart';
import '../../services/printer_service.dart';
import '../billing/widgets/thermal_print_dialog.dart';
import '../login/login_screen.dart';
import '../home/main_layout.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _businessFormKey = GlobalKey<FormState>();
  final _invoiceFormKey = GlobalKey<FormState>();

  // ── User Information (Firebase Auth & Firestore users/{uid}) ─────────────
  final User? _user = FirebaseAuth.instance.currentUser;
  final AuthService _authService = AuthService();
  String _userRole = 'Admin';
  String _userPhoneNumber = '';

  // ── Business Profile Controllers (Firestore companyProfiles collection) ──
  String? _profileDocId;
  late TextEditingController _companyNameCtrl;
  late TextEditingController _ownedByCtrl;
  late TextEditingController _contactCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _gstCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _stateCtrl;
  late TextEditingController _stateCodeCtrl;

  // Bank & UPI Details
  late TextEditingController _bankNameCtrl;
  late TextEditingController _bankAccountCtrl;
  late TextEditingController _bankIfscCtrl;
  late TextEditingController _bankBranchCtrl;
  late TextEditingController _upiIdCtrl;
  late TextEditingController _termsCtrl;

  // ── Invoice & Print Settings (Firestore settings/app & companyProfiles) ─
  late TextEditingController _prefixCtrl;
  late TextEditingController _suffixCtrl;
  String _defaultPrintMode = 'thermal-80'; // 'thermal-80' | 'thermal-58' | 'a4'
  String _defaultPaymentMode = 'Cash'; // 'Cash' | 'UPI'
  late ShopSettings _settings;

  // ── App & Sync Preferences (Firestore settings/app) ─────────────────────
  int _lowStockThreshold = 5;
  bool _lowStockAlerts = true;
  bool _overdueInvoiceAlerts = true;
  bool _isSavingBusiness = false;
  bool _isSavingInvoice = false;
  bool _isSavingAppSettings = false;
  bool _isFullSyncing = false;
  DateTime? _lastSyncTimestamp;

  // Local Counts
  int _localProductCount = 0;
  int _localSaleCount = 0;
  int _localExpenseCount = 0;

  // Printer Service
  final ThermalPrinterService _printerService = ThermalPrinterService();
  bool _isTestingPrinter = false;

  @override
  void initState() {
    super.initState();
    _settings = HiveService.getShopSettings();

    // Initialize controllers with local Hive fallback
    _companyNameCtrl = TextEditingController(text: _settings.shopName);
    _ownedByCtrl = TextEditingController(text: _user?.displayName ?? '');
    _contactCtrl = TextEditingController();
    _emailCtrl = TextEditingController(text: _user?.email ?? '');
    _gstCtrl = TextEditingController();
    _addressCtrl = TextEditingController(text: _settings.location);
    _stateCtrl = TextEditingController(text: 'Tamil Nadu');
    _stateCodeCtrl = TextEditingController(text: '33');

    _bankNameCtrl = TextEditingController();
    _bankAccountCtrl = TextEditingController();
    _bankIfscCtrl = TextEditingController();
    _bankBranchCtrl = TextEditingController();
    _upiIdCtrl = TextEditingController();
    _termsCtrl = TextEditingController(
      text: '1. Goods once sold will not be returned.\n2. Subject to local jurisdiction.',
    );

    _prefixCtrl = TextEditingController(text: _settings.invoicePrefix);
    _suffixCtrl = TextEditingController(text: _settings.invoiceSuffix);

    _loadCounts();
    _loadCloudData();
  }

  @override
  void dispose() {
    _companyNameCtrl.dispose();
    _ownedByCtrl.dispose();
    _contactCtrl.dispose();
    _emailCtrl.dispose();
    _gstCtrl.dispose();
    _addressCtrl.dispose();
    _stateCtrl.dispose();
    _stateCodeCtrl.dispose();
    _bankNameCtrl.dispose();
    _bankAccountCtrl.dispose();
    _bankIfscCtrl.dispose();
    _bankBranchCtrl.dispose();
    _upiIdCtrl.dispose();
    _termsCtrl.dispose();
    _prefixCtrl.dispose();
    _suffixCtrl.dispose();
    super.dispose();
  }

  void _loadCounts() {
    try {
      _localProductCount =
          HiveService.getBox<Product>(HiveService.productBoxName).length;
      _localSaleCount =
          HiveService.getBox<Sale>(HiveService.saleBoxName).length;
      _localExpenseCount =
          HiveService.getBox<Expense>(HiveService.expenseBoxName).length;
    } catch (_) {}
  }

  /// Pulls existing settings and company profile from Firestore web collections
  Future<void> _loadCloudData() async {
    try {
      // 1. Company Profile
      final profile = await SyncService.fetchCompanyProfile();
      if (profile != null && mounted) {
        setState(() {
          _profileDocId = profile['id'];
          if ((profile['companyName'] ?? '').isNotEmpty) {
            _companyNameCtrl.text = profile['companyName'];
          }
          if ((profile['ownedBy'] ?? '').isNotEmpty) {
            _ownedByCtrl.text = profile['ownedBy'];
          }
          if ((profile['contact'] ?? '').isNotEmpty) {
            _contactCtrl.text = profile['contact'];
          }
          if ((profile['email'] ?? '').isNotEmpty) {
            _emailCtrl.text = profile['email'];
          }
          if ((profile['gstNumber'] ?? '').isNotEmpty) {
            _gstCtrl.text = profile['gstNumber'];
          }
          if ((profile['address'] ?? '').isNotEmpty) {
            _addressCtrl.text = profile['address'];
          }
          if ((profile['state'] ?? '').isNotEmpty) {
            _stateCtrl.text = profile['state'];
          }
          if ((profile['stateCode'] ?? '').isNotEmpty) {
            _stateCodeCtrl.text = profile['stateCode'];
          }
          if ((profile['bankName'] ?? '').isNotEmpty) {
            _bankNameCtrl.text = profile['bankName'];
          }
          if ((profile['bankAccountNumber'] ?? '').isNotEmpty) {
            _bankAccountCtrl.text = profile['bankAccountNumber'];
          }
          if ((profile['bankIfsc'] ?? '').isNotEmpty) {
            _bankIfscCtrl.text = profile['bankIfsc'];
          }
          if ((profile['bankBranch'] ?? '').isNotEmpty) {
            _bankBranchCtrl.text = profile['bankBranch'];
          }
          if ((profile['upiId'] ?? '').isNotEmpty) {
            _upiIdCtrl.text = profile['upiId'];
          }
          if ((profile['termsAndConditions'] ?? '').isNotEmpty) {
            _termsCtrl.text = profile['termsAndConditions'];
          }
          if ((profile['invoicePrefix'] ?? '').isNotEmpty) {
            _prefixCtrl.text = profile['invoicePrefix'];
          }
          if ((profile['invoiceSuffix'] ?? '').isNotEmpty) {
            _suffixCtrl.text = profile['invoiceSuffix'];
          }
        });
      }

      // 2. Global App Settings
      final appSettings = await SyncService.fetchAppSettings();
      if (appSettings != null && mounted) {
        setState(() {
          if (appSettings['defaultPrintMode'] != null) {
            _defaultPrintMode = appSettings['defaultPrintMode'];
          }
          if (appSettings['defaultPaymentMode'] != null) {
            _defaultPaymentMode = appSettings['defaultPaymentMode'];
          }
          if (appSettings['lowStockThreshold'] != null) {
            _lowStockThreshold = (appSettings['lowStockThreshold'] as num).toInt();
          }
          if (appSettings['lowStockAlerts'] != null) {
            _lowStockAlerts = appSettings['lowStockAlerts'] == true;
          }
          if (appSettings['overdueInvoiceAlerts'] != null) {
            _overdueInvoiceAlerts = appSettings['overdueInvoiceAlerts'] == true;
          }
        });
      }

      // 3. User Profile
      if (_user != null) {
        final userData = await SyncService.fetchUserProfile(_user!.uid);
        if (userData != null && mounted) {
          setState(() {
            _userRole = userData['role'] ?? 'Admin';
            _userPhoneNumber = userData['phoneNumber'] ?? '';
          });
        }
      }
    } catch (e) {
      debugPrint('[ProfileScreen] Load cloud error: $e');
    }
  }

  // ── Save Business Profile ──────────────────────────────────────────────────
  Future<void> _saveBusinessProfile() async {
    if (!_businessFormKey.currentState!.validate()) return;
    setState(() => _isSavingBusiness = true);

    final profileMap = <String, dynamic>{
      if (_profileDocId != null) 'id': _profileDocId,
      'companyName': _companyNameCtrl.text.trim(),
      'ownedBy': _ownedByCtrl.text.trim(),
      'contact': _contactCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'gstNumber': _gstCtrl.text.trim().toUpperCase(),
      'address': _addressCtrl.text.trim(),
      'state': _stateCtrl.text.trim(),
      'stateCode': _stateCodeCtrl.text.trim(),
      'bankName': _bankNameCtrl.text.trim(),
      'bankAccountNumber': _bankAccountCtrl.text.trim(),
      'bankIfsc': _bankIfscCtrl.text.trim().toUpperCase(),
      'bankBranch': _bankBranchCtrl.text.trim(),
      'upiId': _upiIdCtrl.text.trim(),
      'termsAndConditions': _termsCtrl.text.trim(),
      'invoicePrefix': _prefixCtrl.text.trim(),
      'invoiceSuffix': _suffixCtrl.text.trim(),
    };

    final ok = await SyncService.saveCompanyProfile(profileMap);
    if (mounted) {
      setState(() => _isSavingBusiness = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(ok
                  ? 'Business Profile Synced with Spark Web!'
                  : 'Failed to sync with cloud. Saved locally.'),
            ],
          ),
          backgroundColor: ok ? Colors.green.shade700 : Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  // ── Save Invoice & Print Settings ─────────────────────────────────────────
  Future<void> _saveInvoiceSettings() async {
    if (!_invoiceFormKey.currentState!.validate()) return;
    setState(() => _isSavingInvoice = true);

    final prefix = _prefixCtrl.text.trim();
    final suffix = _suffixCtrl.text.trim();

    // 1. Update local Hive ShopSettings
    final updated = ShopSettings(
      shopName: _companyNameCtrl.text.trim(),
      location: _addressCtrl.text.trim(),
      invoicePrefix: prefix.isNotEmpty ? prefix : 'INV-',
      invoiceSuffix: suffix,
      invoiceCounter: _settings.invoiceCounter,
    );
    await HiveService.saveShopSettings(updated);
    _settings = updated;

    // 2. Sync to Firestore settings/app and companyProfiles
    await SyncService.saveAppSettings({
      'invoicePrefix': prefix,
      'invoiceSuffix': suffix,
      'defaultPrintMode': _defaultPrintMode,
      'defaultPaymentMode': _defaultPaymentMode,
    });

    if (_profileDocId != null) {
      await SyncService.saveCompanyProfile({
        'id': _profileDocId,
        'invoicePrefix': prefix,
        'invoiceSuffix': suffix,
      });
    }

    if (mounted) {
      setState(() => _isSavingInvoice = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('Invoice & Print preferences synced with Web!'),
            ],
          ),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  // ── Save App Preferences ──────────────────────────────────────────────────
  Future<void> _saveAppPreferences() async {
    setState(() => _isSavingAppSettings = true);

    await SyncService.saveAppSettings({
      'lowStockThreshold': _lowStockThreshold,
      'lowStockAlerts': _lowStockAlerts,
      'overdueInvoiceAlerts': _overdueInvoiceAlerts,
      'defaultPrintMode': _defaultPrintMode,
      'defaultPaymentMode': _defaultPaymentMode,
    });

    if (mounted) {
      setState(() => _isSavingAppSettings = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('App & Alert preferences saved to cloud!'),
            ],
          ),
          backgroundColor: AppColors.tertiary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  // ── Full Manual Sync ──────────────────────────────────────────────────────
  Future<void> _triggerFullSync() async {
    setState(() => _isFullSyncing = true);
    final result = await SyncService.performFullSync();
    _loadCounts();

    if (mounted) {
      setState(() {
        _isFullSyncing = false;
        _lastSyncTimestamp = DateTime.now();
      });

      final success = result['success'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.sync_rounded : Icons.warning_amber_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  success
                      ? 'Full Sync Complete! $_localProductCount products, $_localSaleCount invoices updated.'
                      : 'Sync failed: ${result['error'] ?? 'Network error'}',
                ),
              ),
            ],
          ),
          backgroundColor: success ? Colors.green.shade700 : Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  // ── Bluetooth Printer Scanner & Test Print ────────────────────────────────
  void _openBluetoothScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BluetoothDevicePicker(
        printerService: _printerService,
        onConnected: (device) {
          setState(() {});
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Future<void> _handleTestPrint() async {
    if (!_printerService.isConnected) {
      _openBluetoothScanner();
      return;
    }

    setState(() => _isTestingPrinter = true);
    final ok = await _printerService.printTestReceipt(
      is3Inch: _defaultPrintMode == 'thermal-80',
    );
    if (mounted) {
      setState(() => _isTestingPrinter = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Test receipt sent to printer!'
                : 'Could not print test receipt. Check printer power & paper.',
          ),
          backgroundColor: ok ? Colors.green : Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Purge Cache Dialog ────────────────────────────────────────────────────
  void _showPurgeCacheDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
            SizedBox(width: 10),
            Text('Purge Local Cache?'),
          ],
        ),
        content: const Text(
          'This will clear local cache from your device and re-fetch clean records from the Cloud Firestore database. No online data will be lost.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _triggerFullSync();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Purge & Resync'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Live invoice preview computation
    final prefixText = _prefixCtrl.text.isEmpty ? 'INV-' : _prefixCtrl.text;
    final suffixText = _suffixCtrl.text;
    final counterStr = _settings.invoiceCounter.toString().padLeft(3, '0');
    final invoicePreview = '$prefixText$counterStr$suffixText';

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.lightBackground,
        appBar: AppBar(
          title: const Text('Profile & Settings'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              onPressed: _isFullSyncing ? null : _triggerFullSync,
              icon: _isFullSyncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              tooltip: 'Sync with Web App',
            ),
            const SizedBox(width: 8),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkSurfaceElevated
                    : AppColors.lightSurfaceElevated,
                borderRadius: BorderRadius.circular(14),
              ),
              child: TabBar(
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: CyberShadows.subtle(isDark),
                ),
                labelColor: Colors.white,
                unselectedLabelColor:
                    isDark ? Colors.white60 : AppColors.onSurfaceVariant,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                tabs: const [
                  Tab(text: 'Business'),
                  Tab(text: 'Invoicing'),
                  Tab(text: 'App & Sync'),
                ],
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            // ── User Identity Banner ─────────────────────────────────────────
            _buildUserIdentityCard(isDark),

            // ── Tab Views ────────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                children: [
                  _buildBusinessProfileTab(isDark),
                  _buildInvoicingTab(isDark, invoicePreview, counterStr),
                  _buildAppAndSyncTab(isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top User Identity Card ─────────────────────────────────────────────────
  Widget _buildUserIdentityCard(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
        boxShadow: CyberShadows.subtle(isDark),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            backgroundImage:
                _user?.photoURL != null ? NetworkImage(_user!.photoURL!) : null,
            child: _user?.photoURL == null
                ? Text(
                    (_user?.displayName?.isNotEmpty == true
                            ? _user!.displayName![0]
                            : 'S')
                        .toUpperCase(),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primaryLight,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _user?.displayName ?? 'Spark Store Manager',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppColors.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _userRole.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                          color: AppColors.primaryLight,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${_user?.email ?? 'store@wintechspark.com'}${_userPhoneNumber.isNotEmpty ? ' • $_userPhoneNumber' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Colors.greenAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Live Synced with Spark-PWA Web',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade400,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 1: Business Profile ────────────────────────────────────────────────
  Widget _buildBusinessProfileTab(bool isDark) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      child: Form(
        key: _businessFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(isDark, 'Store & Legal Entity',
                subtitle: 'Synced with companyProfiles in Cloud Firestore'),
            const SizedBox(height: 12),

            _cardContainer(
              isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fieldLabel(isDark, 'Business / Shop Name *'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _companyNameCtrl,
                    style: TextStyle(
                        color: isDark ? Colors.white : AppColors.onSurface),
                    decoration: _inputDeco(
                      isDark,
                      hint: 'e.g. WinTech Spark Pvt Ltd',
                      icon: Icons.store_rounded,
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Shop name is required'
                        : null,
                  ),
                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel(isDark, 'Proprietor / Owner'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _ownedByCtrl,
                              style: TextStyle(
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.onSurface),
                              decoration: _inputDeco(
                                isDark,
                                hint: 'e.g. Arul Jegan',
                                icon: Icons.person_outline_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel(isDark, 'GSTIN (GST Number)'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _gstCtrl,
                              textCapitalization: TextCapitalization.characters,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                color:
                                    isDark ? Colors.white : AppColors.onSurface,
                              ),
                              decoration: _inputDeco(
                                isDark,
                                hint: '33AAAAA0000A1Z5',
                                icon: Icons.receipt_long_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel(isDark, 'Contact Phone'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _contactCtrl,
                              keyboardType: TextInputType.phone,
                              style: TextStyle(
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.onSurface),
                              decoration: _inputDeco(
                                isDark,
                                hint: '+91 98765 43210',
                                icon: Icons.phone_outlined,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel(isDark, 'Business Email'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              style: TextStyle(
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.onSurface),
                              decoration: _inputDeco(
                                isDark,
                                hint: 'contact@spark.com',
                                icon: Icons.alternate_email_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  _fieldLabel(isDark, 'Store Address'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _addressCtrl,
                    maxLines: 2,
                    style: TextStyle(
                        color: isDark ? Colors.white : AppColors.onSurface),
                    decoration: _inputDeco(
                      isDark,
                      hint: 'Street address, City, Pincode',
                      icon: Icons.location_on_outlined,
                    ),
                  ),
                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel(isDark, 'State'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _stateCtrl,
                              style: TextStyle(
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.onSurface),
                              decoration: _inputDeco(
                                isDark,
                                hint: 'Tamil Nadu',
                                icon: Icons.map_outlined,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel(isDark, 'State Code'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _stateCodeCtrl,
                              keyboardType: TextInputType.number,
                              style: TextStyle(
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.onSurface),
                              decoration: _inputDeco(
                                isDark,
                                hint: '33',
                                icon: Icons.numbers_rounded,
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

            const SizedBox(height: 24),
            _sectionTitle(isDark, 'Bank & UPI Details',
                subtitle: 'Printed on Invoices and Receipt QR codes'),
            const SizedBox(height: 12),

            _cardContainer(
              isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel(isDark, 'Bank Name'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _bankNameCtrl,
                              style: TextStyle(
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.onSurface),
                              decoration: _inputDeco(
                                isDark,
                                hint: 'e.g. HDFC Bank',
                                icon: Icons.account_balance_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel(isDark, 'Account Number'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _bankAccountCtrl,
                              keyboardType: TextInputType.number,
                              style: TextStyle(
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.onSurface),
                              decoration: _inputDeco(
                                isDark,
                                hint: '502000000000',
                                icon: Icons.credit_card_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel(isDark, 'IFSC Code'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _bankIfscCtrl,
                              textCapitalization: TextCapitalization.characters,
                              style: TextStyle(
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.onSurface),
                              decoration: _inputDeco(
                                isDark,
                                hint: 'HDFC0001234',
                                icon: Icons.pin_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel(isDark, 'Branch Name'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _bankBranchCtrl,
                              style: TextStyle(
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.onSurface),
                              decoration: _inputDeco(
                                isDark,
                                hint: 'Main Branch',
                                icon: Icons.business_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  _fieldLabel(isDark, 'Merchant UPI ID (For Receipt QR)'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _upiIdCtrl,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppColors.onSurface,
                    ),
                    decoration: _inputDeco(
                      isDark,
                      hint: 'merchant@upi or phone@okhdfcbank',
                      icon: Icons.qr_code_2_rounded,
                    ),
                  ),
                  const SizedBox(height: 14),

                  _fieldLabel(isDark, 'Terms & Conditions'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _termsCtrl,
                    maxLines: 2,
                    style: TextStyle(
                        color: isDark ? Colors.white : AppColors.onSurface),
                    decoration: _inputDeco(
                      isDark,
                      hint: 'Printed at the bottom of customer receipts',
                      icon: Icons.gavel_rounded,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isSavingBusiness ? null : _saveBusinessProfile,
              icon: _isSavingBusiness
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.cloud_upload_rounded),
              label: Text(_isSavingBusiness
                  ? 'Syncing with Web App...'
                  : 'Save & Sync Business Profile'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab 2: Invoicing & Printer Settings ────────────────────────────────────
  Widget _buildInvoicingTab(
      bool isDark, String invoicePreview, String counterStr) {
    final connected = _printerService.connectedDevice;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      child: Form(
        key: _invoiceFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(isDark, 'Invoice Numbering Scheme',
                subtitle: 'Auto-synchronized with Web App sales counter'),
            const SizedBox(height: 12),

            _cardContainer(
              isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel(isDark, 'Prefix'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _prefixCtrl,
                              onChanged: (_) => setState(() {}),
                              style: TextStyle(
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.onSurface),
                              decoration: _inputDeco(
                                isDark,
                                hint: 'INV- or WIN/',
                                icon: Icons.text_fields_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.darkSurfaceElevated
                                : AppColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDark
                                  ? AppColors.darkBorder
                                  : AppColors.lightBorder,
                            ),
                          ),
                          child: Text(
                            counterStr,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace',
                              color: AppColors.primaryLight,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel(isDark, 'Suffix'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _suffixCtrl,
                              onChanged: (_) => setState(() {}),
                              style: TextStyle(
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.onSurface),
                              decoration: _inputDeco(
                                isDark,
                                hint: '/26',
                                icon: Icons.text_fields_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Live Preview Badge
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.confirmation_number_rounded,
                            color: AppColors.primaryLight, size: 22),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'NEXT INVOICE NUMBER PREVIEW',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: isDark
                                    ? Colors.white60
                                    : AppColors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              invoicePreview,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primaryLight,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            _sectionTitle(isDark, 'Default Format & Payment Mode',
                subtitle: 'Applies to quick checkout & thermal receipts'),
            const SizedBox(height: 12),

            _cardContainer(
              isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fieldLabel(isDark, 'Default Receipt Layout'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _choiceChip(
                          isDark,
                          label: '3" Thermal (80mm)',
                          selected: _defaultPrintMode == 'thermal-80',
                          onTap: () => setState(
                              () => _defaultPrintMode = 'thermal-80'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _choiceChip(
                          isDark,
                          label: '2" Thermal (58mm)',
                          selected: _defaultPrintMode == 'thermal-58',
                          onTap: () => setState(
                              () => _defaultPrintMode = 'thermal-58'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  _fieldLabel(isDark, 'Default Payment Mode'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _choiceChip(
                          isDark,
                          label: 'Cash',
                          icon: Icons.payments_rounded,
                          selected: _defaultPaymentMode == 'Cash',
                          onTap: () =>
                              setState(() => _defaultPaymentMode = 'Cash'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _choiceChip(
                          isDark,
                          label: 'UPI / QR',
                          icon: Icons.qr_code_rounded,
                          selected: _defaultPaymentMode == 'UPI',
                          onTap: () =>
                              setState(() => _defaultPaymentMode = 'UPI'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            _sectionTitle(isDark, 'Bluetooth Thermal Printer',
                subtitle: 'Pair & test ESC/POS thermal receipt printers'),
            const SizedBox(height: 12),

            _cardContainer(
              isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: connected != null
                              ? Colors.green.withValues(alpha: 0.15)
                              : Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.print_rounded,
                          color: connected != null
                              ? Colors.greenAccent
                              : Colors.amber,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              connected != null
                                  ? (connected.name.isNotEmpty
                                      ? connected.name
                                      : 'Connected Printer')
                                  : 'No Printer Paired',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: isDark
                                    ? Colors.white
                                    : AppColors.onSurface,
                              ),
                            ),
                            Text(
                              connected != null
                                  ? '${connected.address} · Ready to print'
                                  : 'Tap below to scan & connect via Bluetooth',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white60
                                    : AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: connected != null
                              ? Colors.green.withValues(alpha: 0.15)
                              : Colors.grey.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          connected != null ? 'Online' : 'Offline',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: connected != null
                                ? Colors.green
                                : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openBluetoothScanner,
                          icon: const Icon(Icons.bluetooth_searching_rounded,
                              size: 18),
                          label: Text(
                              connected != null ? 'Change' : 'Scan & Pair'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primaryLight,
                            side: const BorderSide(color: AppColors.primary),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isTestingPrinter ? null : _handleTestPrint,
                          icon: _isTestingPrinter
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.receipt_rounded, size: 18),
                          label: const Text('Test Print'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isSavingInvoice ? null : _saveInvoiceSettings,
              icon: _isSavingInvoice
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(_isSavingInvoice
                  ? 'Saving Settings...'
                  : 'Save Invoice & Print Settings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab 3: App & Cloud Sync ────────────────────────────────────────────────
  Widget _buildAppAndSyncTab(bool isDark) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Theme Switcher Tile
          _sectionTitle(isDark, 'Appearance',
              subtitle: 'Violet Cybernet High-Contrast Design System'),
          const SizedBox(height: 12),

          ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemeService.themeModeNotifier,
            builder: (context, mode, _) {
              final activeDark = mode == ThemeMode.dark;
              return _cardContainer(
                isDark,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary
                            .withValues(alpha: activeDark ? 0.25 : 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        activeDark
                            ? Icons.nightlight_round
                            : Icons.wb_sunny_rounded,
                        color: activeDark
                            ? AppColors.primaryLight
                            : AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activeDark
                                ? 'Violet Cybernet (Dark Mode)'
                                : 'Frost Cybernet (Light Mode)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isDark ? Colors.white : AppColors.onSurface,
                            ),
                          ),
                          Text(
                            activeDark
                                ? 'Obsidian card abyss & neon violet glow'
                                : 'Crisp frost white surfaces & vibrant violet',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white60
                                  : AppColors.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: activeDark,
                      activeThumbColor: AppColors.primaryLight,
                      activeTrackColor:
                          AppColors.primary.withValues(alpha: 0.4),
                      onChanged: (_) => ThemeService.toggleTheme(),
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 24),
          _sectionTitle(isDark, 'Inventory & Alert Rules',
              subtitle: 'Synced with Firestore /settings/app in Spark-PWA'),
          const SizedBox(height: 12),

          _cardContainer(
            isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fieldLabel(isDark, 'Low Stock Alert Threshold'),
                          Text(
                            'Highlight items with stock quantity ≤ $_lowStockThreshold',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white60
                                  : AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkSurfaceElevated
                            : AppColors.lightSurfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? AppColors.darkBorder
                              : AppColors.lightBorder,
                        ),
                      ),
                      child: Text(
                        '$_lowStockThreshold Units',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.primaryLight,
                        ),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _lowStockThreshold.toDouble(),
                  min: 1,
                  max: 30,
                  divisions: 29,
                  activeColor: AppColors.primary,
                  inactiveColor: isDark ? Colors.white24 : Colors.grey.shade300,
                  onChanged: (val) =>
                      setState(() => _lowStockThreshold = val.round()),
                ),
                const Divider(),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _lowStockAlerts,
                  activeThumbColor: AppColors.primaryLight,
                  activeTrackColor:
                      AppColors.primary.withValues(alpha: 0.4),
                  title: Text(
                    'Low Stock Notifications',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isDark ? Colors.white : AppColors.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'Trigger alerts on dashboard when products run low',
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          isDark ? Colors.white60 : AppColors.onSurfaceVariant,
                    ),
                  ),
                  onChanged: (val) => setState(() => _lowStockAlerts = val),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _overdueInvoiceAlerts,
                  activeThumbColor: AppColors.primaryLight,
                  activeTrackColor:
                      AppColors.primary.withValues(alpha: 0.4),
                  title: Text(
                    'Overdue Invoice Reminders',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isDark ? Colors.white : AppColors.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'Show pending and unpaid customer bills on dashboard',
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          isDark ? Colors.white60 : AppColors.onSurfaceVariant,
                    ),
                  ),
                  onChanged: (val) =>
                      setState(() => _overdueInvoiceAlerts = val),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _isSavingAppSettings ? null : _saveAppPreferences,
                  icon: _isSavingAppSettings
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Save Alert Preferences'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          _sectionTitle(isDark, 'Cloud Sync & Local Cache',
              subtitle: 'Bi-directional synchronization status with Web App'),
          const SizedBox(height: 12),

          _cardContainer(
            isDark,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _statItem(
                        isDark,
                        label: 'Products',
                        count: '$_localProductCount',
                        icon: Icons.inventory_2_rounded,
                      ),
                    ),
                    Expanded(
                      child: _statItem(
                        isDark,
                        label: 'Invoices',
                        count: '$_localSaleCount',
                        icon: Icons.receipt_long_rounded,
                      ),
                    ),
                    Expanded(
                      child: _statItem(
                        isDark,
                        label: 'Expenses',
                        count: '$_localExpenseCount',
                        icon: Icons.account_balance_wallet_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Last Full Sync:',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            isDark ? Colors.white60 : AppColors.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _lastSyncTimestamp != null
                          ? DateFormat('hh:mm a, dd MMM').format(_lastSyncTimestamp!)
                          : 'Just Now',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppColors.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                ElevatedButton.icon(
                  onPressed: _isFullSyncing ? null : _triggerFullSync,
                  icon: _isFullSyncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.sync_rounded),
                  label: Text(_isFullSyncing
                      ? 'Syncing with Spark Web...'
                      : 'Force Full Sync with Web App'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),
          _sectionTitle(isDark, 'Data Management & Account', danger: true),
          const SizedBox(height: 12),

          _cardContainer(
            isDark,
            borderColor: Colors.redAccent.withValues(alpha: 0.3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OutlinedButton.icon(
                  onPressed: _showPurgeCacheDialog,
                  icon: const Icon(Icons.delete_sweep_rounded,
                      size: 18, color: Colors.redAccent),
                  label: const Text('PURGE LOCAL STORAGE & RE-DOWNLOAD'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: Colors.redAccent,
                    side: BorderSide(
                        color: Colors.redAccent.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor:
                            isDark ? AppColors.darkSurface : Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)),
                        title: const Row(
                          children: [
                            Icon(Icons.logout_rounded,
                                color: Colors.redAccent, size: 22),
                            SizedBox(width: 10),
                            Text('Sign Out'),
                          ],
                        ),
                        content: const Text(
                          'Are you sure you want to sign out of Spark+?',
                          style: TextStyle(fontSize: 14),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Sign Out'),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true && mounted) {
                      await _authService.signOut();
                      MainLayout.currentTab = 0;
                      if (!mounted) return;
                      Navigator.of(context, rootNavigator: true)
                          .pushAndRemoveUntil(
                        MaterialPageRoute(
                            builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                    }
                  },
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('SIGN OUT OF SPARK+'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor:
                        isDark ? Colors.white70 : AppColors.onSurfaceVariant,
                    side: BorderSide(
                        color: isDark ? Colors.white24 : Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          Center(
            child: Text(
              'WinTech Spark+ Mobile & Web PWA · v1.2.0\nCloud Synced with Firebase Studio',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white30 : Colors.grey.shade400,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── UI Helper Builders ─────────────────────────────────────────────────────

  Widget _sectionTitle(bool isDark, String title,
      {String? subtitle, bool danger = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
            color: danger
                ? Colors.redAccent
                : (isDark ? AppColors.primaryLight : AppColors.primary),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _fieldLabel(bool isDark, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: isDark ? Colors.white70 : AppColors.onSurface,
      ),
    );
  }

  Widget _cardContainer(bool isDark,
      {required Widget child, Color? borderColor}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor ??
              (isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
        boxShadow: CyberShadows.subtle(isDark),
      ),
      child: child,
    );
  }

  Widget _choiceChip(
    bool isDark, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.15)
              : (isDark
                  ? AppColors.darkSurfaceElevated
                  : AppColors.lightSurfaceElevated),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: selected
                    ? AppColors.primaryLight
                    : (isDark ? Colors.white60 : AppColors.onSurfaceVariant),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                  color: selected
                      ? (isDark ? Colors.white : AppColors.primary)
                      : (isDark ? Colors.white70 : AppColors.onSurface),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(bool isDark,
      {required String label, required String count, required IconData icon}) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primaryLight, size: 20),
        const SizedBox(height: 6),
        Text(
          count,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.white54 : AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDeco(bool isDark,
      {required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: isDark ? Colors.white30 : Colors.grey.shade400,
        fontSize: 13,
      ),
      prefixIcon: Icon(
        icon,
        size: 18,
        color: isDark ? AppColors.primaryLight : AppColors.primary,
      ),
      filled: true,
      fillColor: isDark
          ? AppColors.darkSurfaceElevated
          : AppColors.lightSurfaceElevated,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 0.8,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }
}
