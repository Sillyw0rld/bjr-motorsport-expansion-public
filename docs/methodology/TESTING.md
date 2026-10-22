# How changes are tested

BJR:ME is tested in four layers before a change reaches a server. Each layer catches what the one
before it can't.

## 1. Offline test suites
About 140 automated test files (Lua and Python) run on every change, without the game:
- the rating model against fixed reference cars, so a change can't silently move existing ratings;
- the parts generator, conversions and the incremental updater, against real car exports;
- the server plugin's logic: race weekend, permissions, upgrade caps, results, rating sync and the
  BeamJoy-Revived API;
- the client: shop and setup rules, HUD data, rubber and marbles, network messages;
- release packaging and syntax checks of every Lua and Python file.

A change ships only when the full suite passes. Tests stay with the change that made them: a fixed
bug gets a test that would have caught it.

## 2. Isolated game instance
Anything that depends on the game's physics or rendering is checked in a separate game instance with
its own profile, on a flat test map, controlled remotely, so nothing touches a player's own game or a
live server:
- **measurements** for ratings (see [PI-AND-CLASSES.md](PI-AND-CLASSES.md)), with quality gates that
  reject bad runs;
- **conversions and parts:** driven, inspected and saved and reloaded (see
  [CONVERSIONS.md](CONVERSIONS.md));
- **visual checks** with screenshots. The marbles, for example, were placed as a realistic band and
  photographed from the driver's eye and from above; that caught things no unit test could, like
  pieces running out of drawing budget a few metres into a band.

## 3. The server's own report
When the server starts, BJR:ME reports each BeamJoy-Revived feature it hooked into (race events,
grid order, weather, players, menu pages) with a ✓ or ✗, so a broken integration is visible at once.

## 4. Racing
Finally, it's raced on my own server with friends. Every new version is installed with a backup of
the files it replaces and is verified file by file; anything that feels wrong on track goes back
through the layers above.

Found a problem? Open an issue with what happened and how to reproduce it. Changes to ratings need
reproducible evidence; see [CONTRIBUTING.md](../../CONTRIBUTING.md).
