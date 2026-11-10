import 'package:flutter/material.dart';
import 'package:main/components/cargo_components.dart';
import 'package:main/models/shipment.dart';
import 'package:main/pages/drop_off_location_page.dart';
import 'package:main/services/cargo_order_service.dart';
import 'package:main/services/shipment_service.dart';
import 'package:main/theme/app_theme.dart';

class CargoCategoryPage extends StatefulWidget {
  const CargoCategoryPage({super.key, required this.draft});

  final CargoOrderDraft draft;

  @override
  State<CargoCategoryPage> createState() => _CargoCategoryPageState();
}

class _CargoCategoryPageState extends State<CargoCategoryPage> {
  final _service = ShipmentService();
  late Future<ShipmentCatalog> _catalog;

  @override
  void initState() {
    super.initState();
    _catalog = _loadCatalog();
  }

  Future<ShipmentCatalog> _loadCatalog() async {
    final catalog = await _service.getCatalog();
    widget.draft.catalog = catalog;
    return catalog;
  }

  void _continue() {
    if (widget.draft.categoryId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DropOffLocationPage(draft: widget.draft),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ShipmentCatalog>(
      future: _catalog,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return CargoPageScaffold(
            title: 'What are you moving?',
            step: 1,
            buttonText: 'Retry catalog',
            onContinue: () => setState(() => _catalog = _loadCatalog()),
            child: Text(
              'Cargo categories could not be loaded. ${snapshot.error is ShipmentApiException ? (snapshot.error as ShipmentApiException).message : 'Please try again.'}',
              style: const TextStyle(color: AppColors.darkGreen),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final categories = snapshot.data!.categories;
        if (categories.isEmpty) {
          return CargoPageScaffold(
            title: 'What are you moving?',
            step: 1,
            buttonText: 'Retry catalog',
            onContinue: () => setState(() => _catalog = _loadCatalog()),
            child: const Text(
              'No active cargo categories are available right now.',
              style: TextStyle(color: AppColors.darkGreen),
            ),
          );
        }
        return CargoPageScaffold(
          title: 'What are you moving?',
          step: 1,
          buttonText: 'Continue',
          buttonEnabled: widget.draft.categoryId != null,
          onContinue: _continue,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose the category that best describes your cargo.',
                style: TextStyle(
                  color: AppColors.darkGreen,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              for (final category in categories) ...[
                CargoOptionCard(
                  title: category.nameEn,
                  subtitle: category.sizes.isEmpty
                      ? 'Choose this category'
                      : '${category.sizes.length} size options',
                  icon: _iconForCategory(category),
                  selected: widget.draft.categoryId == category.id,
                  onTap: () => setState(() {
                    widget.draft
                      ..category = category.nameEn
                      ..categoryId = category.id
                      ..sizeOptionId = null;
                    widget.draft.fieldErrors.remove('cargoCategoryId');
                  }),
                ),
                const SizedBox(height: 10),
              ],
              if (widget.draft.fieldErrors['cargoCategoryId'] case final error?)
                Text(error, style: const TextStyle(color: AppColors.accent)),
            ],
          ),
        );
      },
    );
  }

  IconData _iconForCategory(ShipmentCargoCategory category) {
    return switch (category.code) {
      'furniture' => Icons.chair_outlined,
      'appliances' => Icons.kitchen_outlined,
      'boxes' || 'parcels' => Icons.inventory_2_outlined,
      'building_materials' => Icons.handyman_outlined,
      'office_equipment' => Icons.business_outlined,
      _ => Icons.widgets_outlined,
    };
  }
}
