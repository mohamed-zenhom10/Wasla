import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:main/components/app_page_header.dart';
import 'package:main/components/customer_tracking_map.dart';
import 'package:main/components/main_button.dart';
import 'package:main/models/shipment.dart';
import 'package:main/pages/cargo_category_page.dart';
import 'package:main/pages/location_picker_page.dart';
import 'package:main/pages/messages_page.dart';
import 'package:main/pages/profile_page.dart';
import 'package:main/pages/your_activity_page.dart';
import 'package:main/pages/wallet_page.dart';
import 'package:main/models/wallet.dart';
import 'package:main/services/auth_service.dart';
import 'package:main/services/cargo_order_service.dart';
import 'package:main/services/shipment_service.dart';
import 'package:main/services/wallet_service.dart';
import 'package:main/theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.isPreview = false, this.initialTab = 0});

  final bool isPreview;
  final int initialTab;

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final _pickupController = TextEditingController();
  final _destinationController = TextEditingController();
  final ShipmentService _service = ShipmentService();
  final WalletService _walletService = WalletService();
  ShipmentCatalog? _catalog;
  Wallet? _wallet;
  int _selectedTab = 0;
  String? _customerName;
  LatLng? _pickupPoint;
  LatLng? _destinationPoint;
  CargoOrderDraft? _activeBookingDraft;
  final Set<String> _submittedShipmentIds = <String>{};

  void clearActiveBookingDraft() {
    _activeBookingDraft = null;
  }

  void resetLocationSelection() {
    _pickupController.clear();
    _destinationController.clear();
    _pickupPoint = null;
    _destinationPoint = null;
    if (mounted) setState(() {});
  }

  void markShipmentSubmitted(String shipmentId) {
    _submittedShipmentIds.add(shipmentId);
    if (_activeBookingDraft?.shipment?.id == shipmentId) {
      _activeBookingDraft = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab.clamp(0, _tabNames.length - 1);
    if (!widget.isPreview) _loadCustomerName();
    _loadCatalog();
    _loadWallet();
  }

  Future<void> _loadCustomerName() async {
    final session = await AuthService.loadSession();
    if (!mounted) return;
    setState(() => _customerName = session?.fullName);
  }

  Future<void> _loadCatalog() async {
    try {
      final catalog = await _service.getCatalog();
      if (mounted) setState(() => _catalog = catalog);
    } catch (error) {
      if (mounted) setState(() => _catalog = null);
    }
  }

  Future<void> _loadWallet() async {
    try {
      final wallet = await _walletService.getWallet();
      if (mounted) setState(() => _wallet = wallet);
    } catch (error) {
      if (mounted) setState(() => _wallet = null);
    }
  }

  void setTab(int index) {
    final safeIndex = index.clamp(0, _tabNames.length - 1);
    if (mounted && _selectedTab != safeIndex) {
      setState(() => _selectedTab = safeIndex);
    }
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _pickLocation({required bool isPickup}) async {
    final result = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          title: isPickup ? 'Pickup location' : 'Drop-off location',
          initialPoint: isPickup ? _pickupPoint : _destinationPoint,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (isPickup) {
        _pickupController.text = result.address;
        _pickupPoint = result.point;
      } else {
        _destinationController.text = result.address;
        _destinationPoint = result.point;
      }
    });
  }

  void _requestMove() {
    _startOrder();
  }

  void _startOrder({bool useAiEstimate = false}) {
    final draft = CargoOrderDraft()
      ..pickup = _pickupController.text.trim()
      ..destination = _destinationController.text.trim()
      ..pickupLatitude = _pickupPoint?.latitude
      ..pickupLongitude = _pickupPoint?.longitude
      ..dropoffLatitude = _destinationPoint?.latitude
      ..dropoffLongitude = _destinationPoint?.longitude
      ..useAiEstimate = useAiEstimate
      ..catalog = _catalog
      ..paymentMethod = _wallet?.defaultPaymentMethod ?? 'cash';
    if (draft.paymentMethod == 'wallet') {
      final balance = double.tryParse(_wallet?.balance ?? '0') ?? 0;
      if (balance < 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Top up your wallet before requesting a shipment.')),
          );
        }
        return;
      }
    }
    setState(() => _activeBookingDraft = draft);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CargoCategoryPage(draft: draft)),
    );
  }

  void _resumeOrder() {
    final draft = _activeBookingDraft;
    if (draft == null) return;
    if (draft.shipment != null &&
        _submittedShipmentIds.contains(draft.shipment!.id)) {
      _activeBookingDraft = null;
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CargoCategoryPage(draft: draft)),
    );
  }

  void _handleTripsTap() {
    setTab(1);
  }

  void _goToHome() {
    setTab(0);
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const AppLogo(size: 40),
                  Text(
                    'CAIRO, EGYPT',
                    style: TextStyle(color: AppColors.darkGreen, fontSize: 10),
                  ),
                ],
              ),
              if (widget.isPreview) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.light,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Preview only - not signed in',
                    style: TextStyle(color: AppColors.darkGreen, fontSize: 11),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                _customerName == null ? 'Welcome' : 'Morning, $_customerName',
                style: AppTypography.headingSm.copyWith(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 16),
              CustomerMapPreview(
                pickup: _pickupPoint,
                destination: _destinationPoint,
                height: 250,
              ),
              const SizedBox(height: 20),
              const Text(
                'Where are you moving\nsomething?',
                style: TextStyle(
                  color: AppColors.darkGreen,
                  fontSize: 20,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.light,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _LocationInput(
                      controller: _pickupController,
                      icon: Icons.radio_button_checked,
                      hint: 'Pickup location',
                      onTap: () => _pickLocation(isPickup: true),
                    ),
                    const Divider(height: 1),
                    _LocationInput(
                      controller: _destinationController,
                      icon: Icons.location_on_outlined,
                      hint: 'Where to?',
                      onTap: () => _pickLocation(isPickup: false),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              MainButton(
                text: 'Move something',
                onPressed: _requestMove,
                borderRadius: 8,
              ),
              if (_activeBookingDraft != null) ...[
                const SizedBox(height: 8),
                MainButton(
                  text: 'Resume move',
                  onPressed: _resumeOrder,
                  variant: WaslaButtonVariant.secondary,
                  borderRadius: 8,
                ),
              ],
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.light,
                  border: Border.all(color: AppColors.accent, width: 1.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.auto_awesome, size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Not sure which truck you need?',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Let Wasla choose it for you.',
                      style: TextStyle(fontSize: 12),
                    ),
                    TextButton.icon(
                      onPressed: () => _startOrder(useAiEstimate: true),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.darkGreen,
                        padding: const EdgeInsets.only(top: 8),
                      ),
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: const Text(
                        'Estimate my cargo',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      YourActivityPage(isPreview: widget.isPreview, onDone: () => setTab(0)),
      const MessagesPage(),
      const WalletPage(),
      ProfilePage(isActive: _selectedTab == 4, onNavigateToTab: setTab),
    ];

    return Scaffold(
      backgroundColor: AppColors.white,
      body: IndexedStack(index: _selectedTab, children: pages),
      bottomNavigationBar: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: _selectedTab,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppColors.accent,
          unselectedItemColor: AppColors.darkGreen,
          selectedFontSize: 10,
          unselectedFontSize: 10,
          onTap: (index) {
            if (index == 1) {
              _handleTripsTap();
              return;
            }
            if (index == 0) {
              _goToHome();
              return;
            }
            setTab(index);
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.alt_route),
              label: 'Trips',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              label: 'Messages',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_outlined),
              label: 'Wallet',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

const _tabNames = ['Home', 'Trips', 'Messages', 'Wallet', 'Profile'];

class _LocationInput extends StatelessWidget {
  const _LocationInput({
    required this.controller,
    required this.icon,
    required this.hint,
    required this.onTap,
  });

  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.darkGreen, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: controller,
            readOnly: true,
            onTap: onTap,
            style: const TextStyle(color: AppColors.darkGreen, fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
              hintStyle: const TextStyle(color: AppColors.darkGreen),
            ),
          ),
        ),
        const Icon(Icons.chevron_right, size: 18, color: AppColors.darkGreen),
      ],
    );
  }
}
