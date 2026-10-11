# Changelog

What changed in each release. The same notes, shortened, are what F-Droid
shows as "What's new": `fastlane/metadata/android/en-US/changelogs/`, one file
per version code.

## 0.4.2

Packaging only: the per-ABI APKs take F-Droid's version codes, the version
code times ten plus a digit for the ABI (61, 62, 63 for this release), in
place of Flutter's 1000, 2000 and 4000 added on. The app is unchanged.

## 0.4.1

Store listing only: the short description no longer ends with a full stop,
as F-Droid asks. The app is unchanged from 0.4.0, and this is the first
release on F-Droid, so its "What's new" repeats the notes below.

## 0.4.0

A polish release: nothing new to learn, everything easier to read.

- **Spacing.** One page margin and one spacing scale throughout, in portrait
  and landscape. In landscape the two columns start from the same top.
- **Type.** One type scale for the whole app: every sheet title, heading, row
  and caption looks the same wherever it appears. Small and grey text now
  meets the WCAG AA contrast guideline of 4.5:1; the faintest used to be
  3.1:1.
- **Tyre cards.** Wheel labels and reading ages are larger and brighter, a
  stale reading's age stands out in white, and temperatures read "28 °C" as
  they do everywhere else.
- **Settings** open under the vehicle's own name and say "Saved for this
  vehicle only"; haptics and animations sit under "All vehicles".
- **Landscape.** The vehicle form fits on one screen, and the settings and
  wheel sheets line up on one edge.
- **Motorcycles** are no longer offered tyre rotation: front and rear tyres
  differ and are never swapped.
- **Pickers** have proper titles: "Which wheel is … on?" and "Which sensor is
  on the spare?".

## 0.3.0

First public release.

- Live pressure and temperature from JK Tyre Treel TPMS sensors
- Cars with or without a spare, and motorcycles; several vehicles at once
- Front and rear targets with lopsided warning bands
- Your own vehicle photo on the home screen
- No internet permission, no account
