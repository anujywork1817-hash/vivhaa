import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/api/api_result.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../shared/mapping/profile_enum_mapping.dart';
import '../../../shared/models/match_profile.dart';
import '../../../shared/models/saved_search.dart';
import '../../../shared/models/search_filters.dart';
import '../domain/search_repository.dart';

/// Talks to the real matrimony_backend `/search/profiles`,
/// `/profile-code/:code`, and `/saved-searches` endpoints. The search
/// query supports multiple values for every filter (marital status,
/// religion, community, education, diet, occupation), plus a manglik
/// filter, a height range, and a free-text query.
class ApiSearchRepository implements SearchRepository {
  static const int pageSize = 20;

  final ApiClient _client;

  ApiSearchRepository(this._client);

  @override
  Future<ApiResult<List<MatchProfile>>> search(SearchFilters filters, {int page = 0}) async {
    try {
      final response = await _client.dio.get(ApiEndpoints.search, queryParameters: {
        'page': page + 1,
        'limit': pageSize,
        'min_age': filters.ageMin,
        'max_age': filters.ageMax,
        'min_height_cm': filters.heightMinCm,
        'max_height_cm': filters.heightMaxCm,
        if (filters.maritalStatuses.isNotEmpty)
          'marital_status': filters.maritalStatuses.map(maritalStatusLabelToBackend).toList(),
        if (filters.religions.isNotEmpty) 'religion': filters.religions.toList(),
        if (filters.communities.isNotEmpty) 'community': filters.communities.toList(),
        if (filters.education.isNotEmpty) 'education': filters.education.toList(),
        if (filters.professions.isNotEmpty) 'occupation': filters.professions.toList(),
        // `country` is intentionally absent: it scopes the pickers in the UI
        // but the search index carries no country field to match against.
        if (filters.state != null && filters.state!.isNotEmpty) 'state': filters.state,
        if (filters.city != null && filters.city!.isNotEmpty) 'city': filters.city,
        if (filters.diet != null) 'diet': [dietLabelToBackend(filters.diet!)],
        if (filters.manglik != null) 'manglik': manglikLabelToBackend(filters.manglik!),
        if (filters.query.trim().isNotEmpty) 'q': filters.query.trim(),
        if (_parseMinIncome(filters.incomeMin) != null)
          'min_income_inr': _parseMinIncome(filters.incomeMin),
      });
      final rows = (response.data['data'] as List).cast<Map<String, dynamic>>();
      var results = rows.map(_fromJson).toList();
      if (filters.sort == SortOption.ageLowToHigh) {
        results.sort((a, b) => a.age.compareTo(b.age));
      } else if (filters.sort == SortOption.ageHighToLow) {
        results.sort((a, b) => b.age.compareTo(a.age));
      }
      return ApiResult.success(results);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  /// Looks up a profile by its human-readable code (e.g. "VV100042") via
  /// `/profile-code/:code`. Falls back to treating the input as a raw
  /// profile UUID (`/profiles/:id`) so a pasted-in real ID still works.
  @override
  Future<ApiResult<MatchProfile?>> findByProfileId(String profileId) async {
    final query = profileId.trim();
    try {
      final response = await _client.dio.get(ApiEndpoints.profileByCode(query));
      return ApiResult.success(_fromProfileJson(response.data['data'] as Map<String, dynamic>));
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) return ApiResult.failure(mapDioException(e));
    }

    try {
      final response = await _client.dio.get(ApiEndpoints.profileById(query));
      return ApiResult.success(_fromProfileJson(response.data['data'] as Map<String, dynamic>));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return const ApiResult.success(null);
      return ApiResult.failure(mapDioException(e));
    }
  }

  MatchProfile _fromProfileJson(Map<String, dynamic> data) {
    return MatchProfile(
      id: data['id'] as String,
      name: (data['full_name'] as String?) ?? 'Member',
      age: 0,
      heightCm: (data['height_cm'] as num?)?.toInt() ?? 0,
      city: (data['city'] as String?) ?? '',
      profession: (data['occupation'] as String?) ?? '',
      education: (data['education'] as String?) ?? '',
      religion: (data['religion'] as String?) ?? '',
      community: data['community'] as String?,
      maritalStatus: maritalStatusLabelFromBackend(data['marital_status'] as String?),
      diet: dietLabelFromBackend(data['diet'] as String?),
      manglik: manglikLabelFromBackend(data['manglik'] as String?),
      backendProfileCode: data['profile_code'] as String?,
    );
  }

  @override
  Future<ApiResult<List<SavedSearch>>> getSavedSearches() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.savedSearches);
      final rows = (response.data['data'] as List).cast<Map<String, dynamic>>();
      return ApiResult.success(rows.map(_savedSearchFromJson).toList());
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<SavedSearch>> saveSearch(String name, SearchFilters filters, int resultCount) async {
    try {
      final response = await _client.dio.post(ApiEndpoints.savedSearches, data: {
        'name': name,
        'filters': _filtersToJson(filters),
        'result_count': resultCount,
      });
      final data = response.data['data'] as Map<String, dynamic>;
      return ApiResult.success(_savedSearchFromJson(data));
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<void>> deleteSavedSearch(String id) async {
    try {
      await _client.dio.delete(ApiEndpoints.savedSearch(id));
      return const ApiResult.success(null);
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  int? _parseMinIncome(String? bracket) {
    if (bracket == null || bracket.isEmpty) return null;
    final match = RegExp(r'(\d+)').firstMatch(bracket);
    if (match == null) return null;
    return int.parse(match.group(1)!) * 100000;
  }

  MatchProfile _fromJson(Map<String, dynamic> json) {
    return MatchProfile(
      id: json['profile_id'] as String,
      name: (json['full_name'] as String?) ?? 'Member',
      age: (json['age'] as num?)?.toInt() ?? 0,
      heightCm: (json['height_cm'] as num?)?.toInt() ?? 0,
      city: (json['city'] as String?) ?? '',
      profession: (json['occupation'] as String?) ?? '',
      education: (json['education'] as String?) ?? '',
      religion: (json['religion'] as String?) ?? '',
      community: json['community'] as String?,
      maritalStatus: maritalStatusLabelFromBackend(json['marital_status'] as String?),
      diet: dietLabelFromBackend(json['diet'] as String?),
      manglik: manglikLabelFromBackend(json['manglik'] as String?),
      photoSeed: json['photo_url'] as String?,
      backendProfileCode: json['profile_code'] as String?,
    );
  }

  Map<String, dynamic> _filtersToJson(SearchFilters f) => {
        'query': f.query,
        'age_min': f.ageMin,
        'age_max': f.ageMax,
        'height_min_cm': f.heightMinCm,
        'height_max_cm': f.heightMaxCm,
        'marital_statuses': f.maritalStatuses.toList(),
        'religions': f.religions.toList(),
        'city': f.city,
        'communities': f.communities.toList(),
        'education': f.education.toList(),
        'professions': f.professions.toList(),
        'income_min': f.incomeMin,
        'diet': f.diet,
        'manglik': f.manglik,
        'sort': f.sort.name,
      };

  SearchFilters _filtersFromJson(Map<String, dynamic> json) {
    return SearchFilters(
      query: json['query'] as String? ?? '',
      ageMin: (json['age_min'] as num?)?.toInt() ?? 21,
      ageMax: (json['age_max'] as num?)?.toInt() ?? 40,
      heightMinCm: (json['height_min_cm'] as num?)?.toInt() ?? 145,
      heightMaxCm: (json['height_max_cm'] as num?)?.toInt() ?? 195,
      maritalStatuses: ((json['marital_statuses'] as List?) ?? const []).cast<String>().toSet(),
      religions: ((json['religions'] as List?) ?? const []).cast<String>().toSet(),
      city: json['city'] as String?,
      communities: ((json['communities'] as List?) ?? const []).cast<String>().toSet(),
      education: ((json['education'] as List?) ?? const []).cast<String>().toSet(),
      professions: ((json['professions'] as List?) ?? const []).cast<String>().toSet(),
      incomeMin: json['income_min'] as String?,
      diet: json['diet'] as String?,
      manglik: json['manglik'] as String?,
      sort: SortOption.values.firstWhere(
        (s) => s.name == json['sort'],
        orElse: () => SortOption.relevance,
      ),
    );
  }

  SavedSearch _savedSearchFromJson(Map<String, dynamic> json) {
    final filtersRaw = json['filters'];
    final filtersMap = filtersRaw is String
        ? jsonDecode(filtersRaw) as Map<String, dynamic>
        : filtersRaw as Map<String, dynamic>;
    return SavedSearch(
      id: json['id'] as String,
      name: json['name'] as String,
      filters: _filtersFromJson(filtersMap),
      createdAt: DateTime.parse(json['created_at'] as String),
      resultCount: (json['result_count'] as num?)?.toInt() ?? 0,
    );
  }
}

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return ApiSearchRepository(ref.watch(apiClientProvider));
});
