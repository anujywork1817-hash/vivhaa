/// The annual-income brackets offered during onboarding, paired with the
/// rupee figure sent to the backend (which stores a single number, not a
/// range).
///
/// Kept in one place so the label→number and number→label directions can't
/// drift apart: the backend round-trips income as a plain integer, so
/// without an exact inverse mapping a saved bracket would come back as a
/// different label (or none at all) after every profile fetch.
class IncomeBracket {
  final String label;

  /// Lower bound in rupees. Distinct for every bracket — "Upto INR 1 Lakh"
  /// deliberately maps to 0 rather than 100000 so it doesn't collide with
  /// "INR 1 Lakh to 2 Lakh" and make the reverse lookup ambiguous.
  final int lowerBoundInr;

  const IncomeBracket(this.label, this.lowerBoundInr);
}

const incomeBrackets = <IncomeBracket>[
  IncomeBracket('Upto INR 1 Lakh', 0),
  IncomeBracket('INR 1 Lakh to 2 Lakh', 100000),
  IncomeBracket('INR 2 Lakh to 4 Lakh', 200000),
  IncomeBracket('INR 4 Lakh to 7 Lakh', 400000),
  IncomeBracket('INR 7 Lakh to 10 Lakh', 700000),
  IncomeBracket('INR 10 Lakh to 15 Lakh', 1000000),
  IncomeBracket('INR 15 Lakh to 20 Lakh', 1500000),
  IncomeBracket('INR 20 Lakh to 30 Lakh', 2000000),
  IncomeBracket('INR 30 Lakh to 50 Lakh', 3000000),
  IncomeBracket('INR 50 Lakh+', 5000000),
];

List<String> get incomeBracketLabels => incomeBrackets.map((b) => b.label).toList();
