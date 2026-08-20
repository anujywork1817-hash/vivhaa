enum Gender { male, female }

enum MaritalStatus { neverMarried, divorced, widowed, awaitingDivorce }

enum ProfileFor { myself, son, daughter, brother, sister, relative, friend }

enum DietType { vegetarian, nonVegetarian, eggetarian, vegan, jain }

enum HabitLevel { no, occasionally, yes }

enum ManglikStatus { yes, no, dontKnow }

enum BodyType { slim, athletic, average, heavy }

enum FamilyType { nuclear, joint }

enum FamilyValues { traditional, moderate, liberal }

enum VerificationStatus { unverified, pending, verified, rejected }

enum SubscriptionTier { free, premium, premiumPlus, elite }

extension GenderX on Gender {
  String get label => this == Gender.male ? 'Male' : 'Female';
}

extension MaritalStatusX on MaritalStatus {
  String get label => switch (this) {
        MaritalStatus.neverMarried => 'Never Married',
        MaritalStatus.divorced => 'Divorced',
        MaritalStatus.widowed => 'Widowed',
        MaritalStatus.awaitingDivorce => 'Awaiting Divorce',
      };
}

extension ProfileForX on ProfileFor {
  String get label => switch (this) {
        ProfileFor.myself => 'Myself',
        ProfileFor.son => 'My Son',
        ProfileFor.daughter => 'My Daughter',
        ProfileFor.brother => 'My Brother',
        ProfileFor.sister => 'My Sister',
        ProfileFor.relative => 'My Relative',
        ProfileFor.friend => 'My Friend',
      };

  /// "you" / "your son" / "your daughter" / ... — the profile *subject*,
  /// as distinct from "you" the app operator (who may be a parent filling
  /// this in on someone else's behalf). Safe as a modal-verb subject
  /// ("{subject} can...") or after a preposition ("About {subject}"),
  /// since none of these forms conjugate. Never use it as the subject of
  /// a present-tense verb like "is"/"likes" — "your son" would need
  /// "likes" while "you" needs "like", and this deliberately doesn't
  /// track that distinction.
  String get subject => switch (this) {
        ProfileFor.myself => 'you',
        ProfileFor.son => 'your son',
        ProfileFor.daughter => 'your daughter',
        ProfileFor.brother => 'your brother',
        ProfileFor.sister => 'your sister',
        ProfileFor.relative => 'your relative',
        ProfileFor.friend => 'your friend',
      };

  /// Title-cased [subject]: "You" / "Your Son" / "Your Daughter" / ...
  /// — for headings like "About {subjectTitle}".
  String get subjectTitle =>
      subject.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

  /// "your" / "your son's" / "your daughter's" / ... — a possessive
  /// modifier that goes directly before a noun ("{possessive} name").
  String get possessive => switch (this) {
        ProfileFor.myself => 'your',
        ProfileFor.son => "your son's",
        ProfileFor.daughter => "your daughter's",
        ProfileFor.brother => "your brother's",
        ProfileFor.sister => "your sister's",
        ProfileFor.relative => "your relative's",
        ProfileFor.friend => "your friend's",
      };

  /// Sentence-cased [possessive]: "Your" / "Your son's" / ...
  String get possessiveTitle => '${possessive[0].toUpperCase()}${possessive.substring(1)}';
}

extension DietTypeX on DietType {
  String get label => switch (this) {
        DietType.vegetarian => 'Vegetarian',
        DietType.nonVegetarian => 'Non-Vegetarian',
        DietType.eggetarian => 'Eggetarian',
        DietType.vegan => 'Vegan',
        DietType.jain => 'Jain',
      };
}

extension HabitLevelX on HabitLevel {
  String get label => switch (this) {
        HabitLevel.no => 'No',
        HabitLevel.occasionally => 'Occasionally',
        HabitLevel.yes => 'Yes',
      };
}

extension FamilyTypeX on FamilyType {
  String get label => this == FamilyType.nuclear ? 'Nuclear' : 'Joint';
}

extension FamilyValuesX on FamilyValues {
  String get label => switch (this) {
        FamilyValues.traditional => 'Traditional',
        FamilyValues.moderate => 'Moderate',
        FamilyValues.liberal => 'Liberal',
      };
}
