import 'package:flutter/material.dart';
import 'package:main/components/cargo_components.dart';
import 'package:main/services/cargo_order_service.dart';
import 'package:main/theme/app_theme.dart';

class YourActivityPage extends StatelessWidget {
  const YourActivityPage({super.key, this.savedOrder});

  final CargoActivityItem? savedOrder;

  @override
  Widget build(BuildContext context) {
    final items = CargoOrderService.activity;
    return CargoPageScaffold(
      title: 'Your activity',
      step: 0,
      buttonText: 'Done',
      onContinue: () => Navigator.of(context).maybePop(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (savedOrder != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF4EC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline, color: AppColors.darkGreen),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Demo request saved on this device. No driver has been requested.',
                      style: TextStyle(
                        color: AppColors.darkGreen,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
          ],
          const CargoSectionLabel('Recent moves'),
          if (items.isEmpty)
            const _EmptyActivity()
          else
            for (final item in items) ...[
              _ActivityCard(item: item),
              const SizedBox(height: 12),
            ],
          const SizedBox(height: 8),
          const Text(
            'Activity shown here is sample data stored locally for this prototype.',
            style: TextStyle(
              color: AppColors.darkGreen,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.item});

  final CargoActivityItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E6E3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.light,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.local_shipping_outlined,
                  color: AppColors.darkGreen,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.title,
                  style: const TextStyle(
                    color: AppColors.darkGreen,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                item.dateLabel,
                style: const TextStyle(
                  color: AppColors.darkGreen,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            item.route,
            style: const TextStyle(color: AppColors.darkGreen, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF4EC),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  item.status,
                  style: const TextStyle(
                    color: AppColors.darkGreen,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                item.reference,
                style: const TextStyle(
                  color: AppColors.darkGreen,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        children: [
          Icon(Icons.route_outlined, size: 36, color: AppColors.darkGreen),
          SizedBox(height: 10),
          Text(
            'No moves yet',
            style: TextStyle(
              color: AppColors.darkGreen,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
