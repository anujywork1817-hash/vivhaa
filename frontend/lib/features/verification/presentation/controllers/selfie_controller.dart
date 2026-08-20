import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Path of the just-captured selfie, held between the capture and
/// confirm screens.
final selfiePathProvider = StateProvider<String?>((ref) => null);
