import 'package:flutter/material.dart';
import 'package:main/components/app_page_header.dart';
import 'package:main/theme/app_theme.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        children: [
          const AppPageHeader(title: 'Messages'),
          const SizedBox(height: 8),
          Text(
            'Conversations with your drivers will appear here.',
            style: AppTypography.bodySm.copyWith(color: AppColors.gray),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search messages',
              hintStyle: AppTypography.bodySm.copyWith(color: AppColors.gray),
              prefixIcon: const Icon(Icons.search, color: AppColors.darkGreen),
              filled: true,
              fillColor: AppColors.light,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.accent),
              ),
            ),
          ),
          const SizedBox(height: 56),
          _EmptyMessagesState(
            searching: _searchController.text.trim().isNotEmpty,
          ),
        ],
      ),
    );
  }
}

class _EmptyMessagesState extends StatelessWidget {
  const _EmptyMessagesState({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: const BoxDecoration(
            color: AppColors.light,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.chat_bubble_outline,
            color: AppColors.darkGreen,
            size: 32,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          searching ? 'No matching conversations' : 'No conversations yet',
          textAlign: TextAlign.center,
          style: AppTypography.headingSm,
        ),
        const SizedBox(height: 8),
        Text(
          searching
              ? 'Try another search.'
              : 'Messages related to your trips will show up here.',
          textAlign: TextAlign.center,
          style: AppTypography.bodySm.copyWith(color: AppColors.gray),
        ),
      ],
    );
  }
}
