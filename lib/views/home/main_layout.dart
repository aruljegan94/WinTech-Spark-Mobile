import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/theme.dart';
import '../../core/models/models.dart';
import '../../services/hive_service.dart';
import '../../services/sync_service.dart';
import '../../services/theme_service.dart';
import '../alerts/alerts_screen.dart';
import 'dashboard_screen.dart';
import '../billing/billing_screen.dart';
import '../inventory/inventory_screen.dart';
import '../expenses/expenses_screen.dart';
import '../profile/profile_screen.dart';

class MainLayout extends StatefulWidget {
  final int initialIndex;
  static int currentTab = 0;

  const MainLayout({super.key, this.initialIndex = 0});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout>
    with SingleTickerProviderStateMixin {
  late AnimationController _titleAnimController;
  late Animation<double> _titleFade;
  late Animation<Offset> _titleSlide;

  @override
  void initState() {
    super.initState();
    if (widget.initialIndex != 0) {
      MainLayout.currentTab = widget.initialIndex;
    }
    // Initialize continuous bidirectional sync with Web App Firestore
    SyncService.initLiveSync();
    _titleAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _titleFade = CurvedAnimation(
      parent: _titleAnimController,
      curve: Curves.easeOut,
    );
    _titleSlide = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _titleAnimController,
      curve: Curves.easeOutCubic,
    ));
    _titleAnimController.forward();
  }

  @override
  void dispose() {
    SyncService.disposeLiveSync();
    _titleAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        leadingWidth: 54,
        leading: Padding(
          padding: const EdgeInsets.only(left: 14, top: 10, bottom: 10),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.tertiary],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(1.5),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8.5),
              child: Image.asset(
                'lib/assets/AppLogo.jpeg',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Image.asset(
                  'lib/assets/icon.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ),
        titleSpacing: 0,
        title: SlideTransition(
          position: _titleSlide,
          child: FadeTransition(
            opacity: _titleFade,
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'Spark',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : AppColors.primary,
                          letterSpacing: -0.5,
                        ),
                  ),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: _AnimatedPlusTag(),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          ValueListenableBuilder<Box<Product>>(
            valueListenable:
                Hive.box<Product>(HiveService.productBoxName).listenable(),
            builder: (context, box, _) {
              final lowStockCount =
                  box.values.where((p) => p.stockQuantity <= 10).length;
              final isDark = Theme.of(context).brightness == Brightness.dark;

              return IconButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AlertsScreen()),
                ),
                icon: Badge(
                  isLabelVisible: lowStockCount > 0,
                  label: Text('$lowStockCount'),
                  backgroundColor: Colors.redAccent,
                  child: Icon(
                    Icons.notifications_none_rounded,
                    color: isDark ? Colors.white70 : AppColors.primary,
                  ),
                ),
              );
            },
          ),
          // Theme Switcher Button (Cybernet Dark/Light)
          ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemeService.themeModeNotifier,
            builder: (context, mode, _) {
              final isDark = mode == ThemeMode.dark;
              return IconButton(
                tooltip:
                    isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme',
                onPressed: () => ThemeService.toggleTheme(),
                icon: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E163B)
                        : AppColors.primary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark
                          ? AppColors.primaryLight.withValues(alpha: 0.40)
                          : AppColors.primary.withValues(alpha: 0.20),
                    ),
                    boxShadow: isDark
                        ? [
                            BoxShadow(
                              color:
                                  AppColors.primaryGlow.withValues(alpha: 0.35),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    color: isDark ? const Color(0xFFFFD54F) : AppColors.primary,
                    size: 18,
                  ),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 14.0, left: 4.0),
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              ),
              child: CircleAvatar(
                radius: 17,
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.primaryLight.withValues(alpha: 0.20)
                    : AppColors.primary.withValues(alpha: 0.12),
                child: Icon(
                  Icons.person_rounded,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.primaryLight
                      : AppColors.primary,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: MainLayout.currentTab,
        children: [
          DashboardScreen(
            onNavigate: (index) => setState(() => MainLayout.currentTab = index),
          ),
          const BillingScreen(),
          const InventoryScreen(),
          const ExpensesScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        height: 80,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF120E24).withValues(alpha: 0.90)
                    : Colors.white.withValues(alpha: 0.90),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.primary.withValues(alpha: 0.30)
                    : Colors.white.withValues(alpha: 0.60),
                ),
                boxShadow: CyberShadows.shadow70(
                  Theme.of(context).brightness == Brightness.dark,
                ),
              ),
              child: BottomNavigationBar(
                currentIndex: MainLayout.currentTab,
                onTap: (index) => setState(() => MainLayout.currentTab = index),
                backgroundColor: Colors.transparent,
                elevation: 0,
                type: BottomNavigationBarType.fixed,
                selectedItemColor:
                    Theme.of(context).brightness == Brightness.dark
                        ? AppColors.primaryLight
                        : AppColors.primary,
                unselectedItemColor:
                    Theme.of(context).brightness == Brightness.dark
                        ? AppColors.darkText50
                        : AppColors.lightText50,
                selectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 10),
                unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w500, fontSize: 10),
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.dashboard_outlined),
                    activeIcon: Icon(Icons.dashboard_rounded),
                    label: 'Dashboard',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.receipt_long_outlined),
                    activeIcon: Icon(Icons.receipt_long_rounded),
                    label: 'Billing',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.inventory_2_outlined),
                    activeIcon: Icon(Icons.inventory_2_rounded),
                    label: 'Inventory',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.payments_outlined),
                    activeIcon: Icon(Icons.payments_rounded),
                    label: 'Expenses',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                color: AppColors.primary,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(Icons.bolt_rounded, size: 48, color: Colors.white),
                  const SizedBox(height: 12),
                  Text(
                    'Spark+',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text('Profile'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Animated glowing "+" badge next to "Spark"
class _AnimatedPlusTag extends StatefulWidget {
  @override
  State<_AnimatedPlusTag> createState() => _AnimatedPlusTagState();
}

class _AnimatedPlusTagState extends State<_AnimatedPlusTag>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (context, child) => Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              AppColors.primary,
              AppColors.primaryGlow,
            ],
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryGlow
                  .withValues(alpha: _glowAnim.value * 0.65),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: const Text(
          '+',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 13,
            height: 1,
          ),
        ),
      ),
    );
  }
}
