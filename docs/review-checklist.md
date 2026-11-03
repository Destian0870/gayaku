# Mid-project review checklist

Working record for the Week 8 review (`jti-polinema` codelab: Mid Project Review & Code Review).
Every line states what was run and what it produced; an unchecked box is a real gap, not a wish.

Last measured: 2026-11-03, Flutter 3.47.2 (stable), on the local `main` (47 commits ahead of
`origin/main`).

## The three machine checks

| Check | Command (from `flutter_app/`) | Result | Detail |
| --- | --- | --- | --- |
| tests | `flutter test` | **PASS** — 60 tests, 0 failures | `All tests passed!` |
| format | `dart format --output=none --set-exit-if-changed lib test` | **FAIL** — 6 of 40 files | the six files below are unformatted |
| analysis | `flutter analyze lib test` | **FAIL** — 3 issues (all `info`) | `deprecated_member_use`: `activeColor`, `lib/screens/profile_screen.dart:173`, `:268`, `:278` |

The six unformatted files are exactly the ones being edited for the theme refactor:
`favorites_screen.dart`, `login_screen.dart`, `outfit_detail_screen.dart`, `profile_screen.dart`,
`register_screen.dart`, `theme/app_theme.dart`. Everything else in `lib/` and `test/` is formatted.

`activeColor` was deprecated after Flutter 3.31 in favour of `activeThumbColor`; three switches in
`profile_screen.dart` still use it.

CI (`.github/workflows/ci.yml`) runs these three checks on every push and pull request. **It is red
today**, by design: the two rows above have to go green before a PR is ready for review.

## Git flow

| Item | State |
| --- | --- |
| remote branches | `main` only |
| `develop` | **missing** — the codelab's model targets `develop` for PRs; this repository has always PR'd into `main` |
| local branches | `main`, `feat/home-nav-refresh` (stale, from before the thesis work), `feat/merged-18-class-dataset` (47 commits, not pushed) |
| pull requests | #1–#10 all closed, 0 open |
| direct commits to `main` | the 47 local commits are direct; `AGENTS.md` asks for branch + PR |

`main` is 7 commits behind `origin/main` (PR #9 and #10 from a teammate are merged there but not
here). Reconciling that needs a merge that touches `navigation.dart` and `wardrobe_screen.dart`,
which both sides changed.

## Untracked files that need a decision

| Path | Why it is untracked | Decision needed |
| --- | --- | --- |
| `AGENTS.md` | restored from a stash, waiting for the owner's review | commit it (it is the working agreement) or keep it local |
| `design.md` | same | same |
| `README.md` (modified) | the design section was reworked | commit or revert |

Ignored on purpose: `Clothes_Dataset/` (1.4 GB of training photographs, `docs/adr/0007`),
`ml_workspace/data/` (downloads and split manifests), `yolov8*.pt` and `runs/` (Ultralytics
checkpoints and run output), `build/`.

## Structure

The app is organised by kind, not by feature: `lib/screens/`, `lib/widgets/`, `lib/models/`,
`lib/logic/`, `lib/state/`, `lib/theme/`. The codelab's Week 7 target is feature-first with a
`presentation → domain ← data` dependency rule; this repository instead records its own rules in
`AGENTS.md` (plain `Navigator`, `StatefulWidget`, `ValueNotifier`, every bottom-nav destination in
`lib/navigation.dart`, all colours in `lib/theme/app_theme.dart`).

Adopting feature-first would move nearly every file and is a separate decision, not a tidy-up. What
this pass did enforce is the part both models agree on: one direction of dependency (widgets do not
reach into storage), colours only from the theme, and generated files that stay generated.

## Done when

- [x] `flutter test` green
- [ ] `dart format --set-exit-if-changed lib test` clean
- [ ] `flutter analyze lib test` clean
- [x] CI exists and runs all three
- [x] no untracked file left undecided (three decisions listed above, owner's call)
- [x] review documents in `docs/` (`review-checklist.md`, `ai-review-vs-keputusan.md`)
- [ ] at least one small PR merged through review on a branch
- [ ] `README.md` states the mid-project status and how to run the app
