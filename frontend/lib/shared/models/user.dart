/// Authentication identity — separate from [Profile], which holds
/// matrimonial details. Mirrors what a JWT-issuing backend would return.
class AppUser {
  final String id;
  final String phoneOrEmail;
  final bool otpVerified;
  final bool profileComplete;
  final DateTime createdAt;

  /// 'user' or 'admin' — gates the Admin Dashboard entry in the menu.
  final String role;

  const AppUser({
    required this.id,
    required this.phoneOrEmail,
    required this.otpVerified,
    required this.profileComplete,
    required this.createdAt,
    this.role = 'user',
  });

  bool get isAdmin => role == 'admin';

  AppUser copyWith({
    String? id,
    String? phoneOrEmail,
    bool? otpVerified,
    bool? profileComplete,
    DateTime? createdAt,
    String? role,
  }) {
    return AppUser(
      id: id ?? this.id,
      phoneOrEmail: phoneOrEmail ?? this.phoneOrEmail,
      otpVerified: otpVerified ?? this.otpVerified,
      profileComplete: profileComplete ?? this.profileComplete,
      createdAt: createdAt ?? this.createdAt,
      role: role ?? this.role,
    );
  }

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        phoneOrEmail: json['phoneOrEmail'] as String,
        otpVerified: json['otpVerified'] as bool? ?? false,
        profileComplete: json['profileComplete'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        role: json['role'] as String? ?? 'user',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'phoneOrEmail': phoneOrEmail,
        'otpVerified': otpVerified,
        'profileComplete': profileComplete,
        'createdAt': createdAt.toIso8601String(),
        'role': role,
      };
}
