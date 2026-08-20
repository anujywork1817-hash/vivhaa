enum SortOption { relevance, newest, ageLowToHigh, ageHighToLow }

extension SortOptionX on SortOption {
  String get label => switch (this) {
        SortOption.relevance => 'Relevance',
        SortOption.newest => 'Newest first',
        SortOption.ageLowToHigh => 'Age: low to high',
        SortOption.ageHighToLow => 'Age: high to low',
      };
}

/// Search criteria shared by Basic Search, Advanced Search, and the
/// Sort & Filter sheet on results — one model so a search can flow
/// through all three without translation.
class SearchFilters {
  final String query;
  final int ageMin;
  final int ageMax;
  final int heightMinCm;
  final int heightMaxCm;
  final Set<String> maritalStatuses;
  final Set<String> religions;
  /// Country scopes the state and city pickers only — the search index does
  /// not carry a country field, so it is deliberately not sent to the API.
  final String? country;
  final String? state;
  final String? city;
  final Set<String> communities;
  final Set<String> education;
  final Set<String> professions;
  final String? incomeMin;
  final String? diet;
  final String? manglik;
  final SortOption sort;

  const SearchFilters({
    this.query = '',
    this.ageMin = 21,
    this.ageMax = 40,
    this.heightMinCm = 145,
    this.heightMaxCm = 195,
    this.maritalStatuses = const {},
    this.religions = const {},
    this.country,
    this.state,
    this.city,
    this.communities = const {},
    this.education = const {},
    this.professions = const {},
    this.incomeMin,
    this.diet,
    this.manglik,
    this.sort = SortOption.relevance,
  });

  int get activeFilterCount {
    var count = 0;
    if (maritalStatuses.isNotEmpty) count++;
    if (religions.isNotEmpty) count++;
    if (state != null && state!.isNotEmpty) count++;
    if (city != null && city!.isNotEmpty) count++;
    if (communities.isNotEmpty) count++;
    if (education.isNotEmpty) count++;
    if (professions.isNotEmpty) count++;
    if (incomeMin != null) count++;
    if (diet != null) count++;
    if (manglik != null) count++;
    return count;
  }

  SearchFilters copyWith({
    String? query,
    int? ageMin,
    int? ageMax,
    int? heightMinCm,
    int? heightMaxCm,
    Set<String>? maritalStatuses,
    Set<String>? religions,
    String? country,
    bool clearCountry = false,
    String? state,
    bool clearState = false,
    String? city,
    bool clearCity = false,
    Set<String>? communities,
    Set<String>? education,
    Set<String>? professions,
    String? incomeMin,
    bool clearIncomeMin = false,
    String? diet,
    bool clearDiet = false,
    String? manglik,
    bool clearManglik = false,
    SortOption? sort,
  }) {
    return SearchFilters(
      query: query ?? this.query,
      ageMin: ageMin ?? this.ageMin,
      ageMax: ageMax ?? this.ageMax,
      heightMinCm: heightMinCm ?? this.heightMinCm,
      heightMaxCm: heightMaxCm ?? this.heightMaxCm,
      maritalStatuses: maritalStatuses ?? this.maritalStatuses,
      religions: religions ?? this.religions,
      country: clearCountry ? null : (country ?? this.country),
      state: clearState ? null : (state ?? this.state),
      city: clearCity ? null : (city ?? this.city),
      communities: communities ?? this.communities,
      education: education ?? this.education,
      professions: professions ?? this.professions,
      incomeMin: clearIncomeMin ? null : (incomeMin ?? this.incomeMin),
      diet: clearDiet ? null : (diet ?? this.diet),
      manglik: clearManglik ? null : (manglik ?? this.manglik),
      sort: sort ?? this.sort,
    );
  }

  SearchFilters reset() => const SearchFilters();
}
