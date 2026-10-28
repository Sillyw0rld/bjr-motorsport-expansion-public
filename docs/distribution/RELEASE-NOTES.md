# v2.32.0 beta: the big update

**The biggest BJR:ME release yet.** It brings 21 releases of work since the last
public release (2.16.1.8) together in one update. Players gain race weekends,
server-verified Rivals and challenges, driver progression, crews and seasons, race
presets and Build to class. Owners get more ways to organise races and new cars
that rate themselves, without changing BJR's official results.

## Highlights — beta

- **Race weekends:** optional practice and qualifying followed by the race in
  one BJR event. Only the race counts. With released BJR 2.0.1, weekends run in
  classic mode (BJR:ME-timed practice and qualifying, then a normal BJR race lobby).
- **Rivals and ghosts:** server-verified class boards, weekly targets, factory-car
  support, lap ghosts and notices when another driver passes your time.
- **Progression:** automatic licences, XP/levels, achievements with rarity,
  earned titles and a post-race card showing what you gained.
- **Medals:** Bronze/Silver/Gold depend on the best verified time. Medals set
  alone are provisional, then judged again when another driver confirms the board.
- **Crews and seasons:** persistent teams, configurable driver/crew standings,
  Hall of Fame, history and clickable driver cards.
- **Owner controls:** presets and spec-car rules, permission settings, optional
  Discord awards/record posts, repaired update installation and smaller packages.
- **Challenges:** seven server-scored types (best lap, race distance, clean
  streak, consistency, sector attack, speed trap, tyre saver) with one daily and
  two weekly targets.
- **Race presets:** start a race from a staff-curated library with four staff
  picks, a class cup for every class and searchable categories.
- **Build to class:** upgrade a car into D–R with live PI estimates per part,
  a reviewable quick-upgrade draft and Fit to class.
- **Automatic car rating:** new cars get their PI on an idle staff game, so
  nobody has to drive an unrated car first.
- **Redesigned screens:** Drivers, Crews, Seasons and staff crew management.
- **Racing display:** live ahead/behind estimates, transparent proximity radar,
  fuel strategy, saved/shared tunes and less unnecessary menu refreshing.

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
   bonus; medal/weekly season points start off. Personal notices can be muted in Grid.
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
- Native tyre PI still needs refinement. Performance figures are estimates, not
  measured lap guarantees. Fuel strategy does not add pit servicing.

## Full changelog — beta

Read the [full public changelog](../../CHANGELOG.md#whats-new-since-2161-public-beta)
and the [everyday guide](USAGE.md) for settings, permissions and backups.
