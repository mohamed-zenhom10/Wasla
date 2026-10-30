import 'package:flutter/material.dart';
import 'package:main/pages/ai_recommendation_page.dart';
import 'package:main/routing/app_route.dart';
import 'package:main/theme/app_theme.dart';

class AiEstimatingPage extends StatefulWidget {
  const AiEstimatingPage({super.key});

  @override
  State<AiEstimatingPage> createState() => _AiEstimatingPageState();
}

class _AiEstimatingPageState extends State<AiEstimatingPage> {
  int _completed = 2;

  @override
  void initState() {
    super.initState();
    _runEstimation();
  }

  Future<void> _runEstimation() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _completed = 3);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      TAMaterialRoute<void>(builder: (_) => const AiRecommendationPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  const SizedBox(height: 32),
                  const Icon(Icons.auto_awesome, size: 64, color: AppColors.accent),
                  const SizedBox(height: 24),
                  Text(
                    'Wasla AI is estimating your shipment...',
                    style: AppTypography.headingSm.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                      color: AppColors.darkGreen,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Checking item size, count and suitable cargo space.',
                    style: AppTypography.bodyMd,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _buildProgress(),
                  const SizedBox(height: 24),
                  _buildStatusCard(),
                  const SizedBox(height: 16),
                  Text(
                    'You can leave this screen. Your cargo details are saved.',
                    style: AppTypography.bodyXs,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back, size: 24),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          const Spacer(),
          Text(
            'WASLA AI',
            style: AppTypography.eyebrow,
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildProgress() {
    return Row(
      children: List.generate(4, (index) {
        final done = index < _completed;
        return Expanded(
          child: Container(
            height: 4,
            margin: EdgeInsets.only(right: index < 3 ? 8 : 0),
            decoration: BoxDecoration(
              color: done ? AppColors.accent : AppColors.light,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildStatusRow('Photos received', _completed > 0 ? '✓' : '...'),
          const SizedBox(height: 12),
          _buildStatusRow('Cargo dimensions', _completed > 1 ? 'Estimating' : '...'),
          const SizedBox(height: 12),
          _buildStatusRow('Vehicle match', _completed > 2 ? 'Next' : '...'),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTypography.bodySm,
          ),
        ),
        Text(
          value,
          style: AppTypography.bodySm.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}