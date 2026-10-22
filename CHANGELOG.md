# Changelog

Versions: v2.<minor>.<patch>.<build> (build = number of commits in this repository).

## 2.16.0 — BJR:ME upgrades for BeamNG cars
- **BeamNG's own cars get BJR:ME upgrades**, in both editions: weight-reduction stages (Street
  −4 %, Sport −7 %, Race −15 %) for 33 models and Sport / Race brakes for 31 models.
- **Tyre compounds and widths for BeamNG cars, in beta,** for the Covet, ETK 800, D-Series and SBR.
  Their PI is still being tuned and currently reads about 30 PI high; the workshop says so.
- Every part was spawned on BeamNG 0.40 before release: no broken beams, no fuel leaks, the right
  mass.

## 2.15.12 — first public release (open beta)
The first public release of BeamJoy-Revived: Motorsport Expansion, for BeamNG.drive 0.40,
BeamMP 3.9 and BeamJoy-Revived 2.0.

**Classes and Performance Index**
- Classes E to X with a 100–999 PI, Forza Motorsport style, for Automation and BeamNG cars. Each
  class is progressively harder to reach; X is for extreme builds.
- Ratings from a lap-time model of each car, calibrated against cars measured in game. Parts change
  PI; tuning never does. Race parts that unlock tuning show a small "tuning potential".
- PI and class in the vehicle selector, on the grid, in the race HUD and in results.

**Upgrade workshop**
- Automation cars: tyre compounds and widths, brakes, weight-reduction stages, aero kits, engine
  stages and individual engine parts, forced induction, coolers and radiators, generated on the
  server for the cars it has. The original car mods are never changed.
- Engine conversions from 18 donor engines, checked against each car's engine bay, and FWD / RWD /
  AWD drivetrain conversions.
- BeamNG cars: their compatible factory parts.
- Engine dyno with the curve before your last change, performance figures, Apply / Undo and saved
  setups.

**Setup**
- Suspension, aero, brakes, differentials, fuel and gearing, with permissions that follow the fitted
  parts, a gearing graph and performance estimates.

**Racing**
- Race weekend: practice, then qualifying, then the race, with announcements and live session
  standings with sectors.
- Grids from qualifying, reversed top N or handicap; start lights and false starts, track limits,
  penalties and flags.
- Race HUD at the top of the screen: standings tower, timing box and gap strip.
- Results and history, championships, driver statistics and a safety rating.

**Motorsport settings**
- Permissions by BeamJoy-Revived group; race rules per race or server-wide (eligibility, start and
  grid, track limits, aids, tuning and upgrade caps); track settings (rubber, marbles, wind and
  weather).

**A living track**
- A rubbered racing line that builds up lap by lap, marbles off the line that cost a little grip and
  stick to your tyres for a few corners, track temperature, wind and weather synced through
  BeamJoy-Revived.

**Server**
- Play and Custom editions, a standalone parts generator for Windows and Linux (no Python needed)
  that builds parts before the server starts, and console commands for updates and optional mods
  (`bjrme help`).
- Build 2: update checks and optional-mod downloads work on every Linux distribution, not only
  Ubuntu-based ones.
