import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/api/api_result.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../shared/models/enums.dart';
import '../../../shared/models/income_brackets.dart';
import '../../../shared/models/profile.dart';
import '../../../shared/models/profile_photo.dart';
import '../domain/onboarding_repository.dart';

/// Talks to the real matrimony_backend `/profiles` endpoints.
///
/// One thing still doesn't survive the round trip: the backend stores a
/// single combined `siblings_count`, not a brothers/sisters split, so
/// [getMyProfile] can't reconstruct that split — see the comment at the
/// relevant field below.
class ApiOnboardingRepository implements OnboardingRepository {
  final ApiClient _client;

  ApiOnboardingRepository(this._client);

  @override
  Future<ApiResult<ProfileSubmitResult>> submitProfile(Profile profile) async {
    try {
      final body = _toBackendJson(profile);
      Map<String, dynamic> data;
      try {
        final response =
            await _client.dio.post(ApiEndpoints.createProfile, data: body);
        data = response.data['data'] as Map<String, dynamic>;
      } on DioException catch (e) {
        if (e.response?.statusCode == 409) {
          // Profile already exists (e.g. re-entering onboarding after an
          // earlier successful submit) — fall back to updating it.
          final response =
              await _client.dio.put(ApiEndpoints.myProfile, data: body);
          data = response.data['data'] as Map<String, dynamic>;
        } else {
          rethrow;
        }
      }

      final photoUploadFailures = await _uploadNewPhotos(profile);

      // Re-fetch so the returned Profile reflects the real, persisted
      // photo URLs rather than the local picker paths just uploaded.
      final refreshed = await getMyProfile();
      final saved = refreshed.when(
        success: (p) => (p ?? _fromBackendJson(data)).copyWith(submitted: true),
        failure: (f) => _fromBackendJson(data).copyWith(submitted: true),
      );
      return ApiResult.success(
        ProfileSubmitResult(
            profile: saved, photoUploadFailures: photoUploadFailures),
      );
    } on DioException catch (e) {
      return ApiResult.failure(mapDioException(e));
    }
  }

