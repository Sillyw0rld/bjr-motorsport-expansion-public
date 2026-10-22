# Roadmap

What I'm working on next and what's planned for BJR:ME. It's a pre-release, so priorities can change
as we race and find what needs fixing. Nothing here has a fixed date.

## Next up
- **Race-night check of the new release.** The new window, Motorsport settings, race weekend, race
  and session HUDs, the upgrade caps and the marbles, raced on my server.
- **The last new screenshots:** the race HUD, the vehicle selector with class / PI badges, and the
  before / after engine dyno.
- **The public repository**, with this README, the release archives and the update checker
  pointing at it.

## Planned
- **Generated upgrades for BeamNG's own cars.** Their factory parts are in the workshop now.
  Generated tyre compounds and widths, weight stages, aero kits and brakes like the Automation cars
  have are being tested and need to rate correctly before they ship. See
  [BeamNG cars in the workshop](docs/distribution/NATIVE-FACTORY-PARTS.md).
- **Tyre compound accuracy in PI.** Re-measure the full compound ladder (road to race slicks) on
  every Automation car with its true tyre type, so a compound upgrade is worth the right PI on each
  car instead of an average.
- **Same-PI track test.** Race Automation and BeamNG cars rated at the same PI on a real circuit, to
  confirm that equal PI means equal lap times across both kinds of cars.
- **More from BeamJoy-Revived's API.** Asking its author for a way for a plugin to open the race
  lobby (so a race weekend can go from qualifying to the lobby by itself) and to show plugin labels
  (class / PI) in BeamJoy-Revived's own race HUD.
- **First stable release**, once the beta has run on more servers than mine.

## Known limitations
- **Cars added while the server runs get their parts at the next start** (the start script's
  preflight builds them). Players already on the server need to rejoin to receive new parts; this is
  how BeamMP delivers changed mods.
- **BeamNG factory parts and the upgrade caps:** a factory engine swap counts as an engine conversion
  and a factory turbo or supercharger as forced induction; factory gearbox, suspension and tyre parts
  follow their factory-only rules. Factory engine parts have no Street / Sport / Race level.
- **Engine conversion upgrades were renamed** in this release (each conversion has its own part
  names). A saved setup with an engine conversion and its upgrades needs those upgrades fitted
  again once.
- **X class is meant to be rare.** It's reserved for extreme builds, mostly prototypes; most cars top
  out in P.
- Built and tested on BeamNG.drive 0.40, BeamMP 3.9 and BeamJoy-Revived 2.0. Other versions may need
  changes.

## Ideas and requests
Have an idea or found a problem? Open an issue. Changes to ratings or car performance need
reproducible evidence, see [CONTRIBUTING.md](CONTRIBUTING.md).
