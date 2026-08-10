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

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const _avatars = [
    'https://i.pravatar.cc/300?img=12',
    'https://i.pravatar.cc/300?img=32',
    'https://i.pravatar.cc/300?img=45',
    'https://i.pravatar.cc/300?img=58',
    'https://i.pravatar.cc/300?img=68',
    'https://i.pravatar.cc/300?img=15',
  ];

  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  late final TextEditingController _statusController;
  late final TextEditingController _departmentController;
  late final TextEditingController _courseController;
  late final TextEditingController _yearController;

  late Set<String> _interests;
  late Set<String> _languages;
  late Set<String> _lookingFor;
  late String _photoUrl;

  bool _isSaving = false;
  bool _isUploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    final me = context.read<AuthProvider>().currentUser!;
    _nameController = TextEditingController(text: me.name);
    _usernameController = TextEditingController(text: me.username);
    _bioController = TextEditingController(text: me.bio);
    _statusController = TextEditingController(text: me.campusStatus ?? '');
    _departmentController = TextEditingController(text: me.department);
    _courseController = TextEditingController(text: me.course);
    _yearController = TextEditingController(text: me.year);
    _interests = me.interests.toSet();
    _languages = me.languages.toSet();
    _lookingFor = me.lookingFor.toSet();
    _photoUrl = me.profilePhotoUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _statusController.dispose();
    _departmentController.dispose();
    _courseController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameController.text.trim().length < 3) {
      showAppSnackBar(context, 'Name must be at least 3 characters',
          icon: LucideIcons.circleAlert);
      return;
    }
    if (_usernameController.text.trim().length < 3) {
      showAppSnackBar(context, 'Username must be at least 3 characters',
          icon: LucideIcons.circleAlert);
      return;
    }

    setState(() => _isSaving = true);
    await context.read<AuthProvider>().updateProfile(
          name: _nameController.text.trim(),
          username: _usernameController.text.trim(),
          bio: _bioController.text.trim(),
          campusStatus: _statusController.text.trim(),

          interests: _interests.toList(),
          languages: _languages.toList(),
          lookingFor: _lookingFor.toList(),
          profilePhotoUrl: _photoUrl,
        );
    if (!mounted) return;
    setState(() => _isSaving = false);
    Navigator.pop(context);
    showAppSnackBar(context, 'Profile updated');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = context.watch<AuthProvider>().currentUser!;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Edit Profile'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: Stack(
                  children: [
                    UserAvatar(
                      imageUrl: _photoUrl,
                      name: _nameController.text,
                      radius: 48,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: theme.primaryColor,
                        child: _isUploadingPhoto
                            ? const SizedBox(
                                height: 14,
                                width: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(LucideIcons.camera,
                                size: 15, color: Colors.white),
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
                child: const Text('Change photo'),
              ),
            ),
            const SizedBox(height: 16),
            CustomTextField(
              label: 'Full Name',
              controller: _nameController,
              prefixIcon: LucideIcons.user,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            CustomTextField(
              label: 'Username',
              controller: _usernameController,
              prefixIcon: LucideIcons.atSign,
            ),
            const SizedBox(height: 16),
            CustomTextField(
              label: 'CU Email',
              controller: TextEditingController(text: me.email),
              prefixIcon: LucideIcons.mail,
              readOnly: true,
              helperText: 'Verified — this cannot be changed',
            ),
            const SizedBox(height: 16),
            CustomTextField(
              label: 'Campus Status',
              hint: 'e.g. Need study partner for exams!',
              controller: _statusController,
              prefixIcon: LucideIcons.megaphone,
              maxLength: 60,
            ),
            const SizedBox(height: 16),
            CustomTextField(
              label: 'Bio',
              controller: _bioController,
              maxLines: 3,
              maxLength: 160,
            ),
            const SizedBox(height: 24),
            Text('Academics', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            // Not editable, and not merely disabled in the UI: department and
            // course come from the programme code in the university id, and
            // the year is computed from the admission year every July. The
            // column grants in 0008_rls_policies.sql do not include them, so
            // an edit here would be rejected by the database anyway.
            Text(
              'Taken from your university ID (${me.uid}). '
              'Contact support if something looks wrong.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            CustomTextField(
              label: 'Department',
              controller: _departmentController,
              prefixIcon: LucideIcons.building,
              readOnly: true,
            ),
            const SizedBox(height: 16),
            CustomTextField(
              label: 'Course',
              controller: _courseController,
              prefixIcon: LucideIcons.bookOpen,
              readOnly: true,
            ),
            const SizedBox(height: 16),
            CustomTextField(
              label: 'Current Year',
              controller: _yearController,
              prefixIcon: LucideIcons.calendar,
              readOnly: true,
            ),
            const SizedBox(height: 24),
            // Fed from `public.tags` when Supabase is configured, so adding a
            // tag no longer means shipping an app release.
            _multiSelect(theme, 'Interests', ReferenceData.interests,
                _interests),
            const SizedBox(height: 24),
            _multiSelect(theme, 'Languages', ReferenceData.languages,
                _languages),
            const SizedBox(height: 24),
            _multiSelect(theme, 'Looking For', ReferenceData.purposes,
                _lookingFor),
            const SizedBox(height: 32),
            CustomButton(
              text: 'Save Changes',
              isLoading: _isSaving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _multiSelect(
      ThemeData theme, String title, List<String> options, Set<String> selected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.labelLarge),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((o) {
            final isSelected = selected.contains(o);
            return FilterChip(
              label: Text(o),
              selected: isSelected,
              showCheckmark: false,
              onSelected: (_) => setState(() {
                if (isSelected) {
                  selected.remove(o);
                } else {
                  selected.add(o);
                }
              }),
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
        ),
      ],
    );
  }

  void _pickAvatar() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            Text('Choose a photo',
                style: Theme.of(sheetContext).textTheme.titleLarge),
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
                  child: UserAvatar(imageUrl: url, name: '?', radius: 32),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// Uploads the chosen photo into the `avatars` bucket and keeps the public
  /// URL, so the profile points at an object this app owns rather than at
  /// somebody else's CDN.
  ///
  /// The bucket is public deliberately: Discover renders forty avatars per
  /// scroll and signing each one would be forty round trips.
  Future<void> _applyAvatar(String url) async {
    if (!SupabaseService.isReady) {
      setState(() => _photoUrl = url);
      return;
    }

    setState(() => _isUploadingPhoto = true);
    try {
      final bytes = await FileBytes.fromNetwork(url);
      if (bytes == null) {
        if (!mounted) return;
        showAppSnackBar(context, 'That photo could not be read',
            icon: LucideIcons.circleAlert);
        return;
      }
      final uploaded = await Repositories.storage.uploadAvatar(
        bytes: bytes,
        fileName: 'avatar.jpg',
      );
      if (!mounted) return;
      setState(() => _photoUrl = uploaded.isEmpty ? url : uploaded);
    } on StorageFailure catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.message, icon: LucideIcons.circleAlert);
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }
}
