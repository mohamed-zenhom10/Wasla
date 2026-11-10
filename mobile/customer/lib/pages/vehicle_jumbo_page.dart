import 'package:flutter/material.dart';
import 'package:main/pages/vehicle_small_page.dart';
import 'package:main/services/cargo_order_service.dart';

class VehiclesJumboPage extends StatelessWidget {
  const VehiclesJumboPage({super.key, required this.draft});

  final CargoOrderDraft draft;

  @override
  Widget build(BuildContext context) => VehiclesSmallPage(draft: draft);
}
