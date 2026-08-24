package chatguard

import (
	"strings"
	"unicode"
)

// normalize.go builds a *detection-only* representation of a message.
//
// IMPORTANT: this representation is never persisted and never shown to
// any user -- the original message body is what gets stored when a
// message is allowed. Destructively normalizing the stored text would
// mangle legitimate content (e.g. collapsing "10  AM" or stripping emoji
// from an otherwise-fine message) -- see Phase 3.

// Invisible/zero-width runes an attacker can insert between digits to
// defeat naive matching while the text still renders as nothing to a
// human. Written as \u escapes (not literal glyphs) so the source file
// itself stays plain ASCII and can't be silently corrupted by an editor
// or tool that treats "invisible" bytes specially (a literal BOM rune,
// for instance, is illegal anywhere in a Go source file except as the
// very first byte).
const (
	zeroWidthSpace     = rune(0x200B)
	zeroWidthNonJoiner = rune(0x200C)
	zeroWidthJoiner    = rune(0x200D)
	byteOrderMark      = rune(0xFEFF)
	wordJoiner         = rune(0x2060)
	softHyphen         = rune(0x00AD)
)

// stripInvisible removes zero-width and other invisible-but-renderless
// characters that are otherwise indistinguishable from "nothing" to a
// human reader but break naive substring/regex matching when inserted
// between digits (e.g. "987<ZWSP>654<ZWSP>3210").
func stripInvisible(s string) string {
	var b strings.Builder
	b.Grow(len(s))
	for _, r := range s {
		switch r {
		case zeroWidthSpace, zeroWidthNonJoiner, zeroWidthJoiner, byteOrderMark, wordJoiner, softHyphen:
			continue
		}
		if unicode.Is(unicode.Mn, r) || unicode.Is(unicode.Me, r) {
			// Combining/enclosing marks (accents, the "keycap" combiner
			// used by emoji digit keys like 9️⃣, etc.) rendered on top of
			// the previous rune -- drop rather than let them break digit
			// runs.
			continue
		}
		b.WriteRune(r)
	}
	return b.String()
}

// digitFor maps a rune to its ASCII digit value if it is any of the
// digit systems attackers might substitute for plain 0-9 (fullwidth,
// Devanagari, Arabic-Indic, Bengali -- the scripts an Indian-market app
// realistically sees), or -1 if it isn't a digit at all.
func digitFor(r rune) int {
	switch {
	case r >= '0' && r <= '9':
		return int(r - '0')
	case r >= 0xFF10 && r <= 0xFF19: // fullwidth 0-9
		return int(r - 0xFF10)
	case r >= 0x0966 && r <= 0x096F: // Devanagari 0-9
		return int(r - 0x0966)
	case r >= 0x06F0 && r <= 0x06F9: // Extended Arabic-Indic 0-9
		return int(r - 0x06F0)
	case r >= 0x0660 && r <= 0x0669: // Arabic-Indic 0-9
		return int(r - 0x0660)
	case r >= 0x09E6 && r <= 0x09EF: // Bengali 0-9
		return int(r - 0x09E6)
	default:
		return -1
	}
}

// isDigitSeparator reports whether r is a character commonly inserted
// between digits to defeat naive phone-number regexes while the result
// still visually/audibly reads as one number to a human: spaces
// (including Unicode variants), dashes, dots, slashes, parens, bullets,
// and emoji/symbol characters used as decorative separators.
func isDigitSeparator(r rune) bool {
	switch r {
	case ' ', '\t', '\n', '\r', '-', '–', '—', '_', '.', ',', '/', '\\',
		'(', ')', '[', ']', '{', '}', '|', '~', '*', '•', '·', ':', ';', '#', '+':
		return true
	}
	if unicode.Is(unicode.Zs, r) { // any Unicode space separator (NBSP, thin space, ideographic space, ...)
		return true
	}
	if r >= 0x1F300 && r <= 0x1FAFF { // pictographs/emoji
		return true
	}
	if r >= 0x2600 && r <= 0x27BF { // misc symbols & dingbats
		return true
	}
	if r >= 0x2190 && r <= 0x21FF { // arrows
		return true
	}
	if r >= 0xFE00 && r <= 0xFE0F { // variation selectors
		return true
	}
	return false
}
