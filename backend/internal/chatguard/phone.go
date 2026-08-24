package chatguard

// phone.go implements Indian phone-number detection via a digit-run
// scanner rather than a single regex — regexes can't tolerate the
// unbounded, attacker-chosen mixture of separators (spaces, punctuation,
// emoji, Unicode digit variants) real bypass attempts use, since each new
// separator character would need its own alternation. Instead we walk the
// text rune-by-rune, treat digits (in several Unicode digit systems) and
// "separator" runes (see normalize.go) as a single logical run as long as
// no more than maxSeparatorGap non-digit separator runes appear between
// two digits, and anything else (a letter, an unrecognized symbol) closes
// the run. Each closed run is then checked against known Indian mobile
// number shapes.

const maxSeparatorGap = 4

// detectPhone scans body for an Indian mobile number, tolerant of
// separators, parentheses, Unicode digit substitution, and short emoji
// interruptions between digits.
func detectPhone(body string) (found bool) {
	clean := stripInvisible(body)
	runes := []rune(clean)

	var run []int // digits collected in the current candidate
	gap := 0
	collecting := false

	flush := func() {
		if collecting && isPhoneShaped(run) {
			found = true
		}
		run = run[:0]
		collecting = false
		gap = 0
	}

	for _, r := range runes {
		if found {
			return true
		}
		if d := digitFor(r); d >= 0 {
			run = append(run, d)
			collecting = true
			gap = 0
			continue
		}
		if collecting && isDigitSeparator(r) {
			gap++
			if gap > maxSeparatorGap {
				flush()
			}
			continue
		}
		// any other rune (a letter, an unhandled symbol) ends the run
		flush()
	}
	flush()
	return found
}

// isPhoneShaped reports whether a contiguous run of digits matches a
// recognized Indian mobile number layout:
//   - exactly 10 digits, first digit 6-9 (standard mobile range)
//   - 12 digits: "91" country code + 10-digit mobile
//   - 11 digits: trunk-prefix "0" + 10-digit mobile
//
// For longer runs (e.g. a 16-digit tracking/card number that happens to
// contain digits), we only flag it if a valid 10-digit mobile appears
// immediately after a "91" country-code pair — anything else is left
// alone rather than guessing, per the instruction to avoid blocking
// ordinary numbers that clearly aren't contact numbers.
func isPhoneShaped(run []int) bool {
	n := len(run)
	switch {
	case n == 10:
		return isMobilePrefix(run[0]) && !allSameDigit(run)
	case n == 11 && run[0] == 0:
		return isMobilePrefix(run[1]) && !allSameDigit(run[1:])
	case n == 12 && run[0] == 9 && run[1] == 1:
		return isMobilePrefix(run[2]) && !allSameDigit(run[2:])
	case n > 12 && n <= 20:
		for i := 0; i+2 <= n-10; i++ {
			if run[i] == 9 && run[i+1] == 1 && isMobilePrefix(run[i+2]) && !allSameDigit(run[i+2:i+12]) {
				return true
			}
		}
		return false
	default:
		return false
	}
}

func isMobilePrefix(d int) bool { return d >= 6 && d <= 9 }

// allSameDigit filters out "0000000000"-style placeholder junk that
// technically matches the shape but is never a real number.
func allSameDigit(run []int) bool {
	for _, d := range run {
		if d != run[0] {
			return false
		}
	}
	return true
}
