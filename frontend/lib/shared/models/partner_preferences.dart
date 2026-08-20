class PartnerPreferences {
  final int? ageMin;
  final int? ageMax;
  final int? heightMinCm;
  final int? heightMaxCm;
  final List<String> religions;
  final List<String> communities;
  final List<String> motherTongues;
  final List<String> maritalStatuses;
  final List<String> education;
  final String? locationPreference;
  final String? incomeMin;

  // Recommended-preferences summary screen
  final String? country;
  final String? state;
  final String? highestQualification;
  final String? workingWith;
  final String? profession;
  final String? profileManagedBy;
  final String? diet;

  const PartnerPreferences({
    this.ageMin,
    this.ageMax,
    this.heightMinCm,
    this.heightMaxCm,
    this.religions = const [],
    this.communities = const [],
    this.motherTongues = const [],
    this.maritalStatuses = const [],
    this.education = const [],
    this.locationPreference,
    this.incomeMin,
    this.country,
    this.state,
    this.highestQualification,
    this.workingWith,
    this.profession,
    this.profileManagedBy,
    this.diet,
  });

  PartnerPreferences copyWith({
    int? ageMin,
    int? ageMax,
    int? heightMinCm,
    int? heightMaxCm,
    List<String>? religions,
    List<String>? communities,
    List<String>? motherTongues,
    List<String>? maritalStatuses,
    List<String>? education,
    String? locationPreference,
    String? incomeMin,
    String? country,
    String? state,
    String? highestQualification,
    String? workingWith,
    String? profession,
    String? profileManagedBy,
    String? diet,
  }) {
    return PartnerPreferences(
      ageMin: ageMin ?? this.ageMin,
      ageMax: ageMax ?? this.ageMax,
      heightMinCm: heightMinCm ?? this.heightMinCm,
      heightMaxCm: heightMaxCm ?? this.heightMaxCm,
      religions: religions ?? this.religions,
      communities: communities ?? this.communities,
      motherTongues: motherTongues ?? this.motherTongues,
      maritalStatuses: maritalStatuses ?? this.maritalStatuses,
      education: education ?? this.education,
      locationPreference: locationPreference ?? this.locationPreference,
      incomeMin: incomeMin ?? this.incomeMin,
      country: country ?? this.country,
      state: state ?? this.state,
      highestQualification: highestQualification ?? this.highestQualification,
      workingWith: workingWith ?? this.workingWith,
      profession: profession ?? this.profession,
      profileManagedBy: profileManagedBy ?? this.profileManagedBy,
      diet: diet ?? this.diet,
    );
  }

  factory PartnerPreferences.fromJson(Map<String, dynamic> json) => PartnerPreferences(
        ageMin: json['ageMin'] as int?,
        ageMax: json['ageMax'] as int?,
        heightMinCm: json['heightMinCm'] as int?,
        heightMaxCm: json['heightMaxCm'] as int?,
        religions: List<String>.from(json['religions'] as List? ?? const []),
        communities: List<String>.from(json['communities'] as List? ?? const []),
        motherTongues: List<String>.from(json['motherTongues'] as List? ?? const []),
        maritalStatuses: List<String>.from(json['maritalStatuses'] as List? ?? const []),
        education: List<String>.from(json['education'] as List? ?? const []),
        locationPreference: json['locationPreference'] as String?,
        incomeMin: json['incomeMin'] as String?,
        country: json['country'] as String?,
        state: json['state'] as String?,
        highestQualification: json['highestQualification'] as String?,
        workingWith: json['workingWith'] as String?,
        profession: json['profession'] as String?,
        profileManagedBy: json['profileManagedBy'] as String?,
        diet: json['diet'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'ageMin': ageMin,
        'ageMax': ageMax,
        'heightMinCm': heightMinCm,
        'heightMaxCm': heightMaxCm,
        'religions': religions,
        'communities': communities,
        'motherTongues': motherTongues,
        'maritalStatuses': maritalStatuses,
        'education': education,
        'locationPreference': locationPreference,
        'incomeMin': incomeMin,
        'country': country,
        'state': state,
        'highestQualification': highestQualification,
        'workingWith': workingWith,
        'profession': profession,
        'profileManagedBy': profileManagedBy,
        'diet': diet,
      };
}
