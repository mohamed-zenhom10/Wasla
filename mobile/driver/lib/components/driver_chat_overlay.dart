import 'package:driver/theme/app_theme.dart';
import 'package:flutter/material.dart';

class DriverChatLauncher extends StatefulWidget {
  const DriverChatLauncher({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<DriverChatLauncher> createState() => _DriverChatLauncherState();
}

class _DriverChatLauncherState extends State<DriverChatLauncher> {
  late final OverlayEntry _launcherEntry = OverlayEntry(
    builder: (_) => _buildLauncher(),
  );
  bool _launcherInserted = false;
  bool _chatOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final overlay = widget.navigatorKey.currentState?.overlay;
      if (overlay == null) {
        throw StateError('The driver chat overlay is not available.');
      }
      overlay.insert(_launcherEntry);
      _launcherInserted = true;
    });
  }

  @override
  void dispose() {
    if (_launcherInserted) _launcherEntry.remove();
    super.dispose();
  }

  Future<void> _openChat() async {
    final overlayContext = widget.navigatorKey.currentState?.overlay?.context;
    if (overlayContext == null) {
      throw StateError(
        'The driver chat cannot open before navigation is ready.',
      );
    }

    setState(() => _chatOpen = true);
    _launcherEntry.markNeedsBuild();
    try {
      await showModalBottomSheet<void>(
        context: overlayContext,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const DriverChatSheet(),
      );
    } finally {
      if (mounted) {
        setState(() => _chatOpen = false);
        _launcherEntry.markNeedsBuild();
      }
    }
  }

  Widget _buildLauncher() => _chatOpen
      ? const SizedBox.shrink()
      : Positioned(
          right: 18,
          bottom: 156,
          child: FloatingActionButton(
            key: const ValueKey('driver-chat-launcher'),
            heroTag: 'driver-chat-launcher',
            tooltip: 'مساعد وصلة',
            onPressed: _openChat,
            backgroundColor: AppColors.ink,
            foregroundColor: AppColors.white,
            child: const Icon(Icons.support_agent_rounded, size: 28),
          ),
        );

  @override
  Widget build(BuildContext context) => widget.child;
}

class DriverChatSheet extends StatefulWidget {
  const DriverChatSheet({super.key});

  @override
  State<DriverChatSheet> createState() => _DriverChatSheetState();
}

class _DriverChatSheetState extends State<DriverChatSheet> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [
    const _ChatMessage(
      text: 'أهلًا بيك! أقدر أساعدك في رحلتك أو استخدام تطبيق وصلة.',
      isDriver: false,
    ),
  ];

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_ChatMessage(text: text, isDriver: true));
      _messages.add(
        const _ChatMessage(
          text: 'واجهة المحادثة جاهزة، لكن خدمة المساعد الذكي لم تُربط بعد.',
          isDriver: false,
        ),
      );
      _messageController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.78;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: SafeArea(
        top: false,
        child: Container(
          height: sheetHeight,
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.muted.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: AppColors.ink,
                      foregroundColor: AppColors.white,
                      child: Icon(Icons.support_agent_rounded),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'مساعد وصلة',
                            style: TextStyle(
                              color: AppColors.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'مساعدة السائق',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'إغلاق المحادثة',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const _ChatServiceNotice(),
              Expanded(
                child: ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  itemCount: _messages.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) =>
                      _ChatBubble(message: _messages[index]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: 'اكتب رسالتك...',
                          filled: true,
                          fillColor: AppColors.surface,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'إرسال الرسالة',
                      onPressed: _sendMessage,
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.white,
                      ),
                      icon: const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatServiceNotice extends StatelessWidget {
  const _ChatServiceNotice();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(horizontal: 16),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4E5),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Row(
      children: [
        Icon(Icons.info_outline, color: Color(0xFF9A5B00), size: 18),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'نسخة تجريبية — خدمة الرد الذكي غير متصلة بعد.',
            style: TextStyle(color: Color(0xFF744500), fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) => Align(
    alignment: message.isDriver
        ? AlignmentDirectional.centerEnd
        : AlignmentDirectional.centerStart,
    child: Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: message.isDriver ? AppColors.ink : AppColors.surface,
        borderRadius: BorderRadiusDirectional.only(
          topStart: const Radius.circular(16),
          topEnd: const Radius.circular(16),
          bottomStart: Radius.circular(message.isDriver ? 16 : 4),
          bottomEnd: Radius.circular(message.isDriver ? 4 : 16),
        ),
      ),
      child: Text(
        message.text,
        style: TextStyle(
          color: message.isDriver ? AppColors.white : AppColors.ink,
          height: 1.4,
        ),
      ),
    ),
  );
}

class _ChatMessage {
  const _ChatMessage({required this.text, required this.isDriver});

  final String text;
  final bool isDriver;
}
