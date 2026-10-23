import 'package:flutter/material.dart';
import 'package:main/components/cargo_components.dart';
import 'package:main/pages/drop_off_location_page.dart';
import 'package:main/services/cargo_order_service.dart';
import 'package:main/theme/app_theme.dart';

class CargoCategoryPage extends StatefulWidget {
  const CargoCategoryPage({super.key, required this.draft});

  final CargoOrderDraft draft;

  @override
  State<CargoCategoryPage> createState() => _CargoCategoryPageState();
}

class _CargoCategoryPageState extends State<CargoCategoryPage> {
  static const _categories = [
    ('Furniture', 'Sofas, beds, tables', Icons.chair_outlined),
    ('Appliances', 'Fridges, washers, TVs', Icons.kitchen_outlined),
    ('Boxes & parcels', 'Household or business', Icons.inventory_2_outlined),
    ('Building materials', 'Tools and supplies', Icons.handyman_outlined),
    ('Office equipment', 'Desks, chairs, electronics', Icons.business_outlined),
    ('Other cargo', 'Tell us what you need to move', Icons.widgets_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return CargoPageScaffold(
      title: 'What are you moving?',
      step: 1,
      buttonText: 'Continue',
      buttonEnabled: widget.draft.category.isNotEmpty,
      onContinue: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DropOffLocationPage(draft: widget.draft),
        ),
      ),
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
          for (final category in _categories) ...[
            CargoOptionCard(
              title: category.$1,
              subtitle: category.$2,
              icon: category.$3,
              selected: widget.draft.category == category.$1,
              onTap: () => setState(() => widget.draft.category = category.$1),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
