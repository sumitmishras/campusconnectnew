import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/data/reference_data.dart';
import '../../../core/data/repositories/repositories.dart';
import '../../../core/data/repositories/storage_repository.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/file_bytes.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../navigation/main_navigation.dart';
import 'welcome_screen.dart';

class RegistrationWizard extends StatefulWidget {
  const RegistrationWizard({super.key});

  @override
  State<RegistrationWizard> createState() => _RegistrationWizardState();
}

class _RegistrationWizardState extends State<RegistrationWizard> {
  static const _totalSteps = 3;
  static const _avatars = [
    'https://i.pravatar.cc/300?img=12',
    'https://i.pravatar.cc/300?img=32',
    'https://i.pravatar.cc/300?img=45',
    'https://i.pravatar.cc/300?img=58',
    'https://i.pravatar.cc/300?img=68',
    'https://i.pravatar.cc/300?img=15',
  ];

  final _pageController = PageController();

  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _departmentController = TextEditingController();
  final _courseController = TextEditingController();
  final _yearController = TextEditingController();
  final _bioController = TextEditingController();

  int _currentStep = 0;
  String _gender = '';
  String _photoUrl = '';
  bool _isUploadingPhoto = false;
  final Set<String> _interests = {};
  final Set<String> _languages = {};
  final Set<String> _lookingFor = {};
  final Map<int, String> _errors = {};

