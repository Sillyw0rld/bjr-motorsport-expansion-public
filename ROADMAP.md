# Roadmap

What I'm working on next and what's planned for BJR:ME. It's an open beta, so priorities can change
with what you report and what we find racing. Nothing here has a fixed date.

## Next up
- **Open beta feedback.** Fixing what players and server owners report, first on other people's
  servers and setups.
- **Race nights on my server** with everything in this release: race weekends, the race HUD, upgrade
  caps, marbles and the rest.
- **Smaller Linux downloads.** The Linux generator carries debug information it doesn't need;
  removing it should bring the Linux downloads close to the Windows size.
- **The last new screenshots:** the race HUD, the vehicle selector with class / PI badges, and the
  before / after engine dyno.

## Planned
- **More upgrades for BeamNG's own cars.** Weight stages, brakes and (in beta) tyres are in. Next:
  tyre PI accuracy and more models for tyres, then aero kits (they need visible wings and a fit per
  car) and engine stages. See [BeamNG cars in the workshop](docs/distribution/NATIVE-FACTORY-PARTS.md).
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
- **X class is meant to be rare.** It's reserved for extreme builds, mostly prototypes; most cars top
  out in P.
- Built and tested on BeamNG.drive 0.40, BeamMP 3.9 and BeamJoy-Revived 2.0. Other versions may need
  changes.

## Ideas and requests
Have an idea or found a problem? Tell me on the [Discord](https://discord.gg/m6urHk6EAK). Changes to
ratings or car performance need reproducible evidence, see [CONTRIBUTING.md](CONTRIBUTING.md).
