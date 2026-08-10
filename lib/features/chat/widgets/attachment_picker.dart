import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/data/repositories/storage_repository.dart';
import '../../../core/models/chat_model.dart';
import '../../../core/services/attachment_service.dart';
import '../../../core/widgets/app_widgets.dart';

/// Icon + colour for a document based on its extension.
({IconData icon, Color color}) documentStyle(String extension) {
  switch (extension) {
    case 'pdf':
      return (icon: LucideIcons.fileText, color: const Color(0xFFE53935));
    case 'doc':
    case 'docx':
      return (icon: LucideIcons.fileText, color: const Color(0xFF1E88E5));
    case 'xls':
    case 'xlsx':
      return (icon: LucideIcons.fileSpreadsheet, color: const Color(0xFF2E7D32));
    case 'ppt':
    case 'pptx':
      return (icon: LucideIcons.fileType, color: const Color(0xFFEF6C00));
    default:
      return (icon: LucideIcons.file, color: const Color(0xFF607D8B));
  }
}

/// Bottom sheet that lets the student attach a photo or a document from their
/// device. Returns the chosen [Attachment] with its bytes loaded, or `null` if
/// they backed out. Anything the rules reject never leaves the sheet.
Future<Attachment?> showAttachmentPicker(BuildContext context) {
  return showModalBottomSheet<Attachment>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => const _AttachmentPickerSheet(),
  );
}

class _AttachmentPickerSheet extends StatefulWidget {
  const _AttachmentPickerSheet();

  @override
  State<_AttachmentPickerSheet> createState() => _AttachmentPickerSheetState();
}

class _AttachmentPickerSheetState extends State<_AttachmentPickerSheet> {
  String? _error;
  bool _isReading = false;

  /// Opens the platform picker, then validates what came back.
  ///
  /// Bytes are requested up front because that is what every platform can
  /// supply — `File` paths do not exist on web, and the upload needs the bytes
  /// either way.
  Future<void> _pick(AttachmentType type) async {
    setState(() {
      _isReading = true;
      _error = null;
    });

    FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        allowMultiple: false,
        withData: true,
        type: type == AttachmentType.photo ? FileType.image : FileType.custom,
        allowedExtensions: type == AttachmentType.photo
            ? null
            : AttachmentService.documentExtensions,
      );
    } on PlatformException catch (e) {
      _fail(e.message ?? 'The file picker is not available on this device.');
      return;
    } catch (_) {
      _fail('That file could not be opened.');
      return;
    }

    if (!mounted) return;

    // Cancelled — leave the sheet open so another choice can be made.
    if (result == null || result.files.isEmpty) {
      setState(() => _isReading = false);
      return;
    }

    final picked = result.files.first;
    final bytes = picked.bytes;
    if (bytes == null || bytes.isEmpty) {
      _fail('That file could not be read.');
      return;
    }

    // The declared size has to be the real byte count: create_upload_ticket()
    // records it and send_message() copies it from the ticket, never from the
    // client payload.
    final attachment = Attachment(
      type: type,
      name: picked.name,
      sizeBytes: bytes.length,
      mimeType: mimeTypeFor(picked.name),
      bytes: bytes,
    );

    final reason = AttachmentService.rejectionReason(attachment);
    if (reason != null) {
      _fail(reason);
      return;
    }

    // `width`/`height` are left null. They are nullable on
    // `message_attachments`, nothing renders from them yet, and decoding every
    // picked photo on the UI isolate to fill them in is not worth the stall.
    Navigator.pop(context, attachment);
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _isReading = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            Row(
              children: [
                Text('Share a file', style: theme.textTheme.titleLarge),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.hardDrive,
                          size: 12, color: theme.primaryColor),
                      const SizedBox(width: 6),
                      Text(
                        'Max ${AttachmentService.maxLabel}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.primaryColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Only photos and documents can be shared on Campus Connect.',
              style: theme.textTheme.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              _buildError(theme),
            ],
            const SizedBox(height: 18),
            _buildOption(
              theme,
              type: AttachmentType.photo,
              icon: LucideIcons.image,
              label: 'Photos',
              subtitle:
                  AttachmentService.photoExtensions.join(', ').toUpperCase(),
            ),
            const SizedBox(height: 12),
            _buildOption(
              theme,
              type: AttachmentType.document,
              icon: LucideIcons.fileText,
              label: 'Documents',
              subtitle:
                  AttachmentService.documentExtensions.join(', ').toUpperCase(),
            ),
            if (_isReading) ...[
              const SizedBox(height: 20),
              const Center(
                child: SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOption(
    ThemeData theme, {
    required AttachmentType type,
    required IconData icon,
    required String label,
    required String subtitle,
  }) {
    return InkWell(
      onTap: _isReading ? null : () => _pick(type),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: theme.primaryColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight,
                size: 18, color: theme.textTheme.bodySmall?.color),
          ],
        ),
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: theme.colorScheme.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.triangleAlert,
              size: 16, color: theme.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
