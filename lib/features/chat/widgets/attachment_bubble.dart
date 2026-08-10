import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/data/repositories/repositories.dart';
import '../../../core/data/repositories/storage_repository.dart';
import '../../../core/models/chat_model.dart';
import '../../../core/widgets/app_widgets.dart';
import 'attachment_picker.dart';

/// Opens a stored attachment with whatever the device uses for its type.
///
/// The URL is signed fresh on every open rather than reusing the one the page
/// was rendered with: `chat-media` is private, signatures expire, and a thread
/// left open for an hour would otherwise hand out a dead link. Returns null on
/// success, or the reason it could not be opened.
Future<String?> openAttachment(Attachment attachment) async {
  if (attachment.scanStatus == ScanStatus.infected) {
    return '${attachment.name} was blocked by the file scanner';
  }
  if (!attachment.isStored) {
    return 'That file is still being sent';
  }

  final url = await Repositories.storage.signedUrl(
    attachment.bucket.isEmpty ? StorageBuckets.chatMedia : attachment.bucket,
    attachment.objectPath,
  );
  if (url.isEmpty) {
    return 'That file is no longer available';
  }

  try {
    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    return launched ? null : 'No app on this device can open that file';
  } catch (_) {
    return 'That file could not be opened';
  }
}

/// Renders a shared photo or document inside a chat bubble.
class AttachmentBubble extends StatefulWidget {
  final Attachment attachment;
  final bool isMe;

  const AttachmentBubble({
    super.key,
    required this.attachment,
    required this.isMe,
  });

  @override
  State<AttachmentBubble> createState() => _AttachmentBubbleState();
}

class _AttachmentBubbleState extends State<AttachmentBubble> {
  bool _isOpening = false;

  Attachment get attachment => widget.attachment;
  bool get isMe => widget.isMe;

  /// Files are scanned in the background and start `pending`; a file the scanner
  /// rejected is never rendered or opened. See the malware note in
  /// `supabase/DATABASE.md`.
  bool get _isBlocked =>
      attachment.isStored && attachment.scanStatus == ScanStatus.infected;

  Future<void> _open() async {
    if (_isOpening) return;
    setState(() => _isOpening = true);
    final problem = await openAttachment(attachment);
    if (!mounted) return;
    setState(() => _isOpening = false);
    if (problem != null) {
      showAppSnackBar(context, problem, icon: LucideIcons.circleAlert);
    }
  }

  @override
  Widget build(BuildContext context) {
    return attachment.isPhoto ? _photo(context) : _document(context);
  }

  /// The image the sender is looking at is the one they picked, so an outgoing
  /// bubble renders from the bytes in memory until the upload has finished and
  /// a signed URL exists.
  Widget? _imageProvider(BoxFit fit, {double? width, double? height}) {
    final bytes = attachment.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(bytes, width: width, height: height, fit: fit);
    }
    if (attachment.previewUrl.isEmpty) return null;
    return Image.network(
      attachment.previewUrl,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return SizedBox(
          width: width,
          height: height,
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
      errorBuilder: (_, _, _) => SizedBox(
        width: width,
        height: height,
        child: const Center(child: Icon(LucideIcons.image, size: 32)),
      ),
    );
  }

  Widget _photo(BuildContext context) {
    final theme = Theme.of(context);
    final image = _isBlocked ? null : _imageProvider(BoxFit.cover, width: 220, height: 165);

    if (image == null) return _placeholder(theme);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _PhotoViewer(attachment: attachment),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Hero(
              tag: 'attachment-${attachment.name}-${attachment.hashCode}',
              child: image,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${attachment.name} • ${attachment.readableSize}',
            style: TextStyle(
              fontSize: 11,
              color: isMe ? Colors.white70 : theme.textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  /// Shown while a signed URL is still being fetched, and in place of a file
  /// the scanner rejected.
  Widget _placeholder(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 220,
          height: 165,
          decoration: BoxDecoration(
            color: theme.primaryColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _isBlocked ? LucideIcons.shieldAlert : LucideIcons.image,
            size: 32,
            color: _isBlocked ? theme.colorScheme.error : theme.primaryColor,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _isBlocked ? 'This file was blocked' : attachment.name,
          style: TextStyle(
            fontSize: 11,
            color: isMe ? Colors.white70 : theme.textTheme.bodySmall?.color,
          ),
        ),
      ],
    );
  }

  Widget _document(BuildContext context) {
    final theme = Theme.of(context);
    final style = documentStyle(attachment.extension);

    return GestureDetector(
      onTap: _open,
      child: Container(
        width: 230,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isMe
              ? Colors.white.withValues(alpha: 0.18)
              : theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: isMe
                    ? Colors.white.withValues(alpha: 0.25)
                    : style.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                style.icon,
                size: 19,
                color: isMe ? Colors.white : style.color,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attachment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color:
                          isMe ? Colors.white : theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${attachment.extension.toUpperCase()} • ${attachment.readableSize}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isMe
                          ? Colors.white70
                          : theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
            if (_isOpening)
              const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                _isBlocked ? LucideIcons.shieldAlert : LucideIcons.download,
                size: 16,
                color: _isBlocked
                    ? theme.colorScheme.error
                    : isMe
                        ? Colors.white70
                        : theme.textTheme.bodySmall?.color,
              ),
          ],
        ),
      ),
    );
  }
}

/// Full screen photo view with the file details in the app bar.
class _PhotoViewer extends StatefulWidget {
  final Attachment attachment;

  const _PhotoViewer({required this.attachment});

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  bool _isOpening = false;

  Future<void> _download() async {
    if (_isOpening) return;
    setState(() => _isOpening = true);
    final problem = await openAttachment(widget.attachment);
    if (!mounted) return;
    setState(() => _isOpening = false);
    if (problem != null) {
      showAppSnackBar(context, problem, icon: LucideIcons.circleAlert);
    }
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachment;
    final bytes = attachment.bytes;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              attachment.name,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              attachment.readableSize,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          if (attachment.isStored)
            IconButton(
              icon: _isOpening
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(LucideIcons.download),
              tooltip: 'Open or save',
              onPressed: _isOpening ? null : _download,
            ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: Hero(
            tag: 'attachment-${attachment.name}-${attachment.hashCode}',
            child: bytes != null && bytes.isNotEmpty
                ? Image.memory(bytes, fit: BoxFit.contain)
                : Image.network(
                    attachment.previewUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(LucideIcons.image,
                        size: 64, color: Colors.white24),
                  ),
          ),
        ),
      ),
    );
  }
}
