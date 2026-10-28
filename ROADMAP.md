# Roadmap

BJR:ME is an open beta. Priorities follow player/server reports and race-night
findings; nothing planned below has a fixed date.

## Done in the current beta

- **BJR event integration:** phase weekends share one lobby, with race-only
  results and BJR-owned timing/penalties. This needs a phase-enabled BJR build;
  released BJR 2.0.1 does not have phases.
- **Competition:** verified/class Rivals, weekly targets, lap ghosts, awards,
  presets/spec cars, live race-gap estimates, shared tunes and fuel strategy.
- **Progression:** licences, XP/levels, medals with provisional confirmation,
  achievements, titles and reward cards.
- **Crews and seasons:** persistent membership, driver/crew standings, Hall of
  Fame, history and driver cards; rival inboxes and ghost-chase buttons.
- **Smaller Linux packages and repaired updates:** unnecessary debug data is
  removed and the installer accepts the support files added with competition.

Implemented does not mean every feature is live-tested. See
[current status](docs/STATUS.md) for what still needs a real multiplayer session.

## Next up

- **Open beta feedback:** fix reports from other servers and setups.
- **Race nights on the maintainer's server:** exercise weekends on a compatible
  BJR build, the HUD, caps, marbles and the new competition/progression features.
- **Screenshots:** refresh the HUD, vehicle selector and before/after dyno; take
  the new feature shots marked in the README.

## Planned

- **More upgrades for BeamNG's own cars:** improve tyre PI and model coverage,
  then aero kits with suitable visible parts and engine stages. See
  [factory parts](docs/distribution/NATIVE-FACTORY-PARTS.md).
- **Tyre compound accuracy in PI:** measure the full compound range for each
  Automation car using its actual tyre type rather than an average.
- **Same-PI track tests:** compare Automation and BeamNG cars at the same PI on
  real circuits.
- **More native BJR HUD labels:** the existing public-API request for class/PI
  labels in BJR's own HUD remains separate from BJR:ME's replacement HUD and
  the result fields already supported. Lobby opening is implemented where the
  phase API is available.
- **First stable release:** after the beta has run on more servers.

## Known limitations

See [current status](docs/STATUS.md) for phase-build requirements, Rivals
verification limits, native tyres, data recovery and live checks. Factory
engine swaps/induction and other factory parts still follow their own upgrade
caps; they do not acquire Street/Sport/Race labels. X class remains for extreme
builds. Players reconnect to receive changed mods.

## Ideas and requests

Share ideas and faults on [Discord](https://discord.gg/m6urHk6EAK). Rating or
performance changes need reproducible evidence; see [Contributing](CONTRIBUTING.md).
