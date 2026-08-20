import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:io' as io;

/// Renders a profile image from [path], which can be either of two things
/// depending on where in its lifecycle the photo is:
///
///  * a **local filesystem path**, straight from image_picker, before the
///    photo has been uploaded (`Image.file`); on web that's a blob URL,
///    which `Image.file` cannot open at all (it asserts `!kIsWeb`), so
///    `Image.network` handles it there.
///  * a **remote `http(s)` URL**, once the backend has stored the photo
///    and handed back its public URL. `Image.file` silently fails on these
///    — which is why an uploaded photo never appeared and the placeholder
///    initials stayed on screen.
class AppFileImage extends StatelessWidget {
  final String path;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// Shown while a remote image loads and if it fails — lets callers keep
  /// their own placeholder (e.g. initials) visible instead of a blank box.
  final Widget? placeholder;

  const AppFileImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
  });

  bool get _isRemote => path.startsWith('http://') || path.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    if (_isRemote || kIsWeb) {
      return Image.network(
        path,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, __, ___) => placeholder ?? const SizedBox.shrink(),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : (placeholder ?? const SizedBox.shrink()),
      );
    }
    return Image.file(
      io.File(path),
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (_, __, ___) => placeholder ?? const SizedBox.shrink(),
    );
  }
}
