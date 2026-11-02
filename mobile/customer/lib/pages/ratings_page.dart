import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/services/mock_data.dart';
import 'package:main/theme/app_theme.dart';

class RatingsPage extends StatefulWidget {
  const RatingsPage({super.key});

  @override
  State<RatingsPage> createState() => _RatingsPageState();
}

class _RatingsPageState extends State<RatingsPage> {
  int _selectedRating = 5;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  const SizedBox(height: 16),
                  _buildSummaryCard(),
                  const SizedBox(height: 16),
                  _buildRatingCard(),
                  const SizedBox(height: 16),
                  _buildCommentCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
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
          Text('WASLA', style: AppTypography.eyebrow),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Rate your trip', style: AppTypography.headingSm),
          const SizedBox(height: 8),
          Text(
            'How was your experience with ${RatingMock.driverName}?',
            style: AppTypography.bodySm,
          ),
        ],
      ),
    );
  }

  Widget _buildRatingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your rating', style: AppTypography.labelSm),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final isSelected = index < _selectedRating;
              return IconButton(
                padding: EdgeInsets.zero,
                onPressed: () => setState(() => _selectedRating = index + 1),
                icon: Icon(
                  isSelected ? Icons.star : Icons.star_border_rounded,
                  color: isSelected ? AppColors.accent : AppColors.darkGreen,
                  size: 32,
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '$_selectedRating / 5',
              style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Comment', style: AppTypography.labelSm),
          const SizedBox(height: 10),
          TextField(
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Share any feedback about the move...',
              filled: true,
              fillColor: AppColors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          WaslaButton(
            text: 'Submit review',
            variant: WaslaButtonVariant.primary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 8),
          WaslaButton(
            text: 'Skip for now',
            variant: WaslaButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
