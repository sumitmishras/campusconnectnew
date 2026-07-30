import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../navigation/main_navigation.dart';

class RegistrationWizard extends StatefulWidget {
  const RegistrationWizard({super.key});

  @override
  State<RegistrationWizard> createState() => _RegistrationWizardState();
}

class _RegistrationWizardState extends State<RegistrationWizard> {
  int _currentStep = 0;
  final int _totalSteps = 3;
  
  final _pageController = PageController();

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() {
        _currentStep++;
      });
    } else {
      // Navigate to main app
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const MainNavigation()),
        (route) => false,
      );
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() {
        _currentStep--;
      });
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: _previousStep,
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(_totalSteps, (index) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 30,
              height: 4,
              decoration: BoxDecoration(
                color: index <= _currentStep 
                    ? theme.primaryColor 
                    : theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildBasicInfoStep(theme),
                    _buildAcademicStep(theme),
                    _buildProfileStep(theme),
                  ],
                ),
              ),
              CustomButton(
                text: _currentStep == _totalSteps - 1 ? 'Complete Profile' : 'Next',
                onPressed: _nextStep,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBasicInfoStep(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Basic Info',
            style: theme.textTheme.displayMedium,
          ),
          const SizedBox(height: 8),
          Text(
            "Let's start with the basics.",
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
          const SizedBox(height: 32),
          const CustomTextField(
            label: 'Full Name',
            hint: 'Enter your full name',
            prefixIcon: LucideIcons.user,
          ),
          const SizedBox(height: 16),
          const CustomTextField(
            label: 'Username',
            hint: '@username',
            prefixIcon: LucideIcons.atSign,
          ),
          const SizedBox(height: 16),
          // Simple gender selection placeholder
          Text('Gender', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  child: const Text('Male'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  child: const Text('Female'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAcademicStep(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Academics',
            style: theme.textTheme.displayMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'What are you studying at CU?',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
          const SizedBox(height: 32),
          const CustomTextField(
            label: 'Department',
            hint: 'e.g., Computer Science',
            prefixIcon: LucideIcons.building,
          ),
          const SizedBox(height: 16),
          const CustomTextField(
            label: 'Course',
            hint: 'e.g., BE CSE',
            prefixIcon: LucideIcons.bookOpen,
          ),
          const SizedBox(height: 16),
          const CustomTextField(
            label: 'Current Year',
            hint: 'e.g., 3rd Year',
            prefixIcon: LucideIcons.calendar,
          ),
        ],
      ),
    );
  }

  Widget _buildProfileStep(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Profile Details',
            style: theme.textTheme.displayMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Make your profile stand out.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
          const SizedBox(height: 32),
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 60,
                  backgroundColor: theme.primaryColor.withOpacity(0.1),
                  child: Icon(LucideIcons.camera, size: 40, color: theme.primaryColor),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: CircleAvatar(
                    backgroundColor: theme.primaryColor,
                    radius: 20,
                    child: const Icon(LucideIcons.plus, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          const CustomTextField(
            label: 'Bio',
            hint: 'Write a short bio about yourself...',
          ),
          const SizedBox(height: 16),
          const CustomTextField(
            label: 'Interests',
            hint: 'e.g., Coding, Photography, Football',
          ),
        ],
      ),
    );
  }
}
