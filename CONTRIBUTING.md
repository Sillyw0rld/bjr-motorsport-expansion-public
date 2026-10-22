# Contributing to BJR:ME

Thanks for helping. This project is a racing tool: changes have to be measurably right, not just
feel right. Please read this before opening a pull request.

**Bug reports and questions** go to the [Discord](https://discord.gg/m6urHk6EAK): say what happened, your BJR:ME version (shown
in the window and the server console), the car and map, and how to make it happen again.

## The basics
- **Open an issue first** for anything larger than a small fix, so the approach can be agreed before
  you spend time on it.
- **All tests must pass:** `python3 -I tests/run.py`. Add a test for every bug you fix and every
  behaviour you add. A good test fails on the old code.
- **Keep changes focused:** one topic per pull request.
- **Never commit generated upgrade parts** (`client/vehicles/`, filled part catalogues) or anything
  taken from third-party mods. Parts are generated on each server. The compact,
  author-owned defaults in `donors/default/` are reviewed source inputs, not generated
  parts; additions need provenance, redistribution permission and maintainer approval.
- **No secrets** (BeamMP keys, server configs) and no personal paths.

## Performance changes need reproducible evidence
"It feels smoother" is not evidence. A pull request that claims a performance improvement (frame time,
spikes, server load, network traffic) must include:
1. **The scenario:** map, number of cars and players, what was happening, and how to repeat it.
2. **Before and after measurements** taken the same way: for example the expansion's frame-spike
   report, BeamNG's extension profiler, server log timings or packet sizes. Raw numbers, not only a
   summary.
3. **No regressions elsewhere:** the full test suite, and a note on anything you could not test.

Changes that trade correctness for speed must say so explicitly.

## Rating (PI) and physics changes need data
The PI system is calibrated against cars measured in game. Changes to the rating formula, its
constants, class bands, the output curve or upgrade effects must include:
- what was measured and how (cars, configurations, conditions), and
- the effect on a **blind check**, rating cars the change was not fitted on, compared with the
  current version.

A change that fits the cars it was tuned on but not unseen cars will not be merged.

## Code style
- Match the surrounding code: naming, comment density and idiom.
- Comments explain *why*, not what.
- Keep the SPDX licence line and copyright notice at the top of every source file; add them to new
  files.

## Licence of contributions
By contributing, you agree that your contribution is licensed under the project's licence,
**AGPL-3.0-or-later**, and that you have the right to submit it. Add yourself to the credits in your
pull request using your preferred public name/link and the work you contributed.
Keep upstream credits intact. If you add a dependency or permitted source asset,
record its author, source and licence in [CREDITS.md](CREDITS.md) and, where needed,
[NOTICE](NOTICE). Do not commit someone else's assets merely because they are downloadable.

## Review
The maintainer reviews and approves every merge; see [GOVERNANCE.md](GOVERNANCE.md).
