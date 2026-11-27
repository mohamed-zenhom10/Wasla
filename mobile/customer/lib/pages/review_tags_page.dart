import 'package:flutter/material.dart';
import 'package:main/components/app_page_header.dart';
import 'package:main/models/shipment.dart';
import 'package:main/services/language_service.dart';
import 'package:main/services/shipment_service.dart';
import 'package:main/theme/app_theme.dart';

class ReviewTagsPage extends StatefulWidget {
  const ReviewTagsPage({super.key, this.tags = const []});

  final List<ShipmentReviewTag> tags;

  @override
  State<ReviewTagsPage> createState() => _ReviewTagsPageState();
}

class _ReviewTagsPageState extends State<ReviewTagsPage> {
  final _service = ShipmentService();
  late List<ShipmentReviewTag> _tags;
  bool _isLoading = true;
  String? _error;
  String? _selectedTagId;

  @override
  void initState() {
    super.initState();
    _tags = widget.tags;
    if (widget.tags.isEmpty) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final catalog = await _service.getCatalog();
      if (!mounted) return;
      setState(() => _tags = catalog.reviewTags);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Review tags could not be loaded.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.darkGreen,
        elevation: 0,
        leading: BackButton(),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            const AppPageHeader(title: 'How was your move?'),
            const SizedBox(height: 18),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.accent),
                ),
                const SizedBox(height: 12),
              ],
              if (_tags.isEmpty)
                const Text('No review tags are available yet.')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in _tags.where((item) => item.isActive))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ChoiceChip(
                          label: Text(
                            LanguageService.displayName(tag.nameAr, tag.nameEn),
                          ),
                          selected: _selectedTagId == tag.id,
                          onSelected: (selected) {
                            setState(() {
                              _selectedTagId = selected ? tag.id : null;
                            });
                          },
                        ),
                      ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
