import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/theme.dart';
import '../core/models/models.dart';
import '../services/hive_service.dart';

class CompactBarcodeScannerDialog extends StatefulWidget {
  final bool continuousMode;
  final List<SaleItem>? currentCartItems;
  final void Function(Product product)? onProductScanned;

  const CompactBarcodeScannerDialog({
    super.key,
    this.continuousMode = false,
    this.currentCartItems,
    this.onProductScanned,
  });

  static Future<String?> show(
    BuildContext context, {
    bool continuousMode = false,
    List<SaleItem>? currentCartItems,
    void Function(Product product)? onProductScanned,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => CompactBarcodeScannerDialog(
        continuousMode: continuousMode,
        currentCartItems: currentCartItems,
        onProductScanned: onProductScanned,
      ),
    );
  }

  @override
  State<CompactBarcodeScannerDialog> createState() =>
      _CompactBarcodeScannerDialogState();
}

class _CompactBarcodeScannerDialogState
    extends State<CompactBarcodeScannerDialog>
    with SingleTickerProviderStateMixin {
  late final MobileScannerController _controller;
  late final AnimationController _animController;
  late final Animation<double> _laserAnim;

  final NumberFormat _fmt = NumberFormat('#,##,##0.00', 'en_IN');

  bool _isTorchOn = false;
  DateTime? _lastScanTime;
  String? _lastScannedBarcode;

  String? _feedbackMessage;
  bool _feedbackSuccess = true;
  int _scannedSessionCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _laserAnim = Tween<double>(begin: 0.08, end: 0.92).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture capture) {
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final code = barcodes.first.rawValue?.trim();
    if (code == null || code.isEmpty) return;

    final now = DateTime.now();
    // Debounce duplicate barcode scan within 1.3 seconds
    if (_lastScannedBarcode == code &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!).inMilliseconds < 1300) {
      return;
    }

    _lastScanTime = now;
    _lastScannedBarcode = code;

    if (!widget.continuousMode) {
      // ── Single Scan Mode (Add Product / Single Form Field) ──
      HapticFeedback.mediumImpact();
      Navigator.pop(context, code);
      return;
    }

    // ── Continuous POS Mode (Billing) ──
    final product = HiveService.getProductByBarcode(code);

    if (product != null) {
      HapticFeedback.mediumImpact();
      widget.onProductScanned?.call(product);
      setState(() {
        _scannedSessionCount++;
        _feedbackSuccess = true;
        _feedbackMessage =
            'Added "${product.productName}" • ₹${_fmt.format(product.sellingPrice)}';
      });
    } else {
      HapticFeedback.vibrate();
      setState(() {
        _feedbackSuccess = false;
        _feedbackMessage = 'Barcode "$code" not found in inventory';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const double apertureWidth = 260.0; // ~2 inches logical
    const double apertureHeight = 130.0; // ~1 inch logical

    final cartCount =
        (widget.currentCartItems?.length ?? 0) + _scannedSessionCount;

    return Dialog(
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: isDark ? AppColors.darkBorder : AppColors.outlineVariant,
          width: 1.5,
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Top Header Bar ───────────────────────────────────────────
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
                      Icons.qr_code_scanner_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Barcode Scanner',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? AppColors.darkText100
                                : AppColors.lightText100,
                          ),
                        ),
                        Text(
                          widget.continuousMode
                              ? 'Continuous Auto-Cart Mode'
                              : 'Point camera at barcode',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? AppColors.darkText50
                                : AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Flashlight Toggle Icon Button
                  IconButton(
                    onPressed: () async {
                      await _controller.toggleTorch();
                      setState(() => _isTorchOn = !_isTorchOn);
                    },
                    icon: Icon(
                      _isTorchOn
                          ? Icons.flash_on_rounded
                          : Icons.flash_off_rounded,
                      color: _isTorchOn
                          ? const Color(0xFFFBBF24)
                          : (isDark ? Colors.white70 : Colors.grey.shade700),
                    ),
                    tooltip: _isTorchOn ? 'Turn Flash Off' : 'Turn Flash On',
                    style: IconButton.styleFrom(
                      backgroundColor: _isTorchOn
                          ? const Color(0xFFFBBF24).withValues(alpha: 0.2)
                          : (isDark ? Colors.white10 : Colors.grey.shade100),
                    ),
                  ),

                  // Close Dialog Button
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close_rounded,
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                    ),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Middle 2x1 Inch Camera Aperture ──────────────────────────
              Container(
                width: apertureWidth,
                height: apertureHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary
                          .withValues(alpha: isDark ? 0.35 : 0.15),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Camera Preview Feed
                      MobileScanner(
                        controller: _controller,
                        fit: BoxFit.cover,
                        onDetect: _handleBarcode,
                        errorBuilder: (context, error, child) {
                          return Container(
                            color: Colors.black,
                            padding: const EdgeInsets.all(12),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.videocam_off_rounded,
                                      color: Colors.white54, size: 28),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Camera Unavailable',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ElevatedButton(
                                    onPressed: () => _controller.start(),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 4),
                                      minimumSize: const Size(60, 28),
                                    ),
                                    child: const Text('Retry',
                                        style: TextStyle(fontSize: 11)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),

                      // Corner Accents (4 corners)
                      Align(
                        alignment: Alignment.topLeft,
                        child: _cornerBorder(top: true, left: true),
                      ),
                      Align(
                        alignment: Alignment.topRight,
                        child: _cornerBorder(top: true, left: false),
                      ),
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: _cornerBorder(top: false, left: true),
                      ),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: _cornerBorder(top: false, left: false),
                      ),

                      // Animated Laser Beam
                      AnimatedBuilder(
                        animation: _laserAnim,
                        builder: (context, _) {
                          return Positioned(
                            top: apertureHeight * _laserAnim.value,
                            left: 8,
                            right: 8,
                            child: Container(
                              height: 2.5,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    AppColors.primaryLight,
                                    Color(0xFF38BDF8),
                                    AppColors.primaryLight,
                                    Colors.transparent,
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primaryLight
                                        .withValues(alpha: 0.9),
                                    blurRadius: 8,
                                    spreadRadius: 1.5,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Feedback Banner or Instruction ───────────────────────────
              if (_feedbackMessage != null)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _feedbackSuccess
                        ? (isDark
                            ? const Color(0xFF064E3B)
                            : const Color(0xFFE8F5E9))
                        : (isDark
                            ? const Color(0xFF78350F)
                            : const Color(0xFFFFF3E0)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _feedbackSuccess
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF59E0B),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _feedbackSuccess
                            ? Icons.check_circle_rounded
                            : Icons.warning_amber_rounded,
                        color: _feedbackSuccess
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _feedbackMessage!,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: _feedbackSuccess
                                ? (isDark
                                    ? Colors.greenAccent
                                    : Colors.green.shade800)
                                : (isDark
                                    ? Colors.orangeAccent
                                    : Colors.orange.shade900),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Text(
                  'Center barcode inside the 2×1" aperture',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark
                        ? AppColors.darkText50
                        : Colors.grey.shade600,
                  ),
                ),

              // ── Continuous Mode Bottom Cart Status & Done Action ─────────
              if (widget.continuousMode) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$cartCount items in cart',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppColors.darkText100
                                  : AppColors.lightText100,
                            ),
                          ),
                          if (_scannedSessionCount > 0)
                            Text(
                              '+$_scannedSessionCount scanned this session',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF10B981),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.done_all_rounded, size: 16),
                      label: const Text('Done Scanning'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _cornerBorder({required bool top, required bool left}) {
    const double len = 16.0;
    const double thk = 3.0;
    const color = AppColors.primaryLight;

    return Container(
      width: len,
      height: len,
      decoration: BoxDecoration(
        border: Border(
          top: top
              ? const BorderSide(color: color, width: thk)
              : BorderSide.none,
          bottom: !top
              ? const BorderSide(color: color, width: thk)
              : BorderSide.none,
          left: left
              ? const BorderSide(color: color, width: thk)
              : BorderSide.none,
          right: !left
              ? const BorderSide(color: color, width: thk)
              : BorderSide.none,
        ),
        borderRadius: BorderRadius.only(
          topLeft: top && left ? const Radius.circular(8) : Radius.zero,
          topRight: top && !left ? const Radius.circular(8) : Radius.zero,
          bottomLeft: !top && left ? const Radius.circular(8) : Radius.zero,
          bottomRight: !top && !left ? const Radius.circular(8) : Radius.zero,
        ),
      ),
    );
  }
}
