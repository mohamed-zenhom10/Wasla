import 'package:flutter/material.dart';
import 'package:main/pages/trip_details_page.dart';
import 'package:main/routing/app_route.dart';
import 'package:main/services/mock_data.dart';
import 'package:main/theme/app_theme.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
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
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                children: ChatMock.messages.map(_buildMessage).toList(),
              ),
            ),
            _buildInputBar(),
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
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.light,
            child: Icon(Icons.person, color: AppColors.darkGreen, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(TrackingMock.driverName, style: AppTypography.bodyMd),
                Text(TrackingMock.vehicle, style: AppTypography.bodyXs),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              TAMaterialRoute<void>(
                builder: (_) => const TripDetailsPage(),
              ),
            ),
            tooltip: 'Trip details',
            icon: const Icon(Icons.receipt_outlined, size: 22),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(ChatMessage message) {
    final isDriver = message.sender == 'driver';
    return Align(
      alignment: isDriver ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDriver ? AppColors.light : AppColors.accent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message.text,
              style: AppTypography.bodySm,
            ),
            const SizedBox(height: 4),
            Text(
              message.time,
              style: AppTypography.bodyXs,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                style: const TextStyle(color: AppColors.darkGreen, fontSize: 14),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.send, color: AppColors.accent, size: 24),
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
          ],
        ),
      ),
    );
  }
}