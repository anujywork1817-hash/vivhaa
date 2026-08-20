import 'package:flutter/material.dart';
import '../../../../shared/widgets/misc/profile_avatar.dart';

class PhotoGalleryArgs {
  final List<String> photoIds;
  final String name;
  final int initialIndex;

  const PhotoGalleryArgs({
    required this.photoIds,
    required this.name,
    this.initialIndex = 0,
  });
}

/// Full-screen photo viewer — swipe between photos, tap to toggle chrome.
/// Photos are placeholder tiles (no real image pipeline yet) but the
/// interaction — paging, indicator, index tracking — is real.
class PhotoGalleryScreen extends StatefulWidget {
  final PhotoGalleryArgs args;
  const PhotoGalleryScreen({super.key, required this.args});

  @override
  State<PhotoGalleryScreen> createState() => _PhotoGalleryScreenState();
}

class _PhotoGalleryScreenState extends State<PhotoGalleryScreen> {
  late final PageController _controller =
      PageController(initialPage: widget.args.initialIndex);
  late int _index = widget.args.initialIndex;
  bool _chromeVisible = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.args.photoIds;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: photos.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                return GestureDetector(
                  onTap: () => setState(() => _chromeVisible = !_chromeVisible),
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 0.8,
                      child: ProfileAvatar(
                        name: '${widget.args.name}$i',
                        size: double.infinity,
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                  ),
                );
              },
            ),
            if (_chromeVisible) ...[
              Positioned(
                left: 8,
                top: 8,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(photos.length, (i) {
                    final active = i == _index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: active ? Colors.white : Colors.white38,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
              Positioned(
                right: 12,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_index + 1} / ${photos.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
