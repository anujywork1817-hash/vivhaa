/// One stored profile photo. Unlike the plain URL strings in
/// [Profile.photoUrls], this carries the backend id needed to delete a
/// photo or promote it to the profile picture.
class ProfilePhoto {
  final String id;
  final String url;
  final bool isPrimary;

  const ProfilePhoto({required this.id, required this.url, this.isPrimary = false});

  factory ProfilePhoto.fromJson(Map<String, dynamic> json) => ProfilePhoto(
        id: json['id'] as String,
        url: json['url'] as String,
        isPrimary: json['is_primary'] as bool? ?? false,
      );
}
