import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user's in-app star rating (1-5), persisted across restarts so the
/// "Rate the App" screen can show what they picked last time instead of
/// asking again from a blank slate. Null means they've never rated.
class AppRatingController extends StateNotifier<int?> {
  static const _ratingKey = 'app_rating_stars';

  AppRatingController() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getInt(_ratingKey);
  }

  Future<void> setRating(int stars) async {
    assert(stars >= 1 && stars <= 5);
    state = stars;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_ratingKey, stars);
  }
}

final appRatingProvider = StateNotifierProvider<AppRatingController, int?>((ref) {
  return AppRatingController();
});

/// The free-text comment left alongside a star rating — kept separately
/// from the star count since there's no backend endpoint to send it to
/// yet; this just lets the dialog remember what someone typed last time.
class AppRatingFeedbackController extends StateNotifier<String?> {
  static const _feedbackKey = 'app_rating_feedback';

  AppRatingFeedbackController() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(_feedbackKey);
  }

  Future<void> setFeedback(String text) async {
    state = text;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_feedbackKey, text);
  }
}

final appRatingFeedbackProvider =
    StateNotifierProvider<AppRatingFeedbackController, String?>((ref) {
  return AppRatingFeedbackController();
});
