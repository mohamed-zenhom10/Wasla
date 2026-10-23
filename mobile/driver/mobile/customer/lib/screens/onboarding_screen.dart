import 'package:flutter/material.dart';
import 'package:main/screens/welcome_screen.dart';
import 'package:main/services/onboarding_service.dart';
import 'package:main/theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _pages = <_OnboardingPageData>[
    _OnboardingPageData(
      image: 'assets/images/onboarding/onboarding_1.png',
      title: 'Move anything.',
      description: 'Furniture, packages, goods or appliances. One simple way to get it there.',
    ),
    _OnboardingPageData(
      image: 'assets/images/onboarding/onboarding_2.png',
      title: 'Find the right truck.',
      description: 'Tell us about your cargo. Wasla finds the right fit — without the guesswork.',
    ),
    _OnboardingPageData(
      image: 'assets/images/onboarding/onboarding_3.png',
      title: 'Track every move.',
      description: 'From your gate to their door. Real-time updates, clear ETAs and a driver you can reach.',
    ),
  ];

  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isFinishing = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    if (_isFinishing) return;
    setState(() => _isFinishing = true);

    await OnboardingService.markCompleted();
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
    );
  }

  void _goToNextPage() {
    if (_currentPage == _pages.length - 1) {
      _finishOnboarding();
      return;
    }

    _pageController.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'W',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 40,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextButton(
                    onPressed: _isFinishing ? null : _finishOnboarding,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.darkGreen,
                      padding: const EdgeInsets.symmetric(horizontal: 0),
                    ),
                    child: const Text('Skip'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pages.length,
                  onPageChanged: (page) => setState(() => _currentPage = page),
                  itemBuilder: (context, index) => _buildPage(_pages[index]),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isFinishing ? null : _goToNextPage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    _currentPage == _pages.length - 1
                        ? 'Get started'
                        : 'Continue',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPage(_OnboardingPageData page) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.03,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(page.image, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 22),
          _PageIndicator(pageCount: _pages.length, currentPage: _currentPage),
          const SizedBox(height: 28),
          Text(
            page.title,
            style: const TextStyle(
              color: AppColors.darkGreen,
              fontSize: 30,
              height: 1.15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            page.description,
            style: const TextStyle(
              color: AppColors.darkGreen,
              fontSize: 16,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'MAKE LOGISTICS SIMPLE.',
            style: TextStyle(
              color: AppColors.darkGreen,
              fontSize: 11,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.pageCount, required this.currentPage});

  final int pageCount;
  final int currentPage;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
        pageCount,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: index == currentPage ? 32 : 8,
          height: 4,
          margin: EdgeInsets.only(right: index == pageCount - 1 ? 0 : 8),
          decoration: BoxDecoration(
            color: index == currentPage
                ? AppColors.accent
                : const Color(0xFFB8B8B8),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.image,
    required this.title,
    required this.description,
  });

  final String image;
  final String title;
  final String description;
}
