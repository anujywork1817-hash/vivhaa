/// Backend enum values <-> the display labels used on [MatchProfile] and
/// throughout the UI. The backend stores snake_case enums (marital_status,
/// diet, manglik); the UI has always shown title-case / friendly labels.
library;

String maritalStatusLabelFromBackend(String? value) {
  switch (value) {
    case 'divorced':
      return 'Divorced';
    case 'widowed':
      return 'Widowed';
    case 'awaiting_divorce':
      return 'Awaiting Divorce';
    case 'never_married':
      return 'Never Married';
    default:
      return 'Never Married';
  }
}

String maritalStatusLabelToBackend(String label) {
  switch (label) {
    case 'Divorced':
      return 'divorced';
    case 'Widowed':
      return 'widowed';
    case 'Awaiting Divorce':
      return 'awaiting_divorce';
    default:
      return 'never_married';
  }
}

String dietLabelFromBackend(String? value) {
  switch (value) {
    case 'non_vegetarian':
      return 'Non-Vegetarian';
    case 'eggetarian':
      return 'Eggetarian';
    case 'vegan':
      return 'Vegan';
    case 'jain':
      return 'Jain';
    case 'vegetarian':
      return 'Vegetarian';
    default:
      return 'Vegetarian';
  }
}

String dietLabelToBackend(String label) {
  switch (label) {
    case 'Non-Vegetarian':
      return 'non_vegetarian';
    case 'Eggetarian':
      return 'eggetarian';
    case 'Vegan':
      return 'vegan';
    case 'Jain':
      return 'jain';
    default:
      return 'vegetarian';
  }
}

String manglikLabelFromBackend(String? value) {
  switch (value) {
    case 'yes':
      return 'Yes';
    case 'no':
      return 'No';
    case 'dont_know':
      return "Don't know";
    default:
      return "Don't know";
  }
}

String manglikLabelToBackend(String label) {
  switch (label) {
    case 'Yes':
      return 'yes';
    case 'No':
      return 'no';
    default:
      return 'dont_know';
  }
}
