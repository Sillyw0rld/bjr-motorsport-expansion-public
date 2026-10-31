# v2.35.0 beta: engines, turbo sound and a cleaner window

This update follows the big 2.32 release. Engines now have a realistic power limit, and you can fit
twin-charged and sequential twin-turbo setups and hear them. The Motorsport Expansion window is
cleaner and easier to use. If you're coming from **2.16**, everything from the big update is
included too: see [What's new since 2.16.1](../../CHANGELOG.md#whats-new-since-2161-public-beta).

## What's new

- **Engines have a limit.** Every engine has a power potential, from its layout (four-cylinder,
  V8, V12 and so on) and its size. Upgrades fill the room left between the car's stock power and
  that potential: Stage 1 a little, Stage 3 most of it. An engine that's already near its limit
  only gets a small tune-up (+3 to +5 %). Fitting a turbo or supercharger, or a bigger
  displacement, raises the limit. Swapping in a different engine is the way to go much faster.
  Small engines with eight or more cylinders rev higher, so they keep more of their potential.
- **New induction choices:** twin-charged (a supercharger for low-down response, then a turbo
  takes over) and sequential twin turbos (a small turbo early, a big one in the mid range).
- **Turbo and supercharger sound** for the induction you fit to a car that didn't have it: turbo
  spool and hiss, blow-off when you lift (a flutter on Sport parts), supercharger whine. Cars
  with a factory turbo keep their own sound.
- **Boost gauge:** the HUD and BeamNG's boost app now show the boost of the turbo or supercharger
  you fitted.
- **Factory boost target:** the Race boost upgrade on a factory-turbo Automation engine lets you
  turn its boost up or down in Setup (it never changes PI).
- **Cleaner window:** a gear icon at the top holds your own settings (HUDs, radar, pop-ups). Start
  a race shows staff picks as cards and tells you why the lobby can't open yet. The driver card
  sits beside the page instead of covering it. Drivers, Crews, Seasons and Challenges are tidier.
- **Fixes:** heavy lag with the window open when the server had no rivals or challenges yet;
  Challenges said "End the current practice activity first" in free roam.

## For server owners

- **Upgrade from 2.32:** stop the server, back up `Resources/Server/RacePrep/`, unzip the new
  download over your server folder and start it with the start script. Players download the new
  version when they join. Car ratings with engine upgrades are worked out again under the new
  limits on the first start; class bands don't change.
- **Engine limits are adjustable.** Copy `engine-potential.example.json` to
  `engine-potential.json` next to `RacePrep.lua` and change the power ceilings or how much each
  stage adds. Restart the server after editing. If the file has a mistake, the server says so in
  the console and uses the defaults.
- **Manage crews** has one Save button for a crew's name, tag and colour.
- Coming from **2.16**? Follow the steps below instead.

## Upgrading from 2.16 — beta

1. **Finish the session and stop BeamMP.** Back up the whole
   `Resources/Server/RacePrep/` folder, especially `rules.json`, `motorsport.json`,
   `ratings.json`, `skills.json`, `drivers.json`, `championships.json`, `history/`
   and any existing progression, crew, season, weekly, moderation or Discord files.
   This release adds `presets.json`, `challenges.json` and `rating-jobs.json`.
   Keep custom donors, car mods and BJR's own saved data too. The
   [data-file table](USAGE.md#server-data-files) identifies all saved data.
2. **Check dependencies.** Verified Rivals needs BeamMP Server 3.9.4+ and its
   server-time/position/configuration functions. Released BJR 2.0.1 runs
   classic weekends; a BJR build with race phases gives full single-event
   weekends. The yellow startup block says which, and how to switch. Install BJR separately.
3. **Download the matching Play or Custom edition for Windows/Linux.** For an
   older updater that rejects new files, install the full release ZIP into the
   stopped server folder. Do not delete existing saved data, donor folders or car
   mods. See [installation](INSTALLATION.md). BJR itself is not replaced.
4. **Start through the supplied launcher.** Let it check/generate parts before
   BeamMP starts. Read warnings instead of deleting active lock files. For a
   hosting panel that starts BeamMP directly, follow the background-parts
   `reloadmods` prompt; the launcher is needed to install staged software updates.
5. **Read the startup log.** BJR API lines show which required functions are
   available or missing. On the first progression import, look for:
   `Progression backfill: N drivers, N results, N trusted race results.`
   “Backfill” here means importing saved driver totals and up to 1,000 recent
   result files once. It does not invent missing clean/pole evidence or verify old times.
6. **Have players reconnect.** They download the updated client mod. Drivers
   shows imported progress; old unverified laps remain archived but do not rank
   on verified Rivals boards. There are no reward cards for imported old races.
   New servers start repeating monthly seasons with finish points and a clean
   bonus; medal/weekly season points start off. Personal notices can be muted with the gear icon at the top of the window.
7. **Review Motorsport settings before a race night.** Check permissions,
   weekend defaults, entry limits and season scoring. Discord stays off unless
   configured. Test a normal race and, with a compatible BJR build, a weekend.

## Known limitations — beta

- Recent progression, rewards, inbox and phase behavior has automated checks and
  browser previews, but still needs real multiplayer race-night validation.
  See [current status](../STATUS.md) for the distinction from earlier live-tested features.
- BeamJoy-Revived's pit system is still in development and is not part of BJR:ME
  yet: no pit servicing in races or weekends. Fuel strategy only estimates laps.
- On released BJR 2.0.1, penalties are added to BJR:ME's results only (BJR's own
  standings show times without them), entry minimums are checked at Ready, and
  three awards (Most places gained, Comeback, Cleanest driver) are not given.
- BJR's version label alone does not establish phase support. Missing phase APIs
  are reported at startup; do not schedule a weekend until they are available.
- Server-verified Rivals checks observed positions, gates, timing and configuration;
  it cannot prove unchanged local car physics or detect every shortcut between gates.
- Network interruptions can invalidate a lap or suppress a pop-up. Reward totals
  remain saved when a race card is missed. Restore write access before restarting
  after a storage error; not every older data file has the newer corruption safeguards.
- Turbo and supercharger sounds for fitted induction are new in this release and have only
  been checked on one computer. Whether other players hear your turbo depends on BeamMP running
  the vehicle sound on their side; report it on Discord if they don't.
- Native tyre PI still needs refinement. Performance figures are estimates, not
  measured lap guarantees. Fuel strategy does not add pit servicing.

## Full changelog — beta

Read the [full public changelog](../../CHANGELOG.md) (a short summary of each public release at the
top) and the [everyday guide](USAGE.md) for settings, permissions and backups.
