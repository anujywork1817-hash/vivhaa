import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/api/api_result.dart';
import '../../../core/network/api_error_mapper.dart';
import 'reference_models.dart';

/// Fetches the backend's lookup lists.
///
/// Every method is a plain GET of static data, so results are memoised for
/// the life of the app session: the country list does not change while
/// someone is filling in a form, and re-fetching it on each rebuild of a
/// picker would be a request per keystroke.
class ReferenceRepository {
  final ApiClient _client;

  ReferenceRepository(this._client);

  final Map<String, List<RefState>> _statesByCountry = {};
  final Map<String, List<String>> _citiesByStateKey = {};
  List<RefCountry>? _countries;
  List<RefReligion>? _religions;

  Future<ApiResult<List<RefCountry>>> countries() async {
    final cached = _countries;
    if (cached != null) return ApiResult.success(cached);

    try {
      final response = await _client.dio.get(ApiEndpoints.referenceCountries);
      final list = (response.data['data'] as List<dynamic>)
          .map((e) => RefCountry.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
      _countries = list;
      return ApiResult.success(list);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  Future<ApiResult<List<RefState>>> states(String countryCode) async {
    final cached = _statesByCountry[countryCode];
    if (cached != null) return ApiResult.success(cached);

    try {
      final response =
          await _client.dio.get(ApiEndpoints.referenceStates(countryCode));
      final list = (response.data['data'] as List<dynamic>)
          .map((e) => RefState.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
      _statesByCountry[countryCode] = list;
      return ApiResult.success(list);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  /// Cities for one state. [query] filters server-side — some states carry
  /// over a thousand entries, so the unfiltered call is capped by the API
  /// and typing is the way to reach the rest.
  ///
  /// Only the unfiltered listing is cached; a search is keyed by whatever
  /// the member typed and would just fill memory with one-off results.
  Future<ApiResult<List<String>>> cities(
    String countryCode,
    String stateCode, {
    String query = '',
  }) async {
    final key = '$countryCode|$stateCode';
    if (query.isEmpty) {
      final cached = _citiesByStateKey[key];
      if (cached != null) return ApiResult.success(cached);
    }

    try {
      final response = await _client.dio.get(
        ApiEndpoints.referenceCities(countryCode, stateCode),
        queryParameters: query.isEmpty ? null : {'q': query},
      );
      final list = (response.data['data'] as List<dynamic>)
          .map((e) => e as String)
          .toList(growable: false);
      if (query.isEmpty) _citiesByStateKey[key] = list;
      return ApiResult.success(list);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  Future<ApiResult<List<RefReligion>>> religions() async {
    final cached = _religions;
    if (cached != null) return ApiResult.success(cached);

    try {
      final response = await _client.dio.get(ApiEndpoints.referenceReligions);
      final list = (response.data['data'] as List<dynamic>)
          .map((e) => RefReligion.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
      _religions = list;
      return ApiResult.success(list);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }
}

final referenceRepositoryProvider = Provider<ReferenceRepository>((ref) {
  return ReferenceRepository(ref.watch(apiClientProvider));
});
