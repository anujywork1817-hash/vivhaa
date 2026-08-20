# Layout rules — avoiding RenderFlex/overflow errors

This app hit repeated "Bottom overflowed" / "Right overflowed" errors from
the same handful of patterns. These are the rules that fixed them and
should be followed in any new screen.

## 1. Any `Text` showing variable-length data must truncate

Names, cities, occupations, message previews, plan names, saved-search
names, anything typed by a user or returned by the API — never assume it
fits. Either:

- wrap it in `Expanded`/`Flexible` **and** give it `maxLines` +
  `overflow: TextOverflow.ellipsis`, or
- use `TruncatedText` (`lib/shared/widgets/misc/truncated_text.dart`)
  instead of a raw `Text(...)`.

Short, fixed, developer-authored labels ("Continue", "Chat", "Filter")
don't need this — the rule is about content you don't control the length
of.

## 2. `Row` children need `Expanded`/`Flexible`, not just hope

A `Row` with an icon + two pieces of text + a trailing button can exceed
screen width the moment any one piece is longer than the value used
during development. At least one flexible child (usually the main label)
must be wrapped in `Expanded`, and every `Text` in the row still needs
`maxLines`/`overflow` per rule 1.

## 3. Don't force variable content into a fixed box

A fixed `SizedBox`/`Container(width: N, height: N)` around something whose
content can grow (a sentence, a list, a badge count) will overflow the
moment that content is larger than what was tested. Prefer:

- letting the box size from its content (`mainAxisSize: MainAxisSize.min`,
  no fixed height), or
- making the *content* size-aware via `LayoutBuilder` so it adapts to a
  small box instead of demanding more room than it's given (see
  `LockedProfilePhoto`, which drops its explanation sentence and shows
  just the lock icon when the available space is under ~120px), or
- capping the value itself (e.g. an unread-count badge shows "99+" past
  100, and uses `BoxConstraints(minWidth: ..., minHeight: ...)` with a
  stadium `borderRadius` instead of a fixed-diameter circle, so 1–3 digit
  counts all fit).

## 4. Grids: leave headroom in the aspect ratio

`childAspectRatio` on a `GridView` should be checked against the longest
realistic label/value, not the placeholder text used while building the
screen — a stat tile aspect ratio that fits "Revenue" will clip "Pending
verifications". When in doubt, make the ratio taller (lower number) and
cap text with `maxLines`+`overflow` as a second line of defense.

## 5. Screens scroll; scrollables inside scrollables need bounds

Wrap full-screen bodies that can exceed viewport height in
`SingleChildScrollView`/`CustomScrollView`. A `ListView`/`GridView` nested
inside a `Column` needs either `shrinkWrap: true` + a non-scrollable
parent, or to be wrapped in `Expanded`, or it needs a bounding
`SizedBox`/fixed-height parent — never leave it directly inside an
unbounded `Column`.

## 6. Forms and the keyboard

Screens with text fields should scroll (`SingleChildScrollView`) so the
keyboard doesn't push content into overflow, and shouldn't fight
`Scaffold`'s default `resizeToAvoidBottomInset` unless there's a specific
reason to.
