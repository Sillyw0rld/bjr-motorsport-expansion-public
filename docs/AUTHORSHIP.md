# Authorship and development history

I'm **Sillyw0rld**, and BeamJoy-Revived: Motorsport Expansion (BJR:ME) is my project, built in 2026
as an expansion for BeamJoy-Revived. I started it because I wanted a more curated racing experience
for me and my friends on our own BeamMP server: fair classes, Forza-style upgrades, proper race
procedures. It grew from a small race-preparation window into the full expansion.

This document records the two parts of BJR:ME I'm most proud of, that I designed them, and when. It
describes *what* they are and *how they're structured*. My calibration data, measurement rig and
fitting tools are not part of this repository.

---

## 1. Performance Index (PI) classification and calibration system

**Designed by me, October 2026.**

### What it is
A Forza Motorsport-style rating for BeamNG.drive cars: one number from 100 to 999 and a class from
E to X, so that cars of very different kinds (Automation exports and BeamNG's own cars, stock or
modified) can race in fair classes.

### Architecture
- **A physics-based lap-time model.** Each car's rating comes from a virtual lap computed from its
  own data (mass, weight distribution, engine curves and gearing, tyres, aero and brakes), as
  acceleration, braking and cornering capability. Lap time maps to PI on a logarithmic scale, so a
  given percentage of lap time is worth the same PI everywhere on the scale.
- **Calibration against in-game measurement.** I calibrated the stock ratings against cars I
  measured in game with my own instrumented test procedure, covering both Automation exports and BeamNG factory
  configurations. Formula changes are accepted only if they improve a **blind check**, rating
  cars that were not used to fit them.
- **Anchored upgrades.** A modified car is rated as its measured stock rating plus the model's
  estimate of what its parts change, so the model's per-car bias cancels out.
- **Parts, not tuning.** Only fitted parts change PI. Race parts that unlock tuning carry a small,
  shown "tuning potential" share, as in Forza.
- **Class progression.** A smooth output curve makes each class progressively harder to reach (light
  from D upward, steep in R and P), with X reserved for extreme builds.
- **Tyre-simulation aware.** Measurements and ratings use the true tyre type the tyre simulation
  applies to each car.

### Milestones
| Date (2026) | Step |
|---|---|
| Oct 13 | Rating formula and first calibration integrated into the race tools |
| Oct 15 | Formula v6: weight transfer, suspension softness and refitted acceleration, with a 5-fold blind check |
| Oct 16–17 | Ratings for BeamNG factory cars (formula v7) and probed aerodynamics for every factory configuration |
| Oct 17–18 | Automation fleet re-measured with the true tyre type; stale upgraded ratings recomputed against the new stock values |
| Oct 19 | Forza Motorsport-style class progression (output curve) |
| Oct 21 | Upgrade caps per race (engine level, induction, conversions, tyres, weight, brakes) on top of the PI limit |

---

## 2. Automation vehicle conversion architecture

**Designed by me, October 2026.**

### What it is
A system that gives supported Automation car exports a Forza-style upgrade path,
without editing the car mod itself. Export structure and compatibility determine
which upgrades and conversions can be offered.

### Architecture
- **Generated, additive parts.** Every upgrade is a real BeamNG part generated from the car's own
  export and plugged into its existing slots: tyre compounds and widths (the rim widens with the
  tyre), aero kits, weight-reduction stages, brakes, engine stages, forced induction, coolers and
  radiators. The original car files are never modified.
- **Physically grounded values.** Compound characteristics come from a library of real Automation
  tyres. Wider tyres gain grip through load sensitivity, as real tyres do. Engine parts work through
  the export's own engine data. Radiators scale the core and fan, sized from measured overheating
  cases.
- **Engine conversions:** a curated lineup of donor engines, verified by checksum, screened against
  each car's engine bay dimensions and converted to the car's fuel system.
- **Drivetrain conversions:** FWD, RWD and AWD layouts from donor drivetrains, with layout-correct
  mass, keeping the fitted engine, gearbox and final drive.
- **Common server-generated parts.** The launcher generates and validates parts before BeamMP
  starts, using source/output hashes to reuse unchanged work and regenerate affected cars.
  Players download the generated client mod when joining. Stop/restart and reconnect after
  changing cars or donors; the public path does not write the live ZIP or issue `reloadmods`.
  Common files and server rules do not independently verify client-reported physics.
- **Rated like everything else.** Every generated part feeds the PI system, so an upgraded car's
  class reflects its parts.

### Milestones
| Date (2026) | Step |
|---|---|
| Oct 13 | Upgrade parts for any Automation car: tyres, aero kits, engine packages and induction |
| Oct 14 | Brake upgrades and race ECU |
| Oct 15 | Weight-reduction stages as real parts |
| Oct 17 | Tyre width upgrades widen the rim; real KTS tyre types for Automation cars |
| Oct 18 | Radiators; engine conversions and drivetrain conversions |
| Oct 19 | Automatic, add-only parts generation at server start |
| Oct 20 | Works with an unmodified tyre simulation (public functions only) |
| Oct 21 | Bundled conversion donors from my own exports; incremental, checked parts generation before the server starts; BeamNG factory parts in the workshop |

---

## Development notes
- BJR:ME is a solo project: no team, no studio. I came up with it, designed every system, set the
  rating methodology, ran the in-game testing and calibration, decided what's realistic and fair,
  and reviewed and approved every change before it went to my server.
- I used AI coding assistants (Claude, Codex, Gemini, SWE-2 and GLM-5.3) as tools to write and refactor a lot of the
  code to my specifications, the same way other developers use them today.
- I keep the full development history in my private repository. Public releases start from a clean
  history.
