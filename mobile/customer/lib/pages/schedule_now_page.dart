import 'package:flutter/material.dart';
import 'package:main/components/main_button.dart';
import 'package:main/pages/price_estimate_page.dart';
import 'package:main/routing/app_route.dart';
import 'package:main/theme/app_theme.dart';

class ScheduleNowPage extends StatefulWidget {
  const ScheduleNowPage({super.key});

  @override
  State<ScheduleNowPage> createState() => _ScheduleNowPageState();
}

class _ScheduleNowPageState extends State<ScheduleNowPage> {
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();

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
                  const SizedBox(height: 16),
                  Text(
                    'Schedule pickup',
                    style: AppTypography.headingSm,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pickup within 2 hours',
                    style: AppTypography.bodySm,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _buildDateCard(),
                  const SizedBox(height: 12),
                  _buildTimeCard(),
                  const SizedBox(height: 12),
                  _buildInfoCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            _buildActions(),
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
          Text('WASLA', style: AppTypography.eyebrow),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildDateCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today, color: AppColors.darkGreen),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Date', style: AppTypography.labelSm),
                Text(
                  _formatDate(_selectedDate),
                  style: AppTypography.bodyMd,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _pickDate,
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.access_time, color: AppColors.darkGreen),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Time', style: AppTypography.labelSm),
                Text(
                  _selectedTime.format(context),
                  style: AppTypography.bodyMd,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _pickTime,
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Driver will arrive within the 2-hour window. You can track them in real time.',
        style: AppTypography.bodyXs,
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: WaslaButton(
        text: 'Continue to price estimate',
        variant: WaslaButtonVariant.primary,
        onPressed: () => Navigator.of(context).push(
          TAMaterialRoute<void>(builder: (_) => const PriceEstimatePage()),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }
}