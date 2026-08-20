import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/api/api_result.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../shared/models/partner_preferences.dart';
import '../domain/preferences_repository.dart';

/// Talks to the real matrimony_backend `/preferences` endpoint (a single
/// upsert row per user — POST and PUT behave identically on the backend).
class ApiPreferencesRepository implements PreferencesRepository {
  final ApiClient _client;

  ApiPreferencesRepository(this._client);

  @override
  Future<ApiResult<void>> upsert(PartnerPreferences preferences) async {
    try {
      await _client.dio.post(ApiEndpoints.partnerPreferences, data: _toJson(preferences));
      return const ApiResult.success(null);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  Map<String, dynamic> _toJson(PartnerPreferences p) {
    return {
      'min_age': p.ageMin,
      'max_age': p.ageMax,
      'min_height_cm': p.heightMinCm,
      'max_height_cm': p.heightMaxCm,
      'marital_status': p.maritalStatuses,
      'religion': p.religions,
      'community': p.communities,
      'mother_tongue': p.motherTongues,
      'education': p.highestQualification != null ? [p.highestQualification] : <String>[],
      'min_income_inr': _parseMinIncome(p.incomeMin),
      'country': p.country != null ? [p.country] : <String>[],
      'state': p.state != null ? [p.state] : <String>[],
      'diet': _dietToBackend(p.diet) != null ? [_dietToBackend(p.diet)] : <String>[],
      'profession': p.profession,
      'working_with': p.workingWith,
      'profile_managed_by': p.profileManagedBy,
    };
  }

  int? _parseMinIncome(String? bracket) {
    if (bracket == null || bracket == 'Open to All') return null;
    final match = RegExp(r'(\d+)').firstMatch(bracket);
    if (match == null) return 0;
    return int.parse(match.group(1)!) * 100000;
  }

  String? _dietToBackend(String? diet) {
    switch (diet) {
      case 'Veg':
        return 'vegetarian';
      case 'Non-Veg':
        return 'non_vegetarian';
      case 'Eggetarian':
        return 'eggetarian';
      case 'Vegan':
        return 'vegan';
      case 'Jain':
        return 'jain';
      default:
        return null;
    }
  }
}

final preferencesRepositoryProvider = Provider<PreferencesRepository>((ref) {
  return ApiPreferencesRepository(ref.watch(apiClientProvider));
});
