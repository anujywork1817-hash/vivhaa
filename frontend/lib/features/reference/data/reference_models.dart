/// Models for the backend's `/reference/*` lookup lists.
///
/// These replace what used to be `const _states = [...]` style constants
/// scattered across the onboarding and search screens — lists that never
/// varied by country, so picking Texas still offered Maharashtra cities.
library;

/// A country in the "living in" picker.
class RefCountry {
  /// ISO 3166-1 alpha-2, e.g. `US`. This is what the state/city endpoints
  /// are keyed by — [name] is display only.
  final String code;
  final String name;
  final String emoji;

  const RefCountry({required this.code, required this.name, required this.emoji});

  factory RefCountry.fromJson(Map<String, dynamic> json) => RefCountry(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
        emoji: json['emoji'] as String? ?? '',
      );

  /// `🇮🇳 India` — the flag reads as part of the label in the picker.
  String get label => emoji.isEmpty ? name : '$emoji  $name';
}

/// A first-level subdivision: a US state, an Indian state, a UK country.
class RefState {
  /// Unique within its country only — `MH` is Maharashtra in India and
  /// nothing at all in the US, so it must always be paired with a country.
  final String code;
  final String name;

  const RefState({required this.code, required this.name});

  factory RefState.fromJson(Map<String, dynamic> json) => RefState(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );
}

/// One community and the sub-castes under it.
class RefCommunity {
  final String name;
  final List<String> subCastes;

  const RefCommunity({required this.name, required this.subCastes});

  factory RefCommunity.fromJson(Map<String, dynamic> json) => RefCommunity(
        name: json['name'] as String? ?? '',
        subCastes: (json['sub_castes'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(growable: false),
      );
}

/// A religion with its communities. The whole tree arrives in one response —
/// it is only a few KB, so the cascade happens locally rather than costing a
/// round trip per level.
class RefReligion {
  final String name;
  final List<RefCommunity> communities;

  const RefReligion({required this.name, required this.communities});

  factory RefReligion.fromJson(Map<String, dynamic> json) => RefReligion(
        name: json['name'] as String? ?? '',
        communities: (json['communities'] as List<dynamic>? ?? const [])
            .map((e) => RefCommunity.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );

  /// Sub-castes for one community, or empty when the community is unknown
  /// to this religion — which is what a stale selection looks like after
  /// the member changes religion.
  List<String> subCastesFor(String? community) {
    if (community == null) return const [];
    for (final c in communities) {
      if (c.name == community) return c.subCastes;
    }
    return const [];
  }
}
