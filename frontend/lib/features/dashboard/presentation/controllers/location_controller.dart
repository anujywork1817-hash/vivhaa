import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../shared/models/match_profile.dart';
import '../../data/api_dashboard_repository.dart';

/// Thrown by [nearbyMatchesProvider] when location can't be obtained —
/// carries enough detail for the UI to show the right recovery action
/// (open app settings vs. open device location settings vs. just retry).
class LocationUnavailableException implements Exception {
  final LocationFailureReason reason;
  const LocationUnavailableException(this.reason);
}

enum LocationFailureReason { serviceDisabled, permissionDenied, permissionDeniedForever }

/// Resolves the device's current GPS position, shares it with the backend
/// (powering "Near Me" for this member), then fetches nearby matches.
/// Re-fetching this provider re-reads the device's current position, so a
/// pull-to-refresh naturally re-shares an updated location too.
final nearbyMatchesProvider = FutureProvider.autoDispose<List<MatchProfile>>((ref) async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const LocationUnavailableException(LocationFailureReason.serviceDisabled);
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied) {
    throw const LocationUnavailableException(LocationFailureReason.permissionDenied);
  }
  if (permission == LocationPermission.deniedForever) {
    throw const LocationUnavailableException(LocationFailureReason.permissionDeniedForever);
  }

  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
  );

  final repo = ref.watch(dashboardRepositoryProvider);

  final updateResult =
      await repo.updateLocation(latitude: position.latitude, longitude: position.longitude);
  updateResult.when(success: (_) {}, failure: (f) => throw f);

  final matchesResult = await repo.getNearbyMatches();
  return matchesResult.when(success: (data) => data, failure: (f) => throw f);
});

final allMatchesProvider = FutureProvider.autoDispose<List<MatchProfile>>((ref) async {
  final result = await ref.watch(dashboardRepositoryProvider).getAllMatches();
  return result.when(success: (data) => data, failure: (f) => throw f);
});