  @override
  void initState() {
    super.initState();
    // Everything we already know from the university id is pre-filled.
    final identity = context.read<AuthProvider>().pendingIdentity;
    if (identity != null) {
      _usernameController.text = identity.suggestedUsername;
      _departmentController.text = identity.department;
      _courseController.text = identity.course;
      _yearController.text = identity.yearOfStudy;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    _departmentController.dispose();
    _courseController.dispose();
    _yearController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  String? _validateStep(int step) {
    switch (step) {
      case 0:
        if (_nameController.text.trim().length < 3) {
          return 'Please enter your full name';
        }
        if (_usernameController.text.trim().length < 3) {
          return 'Pick a username with at least 3 characters';
        }
        if (_gender.isEmpty) return 'Please select a gender';
        return null;
      case 1:
        if (_departmentController.text.trim().isEmpty) {
          return 'Department cannot be empty';
        }
        if (_courseController.text.trim().isEmpty) {
          return 'Course cannot be empty';
        }
        if (_yearController.text.trim().isEmpty) {
          return 'Please select your current year';
        }
        return null;
      case 2:
        if (_interests.isEmpty) return 'Pick at least one interest';
        if (_lookingFor.isEmpty) return 'Tell people what you are looking for';
        return null;
    }
    return null;
  }

  Future<void> _nextStep() async {
    final error = _validateStep(_currentStep);
    if (error != null) {
      setState(() => _errors[_currentStep] = error);
      showAppSnackBar(context, error, icon: LucideIcons.circleAlert);
      return;
    }
    setState(() => _errors.remove(_currentStep));

    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      return;
    }

    await context.read<AuthProvider>().completeRegistration(
          name: _nameController.text.trim(),
          username: _usernameController.text.trim(),
          gender: _gender,
          department: _departmentController.text.trim(),
          course: _courseController.text.trim(),
          year: _yearController.text.trim(),
          bio: _bioController.text.trim(),
          interests: _interests.toList(),
          languages: _languages.toList(),
          lookingFor: _lookingFor.toList(),
          profilePhotoUrl: _photoUrl,
        );

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const MainNavigation()),
      (route) => false,
    );
  }

  void _previousStep() {
    if (_currentStep == 0) {
      if (Navigator.of(context).canPop()) {
        Navigator.pop(context);
      } else {
        // Reached here straight after verification — abandoning the wizard
        // means abandoning the sign-up.
        context.read<AuthProvider>().logout();
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
      }
      return;
    }
    setState(() => _currentStep--);
    _pageController.animateToPage(
      _currentStep,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
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
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: index == _currentStep ? 40 : 24,
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
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
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
              if (_errors[_currentStep] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _errors[_currentStep]!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              CustomButton(
                text:
                    _currentStep == _totalSteps - 1 ? 'Complete Profile' : 'Next',
                onPressed: _nextStep,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ step 1 of 3

  Widget _buildBasicInfoStep(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stepHeader(theme, 'Basic Info', "Let's start with the basics."),
          CustomTextField(
            label: 'Full Name',
            hint: 'Enter your full name',
            prefixIcon: LucideIcons.user,
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          CustomTextField(
            label: 'Username',
            hint: '@username',
            prefixIcon: LucideIcons.atSign,
            controller: _usernameController,
            helperText: 'This is how other students will find you',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Text('Gender', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(
            children: ['Male', 'Female', 'Other'].map((g) {
              final selected = _gender == g;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton(
                    onPressed: () => setState(() => _gender = g),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: selected
                          ? theme.primaryColor.withValues(alpha: 0.1)
                          : null,
                      side: BorderSide(
                        color:
                            selected ? theme.primaryColor : theme.dividerColor,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      g,
                      style: TextStyle(
                        color: selected
                            ? theme.primaryColor
                            : theme.textTheme.bodyMedium?.color,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          _buildVerifiedEmailNote(theme),
        ],
      ),
    );
  }

  Widget _buildVerifiedEmailNote(ThemeData theme) {
    final identity = context.read<AuthProvider>().pendingIdentity;
    if (identity == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.badgeCheck, size: 18, color: theme.primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${identity.email} verified',
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: theme.primaryColor),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ step 2 of 3

  Widget _buildAcademicStep(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stepHeader(theme, 'Academics', 'What are you studying at CU?'),
          CustomTextField(
            label: 'Department',
            hint: 'e.g., Computer Science',
            prefixIcon: LucideIcons.building,
            controller: _departmentController,
            readOnly: true,
            onTap: () => _pickFromSheet(
              title: 'Select Department',
              options: ReferenceData.departments,
              onSelected: (v) => setState(() => _departmentController.text = v),
            ),
            suffixIcon: const Icon(LucideIcons.chevronDown, size: 18),
          ),
          const SizedBox(height: 16),
          CustomTextField(
            label: 'Course',
            hint: 'e.g., B.E. CSE',
            prefixIcon: LucideIcons.bookOpen,
            controller: _courseController,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          CustomTextField(
            label: 'Current Year',
            hint: 'e.g., 3rd Year',
            prefixIcon: LucideIcons.calendar,
            controller: _yearController,
            readOnly: true,
            onTap: () => _pickFromSheet(
              title: 'Select Year',
              options: ReferenceData.years,
              onSelected: (v) => setState(() => _yearController.text = v),
            ),
            suffixIcon: const Icon(LucideIcons.chevronDown, size: 18),
          ),
          const SizedBox(height: 24),
          Text('Languages you speak', style: theme.textTheme.labelLarge),
          const SizedBox(height: 12),
          _buildMultiSelect(
            theme,
            options: ReferenceData.languages,
            selected: _languages,
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ step 3 of 3

  Widget _buildProfileStep(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stepHeader(theme, 'Profile Details', 'Make your profile stand out.'),
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 56,
                    backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
                    foregroundImage:
                        _photoUrl.isEmpty ? null : NetworkImage(_photoUrl),
                    onForegroundImageError:
                        _photoUrl.isEmpty ? null : (_, _) {},
                    child: Icon(LucideIcons.camera,
                        size: 36, color: theme.primaryColor),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      backgroundColor: theme.primaryColor,
                      radius: 18,
                      child: _isUploadingPhoto
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(LucideIcons.plus,
                              color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _pickAvatar,
              child: const Text('Choose a photo'),
            ),
          ),
          const SizedBox(height: 16),
          CustomTextField(
            label: 'Bio',
            hint: 'Write a short bio about yourself...',
            controller: _bioController,
            maxLines: 3,
            maxLength: 160,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          Text('Interests', style: theme.textTheme.labelLarge),
          const SizedBox(height: 12),
          _buildMultiSelect(
            theme,
            options: ReferenceData.interests,
            selected: _interests,
          ),
          const SizedBox(height: 24),
          Text('I am looking for', style: theme.textTheme.labelLarge),
          const SizedBox(height: 12),
          _buildMultiSelect(
            theme,
            options: ReferenceData.purposes,
            selected: _lookingFor,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ parts

  Widget _stepHeader(ThemeData theme, String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(title, style: theme.textTheme.displayMedium),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodyLarge
              ?.copyWith(color: theme.textTheme.bodySmall?.color),
        ),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _buildMultiSelect(
    ThemeData theme, {
    required List<String> options,
    required Set<String> selected,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        final isSelected = selected.contains(option);
        return FilterChip(
          label: Text(option),
          selected: isSelected,
          showCheckmark: false,
          onSelected: (_) {
            setState(() {
              if (isSelected) {
                selected.remove(option);
              } else {
                selected.add(option);
              }
            });
          },
          labelStyle: TextStyle(
            color: isSelected
                ? theme.primaryColor
                : theme.textTheme.bodyMedium?.color,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
          side: BorderSide(
            color: isSelected ? theme.primaryColor : theme.dividerColor,
          ),
        );
      }).toList(),
    );
  }

  void _pickAvatar() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            Text('Choose a profile photo',
                style: Theme.of(sheetContext).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Camera and gallery are disabled in the demo — pick one of these instead.',
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: _avatars.map((url) {
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _applyAvatar(url);
                  },
                  child: CircleAvatar(
                    radius: 32,
                    foregroundImage: NetworkImage(url),
                    onForegroundImageError: (_, _) {},
                    backgroundColor: Theme.of(sheetContext)
                        .primaryColor
                        .withValues(alpha: 0.1),
                    child: const Icon(LucideIcons.user, size: 20),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// Uploads the chosen photo into the `avatars` bucket so the finished profile
  /// points at an object this app owns. The session already exists by the time
  /// the wizard runs — the OTP was verified to get here — so
  /// `cc_avatars_write` has an `auth.uid()` to check the path against.
  Future<void> _applyAvatar(String url) async {
    if (!SupabaseService.isReady) {
      setState(() => _photoUrl = url);
      return;
    }

    setState(() => _isUploadingPhoto = true);
    try {
      final bytes = await FileBytes.fromNetwork(url);
      if (bytes == null) {
        if (mounted) {
          showAppSnackBar(context, 'That photo could not be read',
              icon: LucideIcons.circleAlert);
        }
        return;
      }
      final uploaded = await Repositories.storage
          .uploadAvatar(bytes: bytes, fileName: 'avatar.jpg');
      if (!mounted) return;
      setState(() => _photoUrl = uploaded.isEmpty ? url : uploaded);
    } on StorageFailure catch (e) {
      if (mounted) {
        showAppSnackBar(context, e.message, icon: LucideIcons.circleAlert);
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  void _pickFromSheet({
    required String title,
    required List<String> options,
    required ValueChanged<String> onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHandle(),
              Text(title, style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: options
                      .map((o) => ListTile(
                            title: Text(o),
                            onTap: () {
                              onSelected(o);
                              Navigator.pop(sheetContext);
                            },
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
