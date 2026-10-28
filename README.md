<p align="center"><img src="docs/artwork/banner.png" alt="BeamJoy-Revived: Motorsport Expansion" width="800"></p>

**A motorsport layer for [BeamJoy-Revived](https://github.com/foodcache3/BeamJoy-Revived) on BeamMP:** Forza Motorsport-style
car classes and Performance Index, a full upgrade workshop for Automation cars, race control and a
living track: rubbered racing line, marbles and track temperature.

> **Open beta.** Expect changes between versions; see [CHANGELOG.md](CHANGELOG.md). What's next is
> in [ROADMAP.md](ROADMAP.md). Bugs, questions and race nights: **[join the Discord](https://discord.gg/m6urHk6EAK)**.

Created by Sillyw0rld.

**2.32 beta:** race weekends on every BJR 2.0.1+ (classic mode without race phases), plus build-to-class presets, PI estimates, automatic car rating and seven challenge types.
See [everyday use](docs/distribution/USAGE.md#drivers-crews-and-seasons-227).

## How it started
BJR:ME started as something I built for myself and my friends. We race Automation cars on our own
BeamMP server most weekends, and I wanted a more curated racing experience than free-for-all
lobbies: cars grouped into fair classes, real upgrade paths like in Forza, proper race procedures,
and a track that changes as you drive on it. It began as a small race-preparation window and grew
from there, one race night at a time, into the expansion it is now. I'm sharing it so other servers
can race the same way.

   -Sillyw0rld

## What it does

### Car classes and Performance Index (PI)
![Vehicle selector with class and PI badges](docs/screenshots/vehicle-selector-pi.webp)
*Every Automation and BeamNG car gets a class and Performance Index in the vehicle list (PI values
in this screenshot come from an earlier build, before the class curve).*

- **Classes E, D, C, B, A, S, R, P and X with a 100–999 PI,** on Forza Motorsport's class bands. Each
  class is progressively harder to reach: road cars climb easily, super and hypercars climb slowly
  through R and P, and X is reserved for extreme builds.
- **Calibrated ratings:** PI comes from a lap-time model of the car's physics (acceleration, braking
  and cornering). Stock ratings are calibrated against cars measured in game; upgrades are rated by
  how much they change the car.
- **Parts change PI, tuning never does** (as in Forza). Race parts that unlock tuning carry a small,
  visible "tuning potential" bonus.
- Ratings show in the vehicle selector, on the grid, in the race HUD and in results.

### Upgrade workshop
![Upgrade workshop: drivetrain conversion with performance figures](docs/screenshots/upgrades-workshop.webp)
![Engine dyno in the upgrade workshop](docs/screenshots/upgrades-dyno.webp)

**Automation cars** get a full Forza-style upgrade path, generated on the server for the cars it has:
- **Tyres:** compounds from road to race slicks (KTS-aware), width −20 to +40 mm on a matching rim.
- **Aero kits, weight reduction (Street / Sport / Race), brakes** (Sport / Race).
- **Engine:** intake, exhaust, ECU, camshaft, forged internals, displacement, turbochargers and
  superchargers, intercooler, oil cooler and **radiators** (sized so a turbo-converted car stops
  overheating on a hot grid), with a live **dyno**.
- **Engine conversions** from a curated donor-engine lineup, screened against each car's engine bay,
  and **drivetrain conversions** (FWD / RWD / AWD). The donors are included.

**BeamNG's own cars** can fit their compatible factory parts (engines, gearboxes, suspension,
brakes, wheels and tyres, wings), found through BeamNG's own part-slot compatibility. They also get
BJR:ME's own upgrades: **weight-reduction stages** (33 models), **Sport and Race brakes** (31 models)
and, in beta, **tyre compounds and widths** (Covet, ETK 800, D-Series and SBR; their tyre PI is still being refined). These are separate add-on parts built from the cars' factory parts; the factory
files themselves are never modified.

Every section of the workshop and of **Setup** has a short guide with a picture: what the part or
setting does and how to use it.

### Setup
![Setup with gearing graph](docs/screenshots/setup-gearing.webp)

- Suspension, aero, brakes, differential, fuel and gearing, with permissions that follow the fitted
  parts (Race parts unlock their sliders; final-drive and gear-ratio permissions are separate).
- A gearing graph next to the sliders, performance figures, and saved setups.

### Motorsport settings
![Race rules: upgrade caps](docs/screenshots/race-rules-upgrades.webp)

The last tab of the window. Everyone can read it; changing it needs permission.
- **Permissions by BeamJoy group:** who may start race weekends, edit rules and track settings, and
  use race control.
- **Race rules** per race or as server defaults: eligibility (classes, PI min / max), start and grid,
  track limits and flags, driving aids, tuning limits, and **upgrade caps**: engine parts level,
  forced induction, engine and drivetrain conversions, tyre compound and width, weight reduction,
  brakes, radiators, aero, nitrous, and factory-only rows. Parts a race does not allow are locked in
  the workshop with the reason, and Ready is refused while a fitted part breaks a cap.
- **Track settings:** the rubbered racing line and marble sizes (close and far), wind and gusts, and the weather (clouds, fog, rain,
  air temperature by time of day).

### A living track
![Track settings: rubber, wind and weather](docs/screenshots/track-settings.webp)

- **Rubbered racing line** that builds up lap by lap and adds grip, plus **marbles** off the line:
  rubber pieces you can see coming from 80 m (close and far size set in Track settings).
  Driving through them costs a little grip, and your tyres pick some up for a few corners (a
  "Marbles on tyres" pill shows it). Every pass thins them out a little for everyone.
- **Track temperature** from air temperature, sun, clouds and rain, with heat soak; fixed by race
  rules when needed.
- **Weather** through BeamJoy-Revived's weather sync, in both directions: set it in Track settings or
  in BeamJoy-Revived's weather panel and both show the same. Gusting wind is worked out the same on
  every game.
- Oil, coolant and fuel spills come from the [Fluid Spill Mod](https://www.beamng.com/resources/fluid-spill-mod.38681/) by Dirt 2, a separate mod with its
  own BeamMP server plugin. It works alongside BJR:ME and is not included.

### Tyre simulation
Works with an **unmodified** [Kagoni Tyre Simulation (KTS)](https://www.beamng.com/resources/39079/) through its
public functions: the true tyre type of Automation cars, track temperature, and per-wheel grip from
the rubbered line. KTS is optional and installed separately.

### Built on BeamJoy-Revived's plugin API
BJR:ME adds nothing to BeamJoy-Revived's folders and changes none of its files. Everything goes
through BeamJoy-Revived's official plugin API and its saved race files (read only), so a BeamJoy-Revived
update never removes anything of BJR:ME's. At start, the server log lists every API feature BJR:ME
uses, by feature, with ✓ or ✗.

### Race weekends
![Race weekend tab](docs/screenshots/race-weekend.webp)
<!-- screenshot: docs/screenshots/race-weekend.webp -->
<!-- Retake the current weekend image with the phase-enabled BJR build. -->

Practice, qualifying and race share one BJR event and lobby. BJR owns the clocks,
grids and penalties; only the final race counts toward statistics and progression.
Choose optional timed phases and qualifying/reverse/handicap grids in Race weekend.
With released BJR 2.0.1 (no race phases) weekends run in **classic mode**: BJR:ME
times practice and qualifying, and the race is a normal BJR lobby with the
qualifying grid. A BJR build with phases switches to full weekends automatically.
BJR's upcoming pit system is not part of BJR:ME yet.

### Rivals: time attack against server-verified laps
Choose Challenges for class boards and the weekly target, then chase a verified
lap with a see-through ghost. The server checks timing, gates and the car it received.
Medals start provisional until another eligible driver sets a verified time; they
are judged again before paying XP. Notices tell you when a rival beats your time,
with a button to chase their current ghost. Factory BeamNG cars are supported too.
<!-- screenshot: docs/screenshots/challenges.webp -->
<!-- screenshot: docs/screenshots/rivals-ghost.webp -->
<!-- screenshot: docs/screenshots/rival-notice.webp -->

### Driver progression
Earn automatic licences, XP and levels through counted races and verified Rivals.
Drivers shows requirements, achievements with their rarity and earned titles.
A post-race card explains the XP you gained, new achievements and licence changes;
it closes without taking driving focus. Personal pop-up switches are in Grid.
<!-- screenshot: docs/screenshots/reward-card.webp -->

### Crews and seasons
Create a crew, invite friends and race for driver and crew standings. Seasons offers
Drivers | Crews tables, Hall of Fame and history, separate from Championships.
Owners can choose the season length and scoring; monthly repeating seasons work
without setup. Click a driver's name for their progress, medals and racing record.
<!-- screenshot: docs/screenshots/seasons-crews.webp -->
<!-- screenshot: docs/screenshots/driver-card.webp -->

### Race HUD
A small standings tower and timing panel show BJR's positions, sectors, penalties
and phase clock, with official intervals plus local ahead/behind time and distance
estimates where available. Grid has personal HUD, fuel display and transparent
proximity-radar controls. These displays do not change BJR's race results.
<!-- screenshot: docs/screenshots/race-hud.webp -->

## Requirements
- **BeamNG.drive 0.40** and a BeamMP server. For **server-verified Rivals**, use
  **BeamMP Server 3.9.4 or newer** providing server time, raw vehicle positions and
  received vehicle configurations (`MP.GetServerTimeMS`, `MP.GetPositionRaw`,
  `MP.GetPlayerVehicles`). Without these functions verified runs cannot start.
- **BeamJoy-Revived installed separately.** The BJR:ME bridge reports **2.0.1+**
  and checks available API features. Released BJR 2.0.1 runs **classic weekends**
  (BJR:ME-timed practice/qualifying, penalties added by BJR:ME); a BJR build with
  race phases gives full single-event weekends. The startup log says which.
- **Windows x64 or Linux x64** for the standalone parts generator; no Python
  installation is needed for normal server use.

### Optional mods
Other people's mods that BJR:ME works with when they're installed on the server. They're not
included: download them from their pages, or type `bjrme get kts` (or `fluidspill`, `ddp`) in the
server console and the next start installs it. The server reminds you at startup about any that
are missing; `bjrme optional ignore <mod>` stops the reminder for one you don't want.
- [Kagoni's Tyre Simulation](https://www.beamng.com/resources/kagoni%E2%80%99s-tyre-simulation.39079/)
  by Kagoni: tyre heat and wear. BJR:ME's tyre compounds, rubbered-line grip and track temperature
  work through it.
- [Fluid Spill Mod](https://www.beamng.com/resources/fluid-spill-mod.38681/) by Dirt 2: oil, coolant
  and fuel spills. Install its client zip and its own BeamMP server plugin.
- [Dynamic Damage Particles](https://www.beamng.com/resources/dynamic-damage-particles.38670/) by
  samllea1: debris from crashes.
- Automation car mods: the cars BJR:ME builds upgrades for.

## Two editions
Both editions are the same expansion with the same conversion tool. They differ only in the donor
cars that engine and drivetrain conversions are built from:
- **Play** (`bjrme-play-windows-x64.zip` or `bjrme-play-linux-x64.zip`): for servers that just want
  to race. My 18 engine donors and the FWD / RWD / AWD drivetrain donors are included, so engine and
  drivetrain conversions work out of the box.
- **Custom** (`bjrme-custom-windows-x64.zip` or `bjrme-custom-linux-x64.zip`): for servers that want
  their own lineup. No donors are included; you add your own Automation exports to
  `BJRME-donors/custom/engines/` and `custom/drivetrains/`.
  Drivetrain conversions need one FWD, one RWD and one AWD donor.

You can switch later: copying the Play edition's `BJRME-donors/default` folder into a Custom
install adds my donors to yours.

## Installation
1. Install BeamJoy-Revived on your BeamMP server.
2. Download the edition you want and extract it into your **BeamMP server folder**. It adds
   `Resources/Client/BJR_RacePrep.zip`, `Resources/Server/RacePrep/`, the start scripts and the
   `BJRME-donors` folder. No BeamJoy-Revived file is added or changed.
3. Start with `start-bjrme-server.cmd` (Windows) or `./start-bjrme-server.sh ./BeamMP-Server`
   (Linux). A preflight generates and checks the upgrade parts for new or changed cars, then starts
   BeamMP. When nothing changed, the parts are kept as they are. If your host starts BeamMP itself,
   start it normally: BJR:ME builds the parts in the background and asks for `reloadmods`.

**Donors (Play edition):** 18 engines and the FWD / RWD / AWD drivetrain sources, my own Automation
exports, without meshes, audio or pre-generated parts. In either edition, add your own Automation
exports in `BJRME-donors/custom/engines/` or `custom/drivetrains/`, then restart with the start
script.

See [all documentation](docs/README.md), the [current status](docs/STATUS.md), the
[installation guide](docs/distribution/INSTALLATION.md), the
[usage guide](docs/distribution/USAGE.md) (everyday start, donors, console update commands) and the
[custom donor guide](docs/distribution/CUSTOM-DONORS.md).

How it was built and tested: [PI and classes](docs/methodology/PI-AND-CLASSES.md),
[upgrades and conversions](docs/methodology/CONVERSIONS.md), [testing](docs/methodology/TESTING.md) and
[how it came together](docs/AUTHORSHIP.md).

## Contributing
Found a bug or have a question? Report it on the [Discord](https://discord.gg/m6urHk6EAK). Contributions are welcome: please
read [CONTRIBUTING.md](CONTRIBUTING.md) and [GOVERNANCE.md](GOVERNANCE.md) first. Performance and
rating changes need reproducible evidence.

## Credits
| Project / people | Contribution |
| --- | --- |
| [BeamJoy-Revived — Captain Nugget / foodcache3 and contributors](https://github.com/foodcache3/BeamJoy-Revived) | Multiplayer framework this expansion runs on. BJR:ME works through BJR's plugin API and adds nothing to BJR's own folders. |
| [BeamJoy — my-name-is-samael and contributors](https://github.com/my-name-is-samael/BeamJoy), including [BeamJoy-sandbox](https://github.com/my-name-is-samael/BeamJoy-sandbox) | Original project and upstream lineage continued by BeamJoy-Revived. |
| [Kagoni Tyre Simulation — Kagoni](https://www.beamng.com/resources/kagoni%E2%80%99s-tyre-simulation.39079/) | Optional tyre simulation; integrated unmodified through its public interfaces. Installed separately. |
| [Fluid Spill Mod — Dirt 2](https://www.beamng.com/resources/fluid-spill-mod.38681/) | Optional oil, coolant and fuel spills, with its own BeamMP server plugin. Installed separately; BJR:ME contains none of its code. |
| [Dynamic Damage Particles — samllea1](https://www.beamng.com/resources/dynamic-damage-particles.38670/) | Optional crash debris. Its debris technique inspired BJR:ME's tyre debris; no code is shared. Installed separately. |
| [BeamMP team and contributors](https://beammp.com/) | Multiplayer platform and server/client transport. Installed separately. |
| [BeamNG GmbH and the BeamNG.drive team](https://www.beamng.com/) | Game, vehicle physics, native vehicles/parts and modding interfaces. Installed separately. |
| [Camshaft Software / Automation team](https://automationgame.com/) | Vehicle/engine design and BeamNG export tools used to create the Automation cars and donor exports. |
| Vehicle and mod authors | The installed cars from which compatible upgrades are generated. Their models, sounds and source assets remain their work. |

Design inspiration, development tools and more: [CREDITS.md](CREDITS.md). Legal notices: [NOTICE](NOTICE).