  @override
  Future<ApiResult<Profile?>> getMyProfile() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.myProfile);
      final data = response.data['data'] as Map<String, dynamic>;
      return ApiResult.success(_fromBackendJson(data));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return const ApiResult.success(null);
      return ApiResult.failure(mapDioException(e));
    }
  }

  /// Uploads every picked photo path that isn't already a persisted
  /// `http(s)://` URL. Returns the number of uploads that failed so the
  /// caller can tell the user their photo didn't save, rather than
  /// silently dropping it (which made a rejected upload indistinguishable
  /// from a successful one).
  ///
  /// submitProfile() runs more than once during a single onboarding pass
  /// (partner_preferences_screen.dart submits mid-flow, then
  /// review_confirm_screen.dart submits again at the end) — so a photo
  /// picked early can already be uploaded and committed on the backend
  /// well before onboarding actually finishes. If the applicant then goes
  /// back and picks a different photo, that earlier one was never
  /// cleaned up: nothing tracked "this used to be the primary photo, now
  /// replace it" past the moment of upload, so it just sat in the
  /// gallery as an invisible leftover forever — the applicant only ever
  /// saw their latest pick in the picker circle, never realizing an
  /// older one was still there until someone else viewed their profile
  /// and saw more photos than they ever meant to add. Capturing whichever
  /// photo is primary *before* this upload, then deleting it once the new
  /// one has taken over, closes that gap regardless of which screen
  /// triggered the submit.
  Future<int> _uploadNewPhotos(Profile profile) async {
    final localPaths = profile.photoUrls
        .where((p) => !p.startsWith('http://') && !p.startsWith('https://'))
        .toSet() // photo_upload_screen can list the same path more than once
        .take(6);

    String? oldPrimaryId;
    if (localPaths.contains(profile.profilePhotoUrl)) {
      try {
        final response = await _client.dio.get(ApiEndpoints.myProfile);
        final data = response.data['data'] as Map<String, dynamic>;
        final rows = (data['photos'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        final photos = rows.map(ProfilePhoto.fromJson).toList();
        final primaries = photos.where((p) => p.isPrimary);
        if (primaries.isNotEmpty) oldPrimaryId = primaries.first.id;
      } catch (_) {
        // No profile yet (first-ever photo, nothing to replace) or a
        // transient lookup failure — either way, nothing to delete.
      }
    }

    var failures = 0;
    for (final path in localPaths) {
      try {
        final xfile = XFile(path);
        final bytes = await xfile.readAsBytes();
        final filename = xfile.name.isNotEmpty ? xfile.name : 'photo.jpg';
        final response = await _client.dio.post(
          ApiEndpoints.uploadPhoto,
          data: FormData.fromMap({
            'photo': MultipartFile.fromBytes(
              bytes,
              filename: filename,
              // Required. Without it dio defaults to
              // application/octet-stream, which the backend rejects
              // outright (storage.ValidateImage only allows jpeg/png/webp)
              // — so every photo upload failed with a 400 that was then
              // swallowed, and the photo just never appeared.
              contentType: _mediaTypeFor(filename),
            ),
          }),
        );

        // The backend only auto-marks the very first photo a profile ever
        // has as primary, so without this an updated profile picture
        // uploaded fine but never became the displayed one — the old
        // primary kept winning and it looked like nothing changed.
        if (path == profile.profilePhotoUrl) {
          final photoId = (response.data['data']
              as Map<String, dynamic>?)?['id'] as String?;
          if (photoId != null) {
            await _client.dio.put(ApiEndpoints.setPrimaryPhoto(photoId));
            if (oldPrimaryId != null && oldPrimaryId != photoId) {
              try {
                await _client.dio
                    .delete(ApiEndpoints.deletePhoto(oldPrimaryId));
              } catch (_) {
                // Non-fatal: the new photo is correctly uploaded and
                // primary either way — a failed cleanup just leaves one
                // stray extra photo rather than losing the real change.
              }
            }
          }
        }
      } catch (_) {
        failures++;
      }
    }
    return failures;
  }

  /// Maps a filename to the content type the backend accepts. Falls back
  /// to jpeg, which covers the camera/gallery output image_picker produces
  /// after its own re-encode (imageQuality: 85).
  DioMediaType _mediaTypeFor(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return DioMediaType('image', 'png');
    if (lower.endsWith('.webp')) return DioMediaType('image', 'webp');
    return DioMediaType('image', 'jpeg');
  }

  Map<String, dynamic> _toBackendJson(Profile p) {
    final json = <String, dynamic>{};
    void put(String key, dynamic value) {
      if (value == null) return;
      // A blank text field means "not filled in", not "clear the saved
      // value". Sending '' overwrote real data on the backend — e.g.
      // saving from Edit Profile with an empty company box wiped a
      // company name set during onboarding (leaving an empty string in
      // the column rather than the untouched original).
      if (value is String && value.trim().isEmpty) return;
      json[key] = value;
    }

    put('full_name', p.fullName);
    put('date_of_birth',
        p.dateOfBirth == null ? null : _formatDate(p.dateOfBirth!));
    put('gender', p.gender?.name);
    put('height_cm', p.heightCm);
    put('marital_status', _maritalStatusToBackend[p.maritalStatus]);
    put('religion', p.religion);
    put('community', p.community);
    put('mother_tongue', p.motherTongue);
    put('education', p.highestEducation);
    put('occupation', p.profession);
    put('annual_income_inr', _parseIncomeBracket(p.annualIncome));
    put('country', p.country);
    put('state', p.state);
    put('city', p.city);
    put('family_type', p.familyType?.name);
    put('family_status', _familyStatusToBackend[p.familyFinancialStatus]);
    put('father_occupation', p.fatherOccupation);
    put('mother_occupation', p.motherOccupation);
    final siblings = (p.brothers ?? 0) + (p.sisters ?? 0);
    if (p.brothers != null || p.sisters != null)
      json['siblings_count'] = siblings;
    put('diet', _dietToBackend[p.diet]);
    put('smoking', p.smoking?.name);
    put('drinking', p.drinking?.name);
    put('about_me', p.aboutMe);

    put('profile_for', p.profileFor?.name);
    put('sub_community', p.subCommunity);
    put('caste_no_bar', p.casteNoBar);
    put('college', p.college);
    put('work_with', _workWithToBackend[p.workWith]);
    put('company_name', p.companyName);
    put('matchmaking_opt_out', p.matchmakingOptOut);
    put('family_values', p.familyValues?.name);
    put('lives_with_family', p.livesWithFamily);
    if (p.hobbies.isNotEmpty) json['hobbies'] = p.hobbies;
    put('selfie_verified', p.selfieVerified);
    put('manglik', _manglikToBackend[p.manglik]);
    put('rashi', p.rashi);
    put('nakshatra', p.nakshatra);
    put('birth_time', p.birthTime);
    put('birth_place', p.birthPlace);
    put('weight_kg', p.weightKg);
    put('body_type', p.bodyType?.name);
    put('complexion', p.complexion);
    put('has_disability', p.hasDisability);
    put('visibility', p.visibility);

    return json;
  }

  Profile _fromBackendJson(Map<String, dynamic> j) {
    final photos =
        (j['photos'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final primary = photos.where((p) => p['is_primary'] == true).firstOrNull ??
        photos.firstOrNull;

    String? fullName = j['full_name'] as String?;
    String? firstName;
    String? lastName;
    if (fullName != null && fullName.trim().isNotEmpty) {
      final parts = fullName.trim().split(RegExp(r'\s+'));
      firstName = parts.first;
      lastName = parts.length > 1 ? parts.sublist(1).join(' ') : null;
    }

    return Profile(
      id: j['id'] as String? ?? '',
      profileCode: j['profile_code'] as String? ?? '',
      firstName: firstName,
      lastName: lastName,
      dateOfBirth: (j['date_of_birth'] as String?) != null
          ? DateTime.tryParse(j['date_of_birth'] as String)
          : null,
      gender: _genderFromBackend[j['gender']],
      // height_cm and annual_income_inr are both sent to the backend by
      // _toBackendJson and returned by it, but were missing here — so on
      // the re-fetch that follows every submit they were silently dropped
      // from the draft, making them look like they never saved.
      heightCm: (j['height_cm'] as num?)?.toInt(),
      annualIncome:
          _incomeBracketFromInr((j['annual_income_inr'] as num?)?.toInt()),
      maritalStatus: _maritalStatusFromBackend[j['marital_status']],
      city: j['city'] as String?,
      state: j['state'] as String?,
      country: j['country'] as String?,
      religion: j['religion'] as String?,
      motherTongue: j['mother_tongue'] as String?,
      community: j['community'] as String?,
      highestEducation: j['education'] as String?,
      profession: j['occupation'] as String?,
      familyType: _familyTypeFromBackend[j['family_type']],
      familyFinancialStatus: _familyStatusFromBackend2[j['family_status']],
      fatherOccupation: j['father_occupation'] as String?,
      motherOccupation: j['mother_occupation'] as String?,
      // The backend stores one combined sibling count, not a
      // brothers/sisters split — can't be reconstructed, left null.
      diet: _dietFromBackend[j['diet']],
      smoking: _habitFromBackend[j['smoking']],
      drinking: _habitFromBackend[j['drinking']],
      aboutMe: j['about_me'] as String?,
      photoUrls: photos.map((p) => p['url'] as String).toList(),
      photos: photos.map(ProfilePhoto.fromJson).toList(),
      profilePhotoUrl: primary?['url'] as String?,
      profileFor: _profileForFromBackend[j['profile_for']],
      subCommunity: j['sub_community'] as String?,
      casteNoBar: j['caste_no_bar'] as bool?,
      college: j['college'] as String?,
      workWith: _workWithFromBackend[j['work_with']],
      companyName: j['company_name'] as String?,
      matchmakingOptOut: j['matchmaking_opt_out'] as bool?,
      familyValues: _familyValuesFromBackend[j['family_values']],
      livesWithFamily: j['lives_with_family'] as bool?,
      hobbies: (j['hobbies'] as List<dynamic>? ?? []).cast<String>(),
      selfieVerified: j['selfie_verified'] as bool? ?? false,
      manglik: _manglikFromBackend[j['manglik']],
      rashi: j['rashi'] as String?,
      nakshatra: j['nakshatra'] as String?,
      birthTime: j['birth_time'] as String?,
      birthPlace: j['birth_place'] as String?,
      weightKg: (j['weight_kg'] as num?)?.toInt(),
      bodyType: _bodyTypeFromBackend[j['body_type']],
      complexion: j['complexion'] as String?,
      hasDisability: j['has_disability'] as bool?,
      visibility: j['visibility'] as String?,
      submitted: true,
      createdAt: (j['created_at'] as String?) != null
          ? DateTime.tryParse(j['created_at'] as String)
          : null,
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// `annualIncome` is a UI bracket label like "INR 4 Lakh to 7 Lakh", not
  /// a number, but the backend stores a plain integer. Exact bracket
  /// matches use the shared [incomeBrackets] table so the value survives a
  /// round trip; anything else (Edit Profile accepts free text) falls back
  /// to reading the first figure as lakhs.
  int? _parseIncomeBracket(String? label) {
    if (label == null || label.trim().isEmpty) return null;
    for (final bracket in incomeBrackets) {
      if (bracket.label == label) return bracket.lowerBoundInr;
    }
    final numbers = RegExp(r'\d+')
        .allMatches(label)
        .map((m) => int.parse(m.group(0)!))
        .toList();
    if (numbers.isEmpty) return null;
    return numbers.first * 100000;
  }

  /// Inverse of [_parseIncomeBracket] — picks the highest bracket whose
  /// lower bound the stored figure reaches, so a value saved from the
  /// onboarding picker comes back as the exact same label.
  String? _incomeBracketFromInr(int? inr) {
    if (inr == null) return null;
    IncomeBracket? match;
    for (final bracket in incomeBrackets) {
      if (inr >= bracket.lowerBoundInr) match = bracket;
    }
    return match?.label;
  }

  static const _maritalStatusToBackend = {
    MaritalStatus.neverMarried: 'never_married',
    MaritalStatus.divorced: 'divorced',
    MaritalStatus.widowed: 'widowed',
    MaritalStatus.awaitingDivorce: 'awaiting_divorce',
  };
  static final _maritalStatusFromBackend = {
    for (final e in _maritalStatusToBackend.entries) e.value: e.key,
  };

  static const _genderFromBackend = {
    'male': Gender.male,
    'female': Gender.female
  };

  static const _familyTypeFromBackend = {
    'nuclear': FamilyType.nuclear,
    'joint': FamilyType.joint
  };

  // Frontend's 4 tiers ranked high-to-low as authored, matched 1:1 against
  // the backend's 4 tiers (middle_class < upper_middle_class < affluent < rich).
  static const _familyStatusToBackend = {
    'Elite': 'rich',
    'High': 'affluent',
    'Middle': 'upper_middle_class',
    'Aspiring': 'middle_class',
  };
  static final _familyStatusFromBackend2 = {
    for (final e in _familyStatusToBackend.entries) e.value: e.key,
  };

  static const _dietToBackend = {
    DietType.vegetarian: 'vegetarian',
    DietType.nonVegetarian: 'non_vegetarian',
    DietType.eggetarian: 'eggetarian',
    DietType.vegan: 'vegan',
    DietType.jain: 'jain',
  };
  static final _dietFromBackend = {
    for (final e in _dietToBackend.entries) e.value: e.key
  };

  static final _habitFromBackend = {
    for (final h in HabitLevel.values) h.name: h
  };

  static const _profileForFromBackend = {
    'myself': ProfileFor.myself,
    'son': ProfileFor.son,
    'daughter': ProfileFor.daughter,
    'brother': ProfileFor.brother,
    'sister': ProfileFor.sister,
    'relative': ProfileFor.relative,
    'friend': ProfileFor.friend,
  };

  // work_details_screen's _workWithOptions display strings <-> backend enum.
  static const _workWithToBackend = {
    'Private Company': 'private_company',
    'Government / Public Sector': 'government',
    'Defense / Civil Services': 'defense',
    'Business / Self Employed': 'business',
    'Not Working': 'not_working',
  };
  static final _workWithFromBackend = {
    for (final e in _workWithToBackend.entries) e.value: e.key,
  };

  static const _familyValuesFromBackend = {
    'traditional': FamilyValues.traditional,
    'moderate': FamilyValues.moderate,
    'liberal': FamilyValues.liberal,
  };

  static const _manglikToBackend = {
    ManglikStatus.yes: 'yes',
    ManglikStatus.no: 'no',
    ManglikStatus.dontKnow: 'dont_know',
  };
  static final _manglikFromBackend = {
    for (final e in _manglikToBackend.entries) e.value: e.key
  };

  static const _bodyTypeFromBackend = {
    'slim': BodyType.slim,
    'athletic': BodyType.athletic,
    'average': BodyType.average,
    'heavy': BodyType.heavy,
  };
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return ApiOnboardingRepository(ref.watch(apiClientProvider));
});
