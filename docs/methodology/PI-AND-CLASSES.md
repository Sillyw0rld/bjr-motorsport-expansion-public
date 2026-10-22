# How the PI and classes were built

This is how I arrived at BJR:ME's Performance Index (PI) and car classes, and how I tested them.
It describes the method and the checks, not the formula itself.

## The goal
One number from 100 to 999 and a class from E to X for any car on the server, whether it's an
Automation export or one of BeamNG's own cars, stock or upgraded. Two cars with the same PI should be
about equally quick around a typical circuit, so a class makes for close racing. That is the idea of
Forza Motorsport's PI, and the target I set.

## Step 1: rate a car from its own data
Each car is rated by a virtual lap built from what the game knows about it: mass and weight
distribution, engine torque and gearing, tyres, aerodynamics and brakes. The lap mixes straights
(acceleration and top speed), braking zones and corners of different speeds. Faster laps mean a
higher PI, on a scale where the same percentage of lap time is worth the same PI anywhere.

Rules I set for what counts:
- **Only parts change PI, never tuning.** Moving a slider in Setup never changes your rating, as in
  Forza. Race parts that unlock tuning carry a small, shown "tuning potential".
- **A factory configuration counts as built.** If BeamNG ships a config with more boost or a higher
  rev limit, that is part of the car, so it counts. The player's own tuning still doesn't.
- **The tyre the simulation really uses.** Ratings use the tyre type the tyre simulation actually
  applies to each car (road, sport, semi-slick or slick), not a guess from the car's name.

## Step 2: measure real cars in the game
A model is only as good as what it's checked against, so I measured cars in game with my own
instrumented test procedure: an isolated game instance on a flat test map, running each car through
the same set of tests:
- **Acceleration** from standstill to top speed, keeping the best curve across runs.
- **Braking** from several speeds.
- **Cornering** on a circle at increasing speeds, for grip at low and high speed.

Quality gates throw out bad runs: a car that rolled, was damaged, spun at once or ran with the wrong
setup is rejected, and every result is tied to the exact car, configuration and game instance that
produced it. Cars that can't be measured fairly (some spin on the cornering test at once, some
utility vehicles are too slow for it) are rated by the model and flagged in game.

So far that's **58 Automation cars** and **92 BeamNG factory configurations** measured. Measured cars
use their measured rating directly.

## Step 3: fit, then check blind
The model's constants were fitted to the measured cars. A change to the model is only accepted if it
improves a **blind check**: the cars are split into groups, the model is fitted without one group and
then rates that group, and this is repeated for every group. A model that only fits the cars it has
seen doesn't pass.

What that changed over the versions:
- Weight transfer and suspension softness came in when blind checks showed stiff, light cars were
  over-rated.
- BeamNG's own cars got their own grip, braking and aerodynamics: every factory configuration's
  downforce and drag was measured directly in game (856 configurations), instead of assumed.
- Some ideas were rejected because they made the blind check worse, even when they fitted better.
- Extras were removed when measurements didn't support them. For example, the Race body stage used
  to add a small PI bonus on top of the lower weight; measuring stripped cars showed the model
  already counted the weight correctly, so the bonus went.

## Step 4: upgrades
An upgraded car is rated as its stock rating plus the model's estimate of what its parts change. The
model's error for that particular car then mostly cancels out, because it's the same on both sides.
Every generated upgrade part (tyres, aero, brakes, engine stages, weight stages, conversions) goes
through the same path, so a car's class always reflects what's fitted.

## Step 5: the class curve
With plain PI, fast stock cars and upgraded cars piled up at the top: 27 of 67 fully upgraded
Automation cars hit 999 X. Like Forza, I added a smooth output curve that leaves the lower classes as
they were and makes each higher class progressively harder to reach. Now no car reaches X on its own
engine; X is for extreme builds.

| Class | PI |
|---|---|
| E | up to 300 |
| D | 301–400 |
| C | 401–500 |
| B | 501–600 |
| A | 601–700 |
| S | 701–800 |
| R | 801–900 |
| P | 901–998 |
| X | 999 |

## What's still being checked
- **Same PI, same lap time.** Racing Automation and BeamNG cars rated at the same PI on a real
  circuit, to confirm the classes are fair across both kinds of car.
- **Tyre compounds on every car.** Re-measuring the compound ladder per car instead of using an
  average.
- **BeamNG cars are harder to predict than Automation cars**, so measured factory configurations
  stay the reference and more are added over time.

Changes to ratings need reproducible evidence: see [CONTRIBUTING.md](../../CONTRIBUTING.md).
