import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/markdown/markdown_storage_service.dart';

class ProjectStoredImage extends StatelessWidget {
  const ProjectStoredImage({
    required this.location,
    this.thumbnail = false,
    this.fit = BoxFit.contain,
    super.key,
  });

  final String location;
  final bool thumbnail;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final parsed = MarkdownStorageLocation.parse(location);
    if (parsed.kind == MarkdownStorageKind.localPath) {
      return Image.file(
        File(parsed.localPath!),
        fit: fit,
        cacheWidth: thumbnail ? 320 : null,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.image_not_supported_rounded),
      );
    }
    return _TreeImage(location: location, thumbnail: thumbnail, fit: fit);
  }
}

class _TreeImage extends ConsumerStatefulWidget {
  const _TreeImage({
    required this.location,
    required this.thumbnail,
    required this.fit,
  });

  final String location;
  final bool thumbnail;
  final BoxFit fit;

  @override
  ConsumerState<_TreeImage> createState() => _TreeImageState();
}

class _TreeImageState extends ConsumerState<_TreeImage> {
  late Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _TreeImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location ||
        oldWidget.thumbnail != widget.thumbnail) {
      _load();
    }
  }

  void _load() {
    _bytes = ref
        .read(markdownStorageProvider)
        .readImageLocation(widget.location, thumbnail: widget.thumbnail);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      key: ValueKey(_bytes),
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return IconButton(
            tooltip: '无法读取图片，请检查目录授权后重试',
            onPressed: () => setState(_load),
            icon: const Icon(Icons.refresh_rounded),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return const Center(
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return Image.memory(
          bytes,
          fit: widget.fit,
          cacheWidth: widget.thumbnail ? 320 : null,
          errorBuilder: (_, _, _) =>
              const Icon(Icons.image_not_supported_rounded),
        );
      },
    );
  }
}
