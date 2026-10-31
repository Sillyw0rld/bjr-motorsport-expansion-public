# Changelog

Versions: v2.<minor>.<patch>.<build> (build = number of commits).

## Public releases at a glance

Each public release in a few lines. The details for every version follow below.

### v2.36.1 hotfix: no more freezes in the Upgrades window (2026-10-31)

- **No more freezes in Upgrades.** The game was working out PI estimates one by one while you
  browsed. That's gone. For now upgrades show "Not rated yet"; your car's exact PI and class still
  update as soon as you fit an upgrade. Estimates come back in the next update, worked out once and
  shared, so they cost nothing while you browse.
- **Challenges:** the Start buttons showed strange text and sometimes didn't start. Fixed.
- **Share Tune** works again; loading a tune never changes the other player's parts.
- **Create Crew** works again, and tells you if the name, tag or colour needs changing.
- **Race presets:** a preset's car rules (classes, PI range, cars, upgrade limits) now show in the
  BeamJoy lobby and on the Grid tab.
- **Proximity radar:** cars on your left no longer show on the right.
- **Leaderboard gaps:** the distance and time to the car ahead and behind now show from the first lap
  on curvy tracks too, and when a gap can't be shown it says why.
- **Rubber line:** visible again in BeamNG 0.40.
- **Downloaded car mods:** better upgrade parts for some four-wheel-drive cars; mods that aren't
  Automation cars are skipped properly.
- **The window:** the Upgrade and Tuning tabs open correctly, Esc or clicking outside closes it, car
  names show properly, and it comes back cleanly after a loading screen.
- **Timers** (waits and cooldowns) follow real time, so they no longer run slow when the game is busy.
- **Server owners:** after updating, your server rebuilds the upgrade parts for some cars once, and
  players download those cars again the first time they join. Server data is kept.

### v2.36 beta: engines, turbo sound, a cleaner window and fairer low PI (2026-10-28)

- **Engines have a realistic limit.** Upgrades fill the room an engine has left, based on its
  layout and size. A small engine can still gain a lot; an engine that's already very powerful
  only gets a small tune-up. A turbo or bigger displacement raises the limit; an engine swap is
  the way to go much faster.
- **New induction:** twin-charged (supercharger plus turbo) and sequential twin turbos.
- **Hear and see your boost:** turbos and superchargers you fit now make their sound, and the
  boost gauge shows them.
- **Cleaner window:** your own settings behind a gear icon, a rebuilt Start a race, a driver card
  that sits beside the page, and tidier Drivers, Crews, Seasons and Challenges tabs.
- **Every drivable BeamNG vehicle has a PI** (buses, trucks, the trophy truck, loaders), and slow cars no longer all show E 100: they spread across Class E by real performance.
- **Fixes:** heavy lag with the window open when the server had no rivals yet; Challenges no
  longer blocks you in free roam when no practice is running.

Details: [2.33.0](#2330-beta--2026-10-28) · [2.34.0](#2340-beta--2026-10-28) ·
[2.34.1](#2341-beta--2026-10-28) · [2.35.0](#2350-beta--2026-10-28) · [2.36.0](#2360-beta--2026-10-28)

### v2.32 beta: the big update (2026-10-28)

Race weekends, server-checked Rivals with ghosts, seven challenge types with daily and weekly
targets, licences, XP, medals and achievements, crews and seasons, race presets, Build to class
and automatic rating of new cars. [What's new since 2.16.1](#whats-new-since-2161-public-beta)

### v2.16.1 beta (2026-10-22)

The previous public release: rubbered racing line, marbles, track temperature, the upgrade
workshop and Forza-style classes.

## Version by version

## 2.36.0 (beta) — 2026-10-28

### For players

- Buses, trucks and the trophy truck now have a PI, along with loaders and the other supported factory vehicles. Their badges use the same classes and rating system as cars.
- Slow cars no longer all show E 100: their ratings now spread across Class E according to performance. 100 remains the lowest displayed PI. Each existing PI value above 300 and all class boundaries are unchanged.
- Setup tuning still does not change PI. Unstable rig tests keep a flagged formula estimate, and the Pigeon keeps a measured rating. The rear-skid Covet Skidplate remains unsupported; unpowered crash-test rigs, props, trailers and simplified traffic vehicles are not rated.

### For server owners

- The updated factory seed and identity/aero catalogues include the new coverage. Older computed ratings are discarded on the formula revision change and recollected; staff-set ratings are retained.
- No new setting is needed. Details, accuracy checks and known limitations are in the PI floor review report.

## 2.35.0 (beta) — 2026-10-28

### For players

- **My preferences** moved to a gear icon in the window's top bar. HUD, timing tower, fuel strategy, proximity radar, reward pop-ups and rival notices are all in one panel, reachable from any tab, instead of crowding the Grid tab.
- **Grid → Start a race** rebuilt: layout, laps and start side by side; staff picks as cards; the other presets in a tidy list with categories and search; a clear reason when the lobby can't open yet ("Choose a layout first"). The layout is pre-selected, and the empty "Race grid" section only appears once you're in a lobby.
- **Driver card** sits in its own column beside the page instead of covering it, and shows races, wins, podiums and distance, level and licence progress bars, season position, medals and achievements.
- **Drivers, Crews and Seasons:** driver names are clickable name chips (licence, crew tag, name) instead of grey buttons; licence progress shows what's left; seasons show medal positions and the end date in the header; the crew list shows members and season position in columns.
- **Challenges:** the All challenges / Rivals switch and the type filters are compact; empty boards say what to do next.
- Fixed: Challenges said "End the current practice activity first" in free roam when no practice session was running on your map.
- The window header is quieter: the grid deadline and ready count are on the Grid tab.
- Fixed: the remaining spots where an empty list from the server could break the window (rival notices, presets, challenge boards).

### For server owners

- **Manage crews** (Motorsport settings → Crews): one form with a single **Save changes** (and Undo) for name, tag and colour, instead of three separate buttons.

## 2.34.1 (beta) — 2026-10-28

### Fixes

- Fixed heavy lag with the Motorsport Expansion window open. When the server had no rivals or challenges to send yet, the window hit an error on every screen update (thousands per minute), which slowed the game down and showed raw `{{…}}` text on the Rivals tab.

## 2.34.0 (beta) — 2026-10-28

### For players

- Turbos and superchargers you fit to naturally aspirated Automation engines now sound like them, using BeamNG's built-in vehicle sounds. Turbo spin follows spool, so you can hear the lag; supercharger whine follows engine speed.
- Sport turbos flutter on lift; Race turbos have a blow-off valve. Twin-charged builds blend supercharger whine into turbo spin, and sequential twins bring in a second, lower turbo tone.
- Factory turbos and superchargers keep their own sounds. Ignition off or a stalled engine silences the added sounds, and resets or part changes clean up their sources.

### For server owners

- No sound files, extra downloads, or new settings are needed. The sounds use the game's normal vehicle audio volume controls. Power, PI and boost gauges are unchanged.

## 2.33.0 (beta) — 2026-10-28

### For players

- Engine upgrades now follow the fitted engine's layout, displacement and remaining build potential. Engines already near their potential gain less than before; healthy low-output engines retain room to build. Bianka Elita uses the V16/W16 potential rather than a fixed percentage of its already high stock output.
- Small engines with eight or more cylinders rev higher, so they keep more of their potential when they are smaller than their layout's reference size. A 3.6 l turbo V12 now has room up to about 1,400 hp instead of 960.
- Displacement parts make the engine count as bigger: Sport as 6 % more litres, Race as 12 % more, which raises its potential.
- A turbo or supercharger raises the potential only when fitted, including in an estimated draft. Permission to fit one does not raise an NA engine's ceiling.
- Stage 1/2/3 use 15%/40%/70% of remaining headroom. Fully built Sport/Race combinations retain a 3%/5% tune floor. Parts, aspiration choices, rev limits, boost character, mass and tuning controls remain available.
- Engine swaps use the donor engine's own data. Factory combustion engines use the same potential calculation; electric upgrades are unchanged. Dyno power, real PI and draft PI use the limited curves.

- Added Race twin-charged and sequential twin-turbo choices for eligible naturally aspirated engines, with distinct low-rpm response, takeover timing and PI lag discounts.
- HUD boost gauges now receive BJR:ME's simulated boost on engines without factory induction devices. Factory devices keep control of their own values.
- The Race boost upgrade on factory-boosted Automation engines unlocks **Factory boost target** in Setup: 100% is stock positive boost; 0–115% adjusts it down or up while retaining the engine-potential limit. Stock and Sport parts do not unlock this control.

### For server owners

- Copy `engine-potential.example.json` to `engine-potential.json` beside `RacePrep.lua` to customize the ceiling table and stage/floor/taper settings. Restart the server after editing. Settings are sent to clients; an invalid file is logged and retained, with shipped defaults used.
- Missing layout/displacement uses the stock-power taper, with a once-per-engine generation warning. Engine metadata is retained by the parts generator, including all six combustion-runtime swap donors.

### Upgrade notes

- Back up `engine-potential.json` with the other server data. Updates replace the example, not your settings. Old computed engine ratings are recalculated under the new policy. Class bands are unchanged.
- Validation evidence, counts, build details and limits: [engine potential review](docs/reviews/ENGINE-POTENTIAL.md).

## v2.32.0 beta — the big update

**The biggest BJR:ME release yet.** It brings 22 releases of work since the last public release (2.16.1.8): race weekends, server-verified Rivals, seven challenge types with daily and weekly targets, licences/XP/medals/achievements, crews and seasons, server race presets, Build to class with live PI estimates, and automatic rating of new cars. Everything is explained below, feature by feature; the version-by-version notes follow after.

### What's new since 2.16.1 (public beta)

Everything added between the last public release, **2.16.1.8**, and this one, grouped by feature. Each part says what you get and how it works. Version-by-version notes follow further down.

**Before you upgrade (server owners):** back up the whole `Resources/Server/RacePrep` folder. Race weekends run on any BJR 2.0.1+ (full single-event weekends need a BJR build with phases); see [Race weekends](#race-weekends). Step-by-step upgrade instructions are in [RELEASE-NOTES.md](docs/distribution/RELEASE-NOTES.md#upgrading-from-216--beta).

#### Rubbered racing line

The rubbered line looks like real track rubber: mottled, with fine tyre streaks and ragged edges, instead of a smooth dark smudge. Grip and performance cost are unchanged. [2.16.2](#2162--better-looking-rubbered-line)

#### Race weekends

**What you get:** practice, qualifying and the race as phases of one BJR event, with one lobby. Announcements, standings and sectors follow the current phase.

**How it works**
- Staff start a weekend from **Race weekend**. Defaults: 10 minutes of practice, 10 minutes of qualifying, then a 5-lap race. Set either timed phase to 0 to skip it.
- Qualifying decides the grid. Reversed and handicap grids are also available. A qualifying lap with a recorded track-limit cut can't set your grid place.
- BJR runs the clocks, positions and penalties. Accepted penalties appear in BJR's standings.
- Only the race counts towards history, statistics, championships, XP and awards. Practice and qualifying are kept as separate session records. Practice resets and qualifying penalties never cost you a race clean-driving award.

**Two modes, chosen automatically at every server start:**
- **Full weekend** (a BJR build with race phases, e.g. a development build): one BJR event and lobby, BJR-timed phases, penalties inside BJR's standings.
- **Classic weekend** (any BJR 2.0.1+, including the released one): BJR:ME times practice and qualifying in free roam; then any player opens the race lobby in BeamJoy's race menu and the qualifying grid is applied. Penalties are added to BJR:ME's results.
- A yellow block in the server console says which mode is active, and how to switch BJR to development builds (`bj update channel development`, `bj update`, restart) and back (`bj update channel release`, or restore BJR's backup). Once phases are available, the next start uses full weekends by itself.

**Pit stops:** BeamJoy-Revived's pit system is still in development and is not part of BJR:ME yet. There's no pit servicing; fuel strategy only estimates laps remaining.

**Server owners:** BJR:ME never replaces BJR's files; install and update BJR with its own tools. [2.17.0](#2170--2026-10-23) · [2.19.0](#2190-beta--2026-10-27) · [2.32.0](#2320-beta--2026-10-27)

#### Rivals: server-verified time attack

**What you get:** a personal time attack in free roam. Every layout has class leaderboards, a weekly target, ghosts to chase, and a notice when someone beats your time.

**How it works**
- Open **Challenges** and pick a class and a layout. Choose a time to **Chase**, then **Start Rivals run**.
  - **Go to start** puts you on an available grid spot.
  - Follow the orange gates.
  - Close the window to drive with the lap timer and the live gap to your target (negative means you're ahead).
- **The server times the lap, not your game.** It reads your car's position, checks every gate in order and times the lap itself. It also checks the car it received matches the rated car. Only then does it say **Server-verified lap saved**.
  - A reset spoils the current lap.
  - Changing the car, parts, tune, map or activity ends the run.
  - The run card explains why a lap was refused.
- **Boards:** each layout, rule set and car class has its own board, so a C-class time never competes with an S-class time. Old unverified times are archived but don't rank.
- **Ghosts:**
  - an orange see-through **target car** drives the target's recorded line;
  - a faint blue car shows **your best lap** of the run.

  Only you can see them, they can't collide with anything, and both can be switched off in the run card.
- **Rival notices:** an 8-second notice tells you when another driver beats your time, for example "Alex beat your time at Imola · B by 0.31 s".
  - When you join, you see your 5 newest unseen notices; the inbox keeps 20.
  - **Race their ghost** loads their current best.
  - Mute notices in **Grid → Rival notices**.
- **BeamNG's own factory cars** can enter, checked against shipped parts lists (`native-identity.json`).

**Server owners**
- Rivals needs **BeamMP Server 3.9.4 or newer**: verification uses its server time, position and vehicle configuration functions.
- Race-control staff can **Remove time**, **Block driver** and **Unblock** from Challenges. Removed and blocked times never rank or become targets, and the original history stays saved.
- New board records can optionally be posted to Discord; this is off by default. [2.18.0](#2180--2026-10-27) · [2.20.0](#2200-beta--2026-10-27) · [2.21.0](#2210-beta--2026-10-27) · [2.26.0](#2260-beta--2026-10-27)

#### Challenges: seven types, daily and weekly targets

**What you get:** **Challenges** opens with **one daily and two weekly targets**, then **All challenges** and **Rivals** (your closest competitors and your notice inbox).

**The seven types**

| Type | What scores |
|---|---|
| Best lap | Fastest verified lap |
| Race distance | Standing start, fastest time over a set number of laps |
| Clean streak | Most consecutive valid laps |
| Consistency | Smallest spread between your lap times |
| Sector attack | Fastest time through one sector |
| Speed trap | Highest speed through a trap on the longest straight (marked during the run) |
| Tyre saver | Laps on one set of tyres; offered only when tyre wear is on |

**How it works**
- The server scores every type with the same checks as Rivals: its own gate crossings, its own timing and the car's configuration. Times your game reports are never trusted.
- Each type, layout, class and preset has its own board. An empty board can be started straight away; the first verified result sets it.
- Daily targets reset at 00:00 UTC (100 XP); weekly targets reset Monday 00:00 UTC (250 XP). Each pays once per driver. The three current targets are always different types.
- Medals work on every type (see [Progression](#progression-licences-xp-medals-achievements)). Lap-based types have ghosts; sector and speed-trap boards don't.

**Server owners:** **Motorsport settings → Challenges** chooses which types are on, whether daily and weekly targets rotate, the standing-start distance, the speed-trap position and width, and the tyre-saver minimum laps. [2.29.0](#2290-beta--2026-10-27)

#### Progression: licences, XP, medals, achievements

**Licences:** you move up **Rookie → D → C → B → A → Pro** automatically as you race. The letter shows on the grid, in Drivers and in the timing tower.

| Licence | Races | Safety | Skill |
|---|---|---|---|
| D | 5 | C | – |
| C | 15 | B | – |
| B | 30 | B | 3000 |
| A | 50 | A | 3400 |
| Pro | 100 | S | 3800 |

- **Drivers** shows what's left for your next licence.
- Only safety can demote you, one licence at a time. Staff choose when: immediately, after N races in a row below the bar (default 3), or never. Losing skill never demotes.
- Races can require a minimum licence, checked at Join and at Ready.

**XP and levels:** finishing a counted race pays 100 XP, plus 20 for each car you beat and 50 for a clean-race award. Reaching level L takes a total of `100 × (L−1) × (L+4)` XP.

**Medals:** on every challenge board, Gold is within 2% of the best verified result, Silver within 5% and Bronze within 10%.
- They're worth 50/100/200 XP; improving a medal pays only the difference.
- **Provisional medals:** a medal set alone on a board is marked *Provisional* and pays nothing yet. It's confirmed when a second driver sets a verified time, and judged again at that point. A lone "Gold" can become Silver or Bronze, or disappear if the newcomer is more than 10% faster. Confirmed medals never drop.

**Achievements and titles:** **Drivers → Achievements and titles** shows progress and rarity, meaning the share of drivers who actually race that have earned each one. Pick an earned title with **Use title** and it shows under your name.

**Reward card:** after a counted race, a card at the bottom centre shows:
- the XP breakdown;
- an animated XP bar, with a flash if you level up;
- new achievements;
- any licence change.

It closes on a click or after 12 seconds and never takes your keyboard or controller. Smaller notices cover medals and targets. Turn them off in **Grid → Reward pop-ups**; that never removes anything you've earned.

**Existing servers:** on first start, existing driver totals and up to 1,000 past result files are imported once. The log says *Progression backfill: N drivers, N results, N trusted race results*. Old unverified times are not promoted onto verified boards. [2.22.0](#2220-beta--2026-10-27) · [2.23.0](#2230-beta--2026-10-27) · [2.24.1](#2241-beta--2026-10-27) · [2.24.2](#2242-beta--2026-10-27) · [2.25.0](#2250-beta--2026-10-27)

#### Crews, seasons and driver cards

**Crews**
- Anyone can create a crew with a name, a 2–4 character tag and one of nine colours. The tag shows in front of members' names.
- Invite drivers or request to join; leaders accept requests and can hand over leadership. You can be in one crew at a time.
- If the leader leaves, the longest-standing member takes over. When the last member leaves, the crew is removed.
- Staff with the **Manage crews** permission (Mod and above by default) can rename, recolour, re-tag, change leaders, and remove members or whole crews. Removing one keeps its season points in history.

**Seasons**
- **Seasons** has **Drivers | Crews** views of the current standings, the Hall of Fame and past seasons.
- Defaults need no setup: a monthly UTC season that repeats, points 25-18-15-12-10-8-6-4-2-1, and +5 for a clean race.
- Each race, a crew's **best 2 finishers** score crew points, so a solo driver isn't penalised in the driver table, and crews compete in their own table.
- Seasons can also be per class (points by finishing position within your class), weekly, have a custom end date, or be open-ended.
- Staff can rename, extend or end a season; scoring changes apply to the next season.
- Points reset each season. XP, licences, achievements and titles carry over.

**Driver cards:** click any name in Grid or Drivers. The card opens inside the window and shows licence progress, level, title, achievements, medals, season ranks and statistics. [2.24.0](#2240-beta--2026-10-27) · [2.27.0](#2270-beta--2026-10-27)

#### Race presets and starting a race

**What you get:** **Grid → Start a race**. Choose a layout, laps, a standing or rolling start, and a preset.

**How it works**
- Presets are a server library. Up to **four staff picks** sit at the top; the rest can be searched by name or filtered by category (Racing, Class cups, Endurance, Spec series, Fun, Build to class).
- **Built-ins:**
  - a class cup for every class E–X;
  - a spec series for each server car;
  - Stock Cup, Street A, B road cars and Endurance preparation;
  - Reverse grid, Rookie cup, GT-style, Barstow muscle, Short sprint and Clean racing;
  - six Build to class presets.
- A preset lobby takes a saved snapshot of its rules. Starting one never changes the layout's normal rules or other lobbies, and the result records which preset was used.
- Players can only start presets that staff offer, and can't change the rules. Ready still checks your car against them.

**Server owners:** **Motorsport settings → Race presets** adds, edits, duplicates, removes, offers and picks presets. Editing uses the normal rule editor. [2.28.0](#2280-beta--2026-10-27)

#### Build to class

**What you get:** take a car and upgrade it into a target class (D, C, B, A, S or R) to race against others who did the same.

**How it works**
- **Who can enter:** your car's **current** PI must be inside the target class, and its **factory** PI must be at or below the class's top. A factory S car can't enter Build to B; a factory C car upgraded into B can.
  - The server checks both at Ready and at challenge start.
  - A refusal tells you exactly why, for example "Your car is S 704: 4 PI over the A limit".
  - Cars spawned from a saved setup are matched to their closest factory configuration by parts.
- **PI estimates in Upgrades:** every compatible part shows its estimated PI change, and your whole draft shows its estimated class and PI before you press Apply.
  - The estimate builds a hidden copy of the car with your draft parts and rates it exactly like the real rating, so after Apply it matches. Tested on 35 builds across 12 cars: 0 PI error.
  - If the rating formula changes and hasn't been re-tested, estimates are hidden behind **Experimental PI estimates**.
- **Quick upgrade to class** proposes a draft for you. It balances grip, brakes, weight and power, stays 5 PI under the limit, and respects the preset's upgrade caps. Nothing is fitted until you review it and press Apply.
- **Fit to class:** if a build ends up over the limit, it finds the smallest set of part removals that brings it back in.
- Weight-reduction stages now join the pending draft and apply with other parts. Engine packages still fit immediately. [2.31.0](#2310-beta--2026-10-27) · [2.31.1](#2311-beta--2026-10-27)

#### Automatic rating of new cars

**What you get:** a newly installed car gets its PI without anyone having to spawn and drive it first. Until then the selector shows **— Not rated yet**, and **— Rating…** while it's being rated.

**How it works**
- When a server car's factory configuration has no rating, the server asks an **idle staff member's game** to spawn that car briefly in the background. Idle means 30 seconds without driving, outside races and Rivals.
- The car is rated with the normal rating code, then removed. Your own car is never replaced or changed.
- BeamMP shows background cars to every player, which is why only staff games are used. A **Rating new cars (n/total)…** notice shows while it runs.
- It waits while anyone is racing or in Rivals, and stops as soon as the staff member moves, joins a session or leaves.
- The server only accepts a rating through its normal validated report. A failing car is retried at most three times per UTC day.

**Server owners:** **Motorsport settings → Cars and ratings** shows rated/total, each car's state, retry reasons and **Rate now**. [2.30.0](#2300-beta--2026-10-27) · [2.31.1](#2311-beta--2026-10-27)

#### Race results, ratings and tools

- **Race awards:** Fastest valid lap, Most places gained, Comeback and Cleanest driver. Missing clean-driving evidence never counts as clean. Awards can optionally be posted to Discord through a webhook; no bot is needed.
- **Skill and safety:** skill is shown from 1000 to 5000, and safety from F to S. Races can require a minimum of either; each needs 5 scored races. Skill or safety grid orders put new drivers behind established ones.
- **Named series:** a race can require a series name, a model, and optionally an exact factory configuration and factory tuning.
- **Saved setups and server tunes:**
  - save your tuning and differential for the same car and parts;
  - share copies with author credit;
  - loading one never fits parts or bends another race's rules.
- **Fuel strategy** estimates laps remaining from your own driving, with an optional HUD.
- **Proximity radar** (**Grid → Proximity radar**, off by default): see-through arcs showing nearby cars. The live ahead/behind gaps are back in the race HUD.
- **Fixes:**
  - missing finishing positions no longer count as podiums;
  - invalid laps don't become track bests;
  - the same BJR race is never counted twice;
  - interrupted saves retry without overwriting good files. [2.18.0](#2180--2026-10-27) · [2.19.0](#2190-beta--2026-10-27)

#### Server owners: settings, permissions and packaging

- **Motorsport settings** holds every page above. Permissions follow BJR groups: Rules, Manage crews, Race control and Weekend.
- The download is about **18 MB** instead of 26–39 MB, and updates install again. If an older updater refuses the release, install the full ZIP while the server is stopped. [2.24.3](#2243-beta--2026-10-27)
- **New data files to include in backups:**

  | Feature | Files |
  |---|---|
  | Records and skill | `records-pending.json`, `skill-pending.json` |
  | Server tunes | `shared-tunes.json` |
  | Rivals | `weekly-rivals.json`, `rivals-moderation.json`, `rival-notices.json` |
  | Discord awards | `awards-discord-queue.json` |
  | Progression | `progression.json`, `progression-pending.json` |
  | Crews and seasons | `crews.json`, `seasons.json`, `league-pending.json` |
  | Settings | `motorsport.json` |
  | Race presets | `presets.json` |
  | Challenges | `challenges.json` |
  | Automatic rating | `rating-jobs.json` |

  If one of these is damaged, its feature stops saving and asks you to restore a backup. It never silently starts over.

## 2.32.0 (beta) — 2026-10-27

### New for server owners

- **Race weekends work on every BJR 2.0.1+.** With a BJR build that has race phases, weekends stay one BJR event. With the released BJR 2.0.1, which has no phases, they run in **classic mode**: BJR:ME times practice and qualifying in free roam, then any player opens the race lobby in BeamJoy's race menu and the qualifying grid is applied. The mode is chosen at every server start; updating BJR switches to full weekends by itself.
- A **yellow block in the server console** lists every fallback in use. It gives the commands to try a BJR development build (`bj update channel development`, `bj update`, restart) and to go back (`bj update channel release`, or restore the copy BJR keeps in `BeamJoyData/update/backup-...`).

### Fixes for the released BJR 2.0.1

- **Grid orders work again.** BJR:ME answered BJR's grid hook with racer keys that the released BJR does not know, so qualifying, reverse, handicap, skill and safety grids were ignored. It now answers with player IDs there.
- **Penalties are no longer lost.** Without BJR's `race.penalize`, track-limit and false-start penalties are added to BJR:ME's results and the order is recalculated, as in 2.16. Lapped and disqualified cars keep their place.
- **Race HUD:** the timing box always shows the race, phase and lap (for example “RACE · LAP 1/2 · Highspeed Ring - Oval”), also when racing alone; previously that line only appeared with the standings tower.
- **No floating “Motorsport Expansion” button:** BJR:ME opens from BeamJoy's menu (Motorsport page).
- The startup check reads the hooks BJR actually accepts, so a missing `raceJoin` hook is reported. Licence, skill and safety minimums then apply at Ready.

### Known limitations

- BeamJoy-Revived's pit system is not part of BJR:ME yet.
- On released BJR 2.0.1: BJR's own standings show times without BJR:ME's penalties, and Most places gained, Comeback and Cleanest driver are not awarded, because BJR does not report the events they need.

## 2.31.1 (beta) — 2026-10-27

### Fixes

- **Build to class:** a car spawned from a saved setup could never get past Ready. The server looked up its factory PI by setup name and kept answering “Waiting for this car’s factory PI”. It now picks the closest factory configuration by parts, the same choice the game already makes.
- **Automatic car rating:** the rating car is visible to every player, so it now waits until nobody is racing or running Rivals. A rating in progress stops as soon as someone starts.

## 2.31.0 (beta) — 2026-10-27

### For players

- **Upgrades** previews each compatible part’s estimated PI change and your complete draft’s class/PI before Apply. It uses the same canonical collector, formula, constants, stock anchoring and part bonuses as the actual rating.
- **Build to class** presets cover D, C, B, A, S and R. Any car can enter when its current PI is in the target class and its factory PI is at or below that class’s top. Refusals identify the factory restriction or exact overage.
- **Quick upgrade to class** produces a reviewable draft, balancing grip, brakes, weight and power and keeping a 5 PI margin. It respects the selected preset’s caps. **Fit to class** searches permitted removals if the actual rebuild is over.
- Body stages now join the pending draft and Apply with other parts. Engine packages still fit immediately. Unsupported predictions show an explanation; they do not invent a PI value.

### For server owners

- The Ready hook and verified challenge start check current and factory PI on the server. Existing rule caps, PI bands and spec restrictions remain in force.
- The live accuracy gate passed: **35 distinct builds across 12 cars** (factory and Automation), **0.00 PI mean error, 0 PI worst error** on BeamNG 0.40.3. Full measurements and failed attempts are in the private review report.
- Formula/constants fingerprints bind normal preview activation to that gate. Unvalidated formulas leave estimates behind the local **Experimental PI estimates** setting. After Apply, actual PI remains authoritative.

### Upgrade notes

- Six new presets migrate into existing libraries once, preserving staff edits and active lobby rules. Deleting a new built-in does not make it reappear on every restart. Checked migration failures stop writes.
- Quick upgrade never applies automatically, and its bounded search does not promise a globally optimal part combination. Fit selects the smallest predicted reduction among inspected combinations; review before Apply. Conversions are fitted separately before searching their new upgrade tree.
- No production deployment, merge or BJR/KTS edits are part of this beta preparation.

## 2.30.0 (beta) — 2026-10-27

### For players

- Unrated selector models show **— Not rated yet**, changing to **— Rating…** during background collection.
- Rating a newly installed car no longer requires someone to choose and drive it first. The background worker spawns one disposable default configuration and uses the normal rating collector.

### For server owners

- **Motorsport settings → Cars and ratings** shows rated/total, individual states, retry reasons and **Rate now** (Rules permission).
- The tested BeamMP build syncs ordinary background spawns despite `autoEnterVehicle=false`; the worker therefore uses idle staff games only, with a **Rating new cars (n/total)…** notice. It waits for 30 idle seconds outside BJR/Rivals and stops when the driver moves, joins a session or leaves.
- Failures are capped at three attempts per car per UTC day, persisted across restarts. A client “done” cannot substitute for the normal server-validated rating report.

### Upgrade notes

- Back up `rating-jobs.json`. It preserves retry state and the validated default-build keys discovered by jobs; a corrupt queue stops writes.
- Factory identity matters: an upgraded build using the same configuration name does not satisfy the default rating check. Formula-invalidated entries remain pending until recomputed. No BJR or BeamMP files are patched by the feature.

## 2.29.0 (beta) — 2026-10-27

### For players

- **Challenges** opens with one daily and two weekly picks, followed by All challenges and Rivals. Empty layouts can be started immediately; a previous race result is no longer required.
- Seven server-scored types: Best lap, standing-start Race distance, Clean streak, Consistency, Sector attack, Speed trap and Tyre saver. Type, layout, class and preset each define a separate board. Tyre saver requires tyre wear.
- Daily targets award 100 XP and weekly targets 250 XP, once per driver/publication. Rivals shows your closest competitors, the existing notice inbox and shared-board comparisons.
- Medals retain provisional confirmation and difference-only XP. Lap-based types support ghosts; sector and trap boards show scores without a ghost button.

### For server owners

- **Motorsport settings → Challenges** controls enabled types, rotation switches, standing-start distance, trap position/width and tyre-saver minimum laps (Rules permission).
- The speed trap is placed from gate geometry on the longest identifiable straight and marked during the run. Daily reset is 00:00 UTC; weekly reset is Monday 00:00 UTC. The three current featured picks use distinct types.
- Board queries are paged and sent separately from the periodic HUD. Layout/preset/rule changes make outdated publications unavailable rather than silently replacing their target.

### Upgrade notes

- Back up `challenges.json`, including frozen targets. Damaged publication files stop writes. Keep `weekly-rivals.json` for history/backfill: old 150-XP awards are preserved, while new sessions use the daily/weekly publications.
- Existing best-lap board keys and ranked verified times remain compatible. All new scores use the same verification/moderation/medal path; cut evidence still comes from the game's existing track-limit reports and can invalidate, never establish, a server proof.

## 2.28.0 (beta) — 2026-10-27

### For players

- Grid now offers **Start a race**: choose a layout, laps, standing/rolling start and a server preset. Search by name or category, or use one of four staff picks.
- Built-ins include every class cup from E through X, server-car spec series, Stock Cup, Street A, B road cars and endurance preparation. Ready still checks your current car against the rules.
- A preset lobby has its own saved rules snapshot. Existing layout rules and other lobbies stay unchanged; results record the chosen preset.

### For server owners

- **Motorsport settings → Race presets** is the server library. Rules permission controls add, edit, duplicate and remove, categories, offered status and the four-pick limit.
- Edit a preset’s rules with the existing rule editor; Save changes the preset only. Players cannot submit rule patches or start unoffered presets.
- Additional built-ins: Reverse grid, Rookie cup, GT-style, factory Barstow muscle, Short sprint and Clean racing.

### Upgrade notes

- Back up `presets.json` with server data. It holds the editable library and per-session rule snapshots; corruption stops writes and asks for a backup restore.
- The previous JS preset list is now supplied by the server. Existing `rules.json` is retained.
- BJR’s current player-start path has no additional group restriction: known/free players can start. BJR:ME checks that state before `race.open` and displays BJR refusals. BJR remains unchanged.

## 2.27.0 (beta) — 2026-10-27

### For players

- Drivers now has clearly selected tabs, licence requirement bars, inline licence/crew badges, achievement cards and earned title chips.
- Driver cards open inside the window on the right and receive their own response event, including a loading state and close button.
- Create a crew with a clear tag label and nine colour swatches. Your crew shows membership, invitations and requests; the crew directory shows capacity and season rank.
- Seasons uses compact standings, scoring chips, podium colours, Hall of Fame cards and expandable final tables.
- Progress is requested when the menu opens and pushed when the server resolves your profile. Unchanged payloads are still suppressed.

### For server owners

- New **Manage crews** permission defaults to Mod+. Crew management is in Motorsport settings, with size/scoring steppers and server-checked rename, tag, colour, leader, member and crew actions.
- Corrected the client settings transport: licence, crew, season and Discord settings now reach the server instead of being dropped.

### Upgrade notes

- Existing crews and season history are retained, including older saved colours. New colours must use an approved swatch.
- Removing a crew/member preserves recorded season points. Leadership passes to the longest-standing remaining member.
- Rules permission still manages general settings; Manage crews separately controls crew limits and scoring membership. No new data files.

## 2.26.1 (beta) — 2026-10-27
### Fixes
- The reward display no longer refreshes the whole menu repeatedly while nothing is happening. Cards and notices still appear, animate and close normally.
### Upgrade notes
- Keep your existing settings and data. No new setup is required.

## 2.26.0 (beta) — 2026-10-27
### New for players
- An eight-second notice tells you when another driver's new verified best passes your previously faster time: for example, “Alex beat your time at Race name · B by 0.31 s”. A driver setting their first time can notify you too. Your own laps, ties and improvements by a driver who was already ahead do not notify you.
- On joining, see your newest five unseen notices. The inbox keeps the newest 20 per driver. **Grid → Rival notices** mutes them on this device; muted deliveries are still marked seen.
- **Race their ghost** chooses that rival's current verified best, not necessarily the older lap that caused the notice. The button explains when you need another map or the lap is unavailable. Normal car, class and race-rule checks still apply.
### New for server owners
- **Motorsport settings → Permissions → Post new Rivals records to Discord** is off by default and requires rules permission to save. It uses the existing awards webhook. Only a different driver taking the board record posts; the first time on an empty board and the holder's own improvements stay silent.
### Changes
- Blocked or removed laps cannot cause notices. Removing the source lap also removes its notices, including those still visible or waiting to appear.
### Upgrade notes
- Add `rival-notices.json` to backups. If it is damaged, notices stop saving until you restore it. This does not delete the original lap history. See [Discord posts](docs/distribution/USAGE.md#discord-posts) before enabling posts.

## 2.25.0 (beta) — 2026-10-27
### New for players
- After a counted race, a bottom-centre card shows finish XP, cars-beaten XP, clean-race XP, the total, XP and level before/after, new achievements with their rarity, and any licence change. The XP bar animates; a level-up flashes its new level.
- Cards appear one after another and close on click or after 12 seconds without requesting keyboard or controller focus. Practice, qualifying and the first-start history import do not create cards. An offline driver's card is discarded.
- Medal confirmations or improvements, Rivals/weekly achievements and weekly XP use six-second top-right notices. A provisional medal confirmed as Bronze says Bronze, not Gold.
### Changes
- **Grid → Reward pop-ups** is on by default and saved on your device. It covers race cards and reward notices, independently of Rival notices; switching it off never removes earned rewards.
### Upgrade notes
- Existing progression files are retained. A missed pop-up does not mean XP was lost: **Drivers → Achievements and titles** shows the saved total.

## 2.24.3 (beta) — 2026-10-27
### Fixes
- Update installation now accepts the support files added with Rivals and series. Earlier updaters could reject the new package as containing unexpected files.
### Changes
- Download packages are about 18 MB instead of the earlier 26–39 MB. Linux downloads no longer carry unnecessary debug information; screenshots use smaller WebP images.
### Upgrade notes
- If an older updater refuses the release, back up the server and install the full ZIP while it is stopped. Preserve existing data, donors and car mods; then use the supplied launcher. [Upgrade steps](docs/distribution/RELEASE-NOTES.md#upgrading-from-216--beta)

## 2.24.2 (beta) — 2026-10-27
### Fixes
- A provisional Gold is judged again when another driver confirms the board. It can become Silver or Bronze, or disappear if the time is over 10% behind the best. Previously it could pay Gold rewards despite a much faster newcomer. Only the confirmed tier now pays; already confirmed medals never drop.

## 2.24.1 (beta) — 2026-10-27
### Changes
- Live progression updates contain your full progress and small licence/title/crew labels for others. Season history and Hall of Fame load when opened. Unchanged updates are not sent repeatedly.
- Per-class seasons award race points by finishing position within that class, counting finishers only. Overall seasons still use overall positions; official race results are unchanged.
### New for players
- A medal set alone is marked **Provisional: confirmed when another driver sets a time**. It pays no medal XP, season medal points or gold-achievement progress until two different drivers have verified, unblocked times on that board.
- Confirmation happens on the next medal check without another lap from you. Season points go to the season active at confirmation. Confirmed rewards stay earned if later moderation reduces the board to one driver.
### Upgrade notes
- No new settings are needed. The confirmation re-judging fix is described in [2.24.2](#2242-beta--2026-10-27).

## 2.24.0 (beta) — 2026-10-27
### New for players
- **Crews** lets any player create a named crew with a colour and a 2–4 character tag. Invite drivers or request to join; leaders accept requests and can hand over leadership. You can belong to one crew at a time. If the leader leaves, the longest-standing remaining member takes over; the last member leaving removes the crew.
- **Seasons** has **Drivers | Crews** views for current standings, Hall of Fame and season history. Crew rows show each member's contribution. Changing crews never transfers old points.
- Click a name in Grid or Drivers for a card with licence requirements, XP/level, title, achievements and rarity, medals, season ranks and racing statistics.
### New for server owners
- **Motorsport settings → Crews** sets the member limit: 4 by default, adjustable from 2 to 12. Race-control staff can rename or remove crews. These crews are separate from BJR's own temporary crews.
- **Motorsport settings → Seasons** (rules permission) controls name, length, repeat, scoring, overall/class tables, minimum races, dropped results and scoring crew members. The defaults work without setup: repeating monthly UTC seasons, one overall table, minimum 1 race, no dropped results, and the best 2 crew members scoring.
- Finish points default to 25/18/15/12/10/8/6/4/2/1. The clean-race bonus is enabled at 5 points. Medal points of 5/10/20 and weekly-target points of 10 start disabled.
### Changes
- Choose weekly, monthly, custom-end or open-ended seasons. Weekly starts Monday UTC; a custom date includes that entire UTC day and repeats its original duration. Open-ended seasons wait for staff to end them.
- Staff can rename, extend or end an active season, or start one after it ends. Saved scoring changes apply to the next season. Turning repeat off prevents the next automatic season.
- Dropping a driver's worst race scores also drops their clean bonuses for those races, but does not rewrite already-earned crew contributions. Rivals/weekly crew scoring keeps the best scoring members per board/target.
### Upgrade notes
- Back up `crews.json`, `seasons.json`, `league-pending.json`, `progression.json`, `progression-pending.json` and `motorsport.json`. Season history and Hall of Fame are held in `seasons.json`, not separate files. Season points reset; XP, licences, achievements and titles carry over. Existing championships remain separate.

## 2.23.0 (beta) — 2026-10-27
### New for players
- **Challenges** boards show Gold within 2% of the best verified time, Silver within 5%, and Bronze within 10%. Each board is separate for its layout, rules and car class. The later provisional-medal rules and confirmation fix apply in this release: [2.24.1](#2241-beta--2026-10-27) and [2.24.2](#2242-beta--2026-10-27).
- Earn 100 XP for finishing a counted race, 20 per car beaten and 50 for a clean-race award. Medal XP totals are 50/100/200 for Bronze/Silver/Gold; an improvement pays only the increase. Beating a published weekly target pays 150 XP once per driver for that map/week target.
- Levels use total XP = `100 × (L−1) × (L+4)` for level L. **Drivers → Achievements and titles** shows progress, milestones and the percentage of eligible drivers who earned each. Eligible means a race finish or a verified Rivals lap, rather than everyone who connected.
- Choose an earned title and press **Use title**. It appears under your grid name and on your card. Licence achievements stay earned after demotion. Missing clean-driving or qualifying evidence is not guessed.
### New for server owners
- On first start, existing driver totals and up to the latest 1,000 result files are imported once. Recognised BJR race results supply race bonuses; verified Rivals laps supply medals. Unverified old times are not promoted onto verified boards.
### Upgrade notes
- Back up `drivers.json`, `skills.json`, `history/`, `progression.json` and `progression-pending.json`. Look for **Progression backfill: N drivers, N results, N trusted race results.** in the server log. Here “backfill” means the one-time import. It is not repeated on each restart, and does not show old reward cards.

## 2.22.0 (beta) — 2026-10-27
### New for players
- Passive licences progress through **Rookie, D, C, B, A, Pro** as your races, safety and skill meet each requirement. Grid, Drivers and the timing tower show a small licence letter; Drivers shows what remains for the next one.
- D needs 5 races and safety C; C needs 15 and safety B; B needs 30, safety B and skill 3000; A needs 50, safety A and skill 3400; Pro needs 100, safety S and skill 3800. The progress view uses “C+”, “B+” and “A+” to mean that grade or better.
### New for server owners
- **Motorsport settings → Licences** (rules permission) chooses demotion: Immediately, After N races, or Never. Default is After 3; N can be 1–10. Only safety causes demotion, one licence at a time. Losing skill does not demote.
- After N counts consecutive safety-scored races below the current licence's bar, including the first. A scored recovery resets the count; races with safety scoring off neither count nor reset it. Drivers without safety-scored races keep their existing default safety for licence checks.
- **Race rules → Eligibility → Minimum licence** defaults to no limit. Both Join and Ready refuse a driver below the selected licence with a readable reason.
### Upgrade notes
- Preserve `skills.json`, `drivers.json` and the progression files together. Changing or deleting these to bypass a problem can break continuity of progress. This feature does not change car ratings or race results.

## 2.21.0 (beta) — 2026-10-27
### New for players
- Rivals laps can show an orange see-through target car and a fainter blue car for your best lap of the current run. They follow the recorded line at the corresponding lap time, fade near your car and cannot collide with anything.
- **Target ghost** and **Your best ghost** in the Rivals run card are both on by default and saved on your device. They also respect BJR's activity-marker visibility setting. Close the main window to chase the ghost with the timing HUD visible.
### Changes
- Ghosts are local visual guides: no extra vehicle is spawned or sent to other players. They do not change lap verification or BJR's separate non-collision settings.
### Upgrade notes
- There is no server-side ghost setup. A target needs a usable recorded reference line; old records without one cannot supply playback.

## 2.20.0 (beta) — 2026-10-27
### Fixes
- Factory configurations of BeamNG's own cars can now enter verified Rivals when their shipped parts information matches the selected rating. Previously some correctly rated factory cars were refused with **Server parts identity unavailable**.
- Cars with repeated part names in different slots no longer get incorrectly refused as **Ambiguous server parts identity**. Real parts changes still require a matching rating.
### Upgrade notes
- Keep the new server support file `native-identity.json` from the release. It is not a player download and needs no manual editing. If a configuration still lacks a matching parts list, the run remains unavailable rather than accepting an unchecked car.

## 2.19.0 (beta) — 2026-10-27
### New for players
- Race weekends now receive post-race awards too. Fastest valid lap, Most places gained, Comeback and Cleanest driver use the race phase only. Practice resets and qualifying penalties do not cost a race clean-driving award.
### Changes
- Optional Discord awards follow the same race-only result. Practice and qualifying still do not add wins, race counts, skill or race XP.
### Upgrade notes
- No new setting is required. Weekends still need a BJR build with phase support; the version number alone is not enough.

## 2.18.0 — 2026-10-27
### New for players
- **Challenges**, beside Results, combines **Weekly Rivals** and **Class leaderboards**. Choose a class and layout/rules board, optionally filter by car, choose **Chase**, then **Start Rivals run**. Your best and its gap to the target appear above the board. An empty layout can be started without a target to set its first verified lap.
- Rivals is a personal free-roam activity, not a shared BJR event. Leave any BJR race or practice, use a rated car in the required class, and follow the orange gates. **Go to start** moves you to an available grid position. Close the window for lap time, valid/invalid status and a signed live difference; negative means ahead.
- **Server-verified lap saved** confirms that the server accepted its own timing and gate checks. A reset invalidates the current attempt; changing the car, parts, tune, map or activity ends the run. The run card explains refused laps. Old unverified times stay archived but do not rank or become verified targets.
- **Weekly Rivals** publishes a target for each map from existing verified times, with its class, car and PI. It changes Monday at 00:00 UTC and remains fixed for the week. If its car, layout, rules or time becomes unavailable, it waits for the next week instead of silently choosing a replacement.
- **Results** adds Fastest valid lap, Most places gained, Comeback and Cleanest driver. Ties can share an award; missing clean-driving evidence never counts as clean. Weekend awards were added in [2.19.0](#2190-beta--2026-10-27).
- **Saved setups** saves applied tuning and differential settings for the same model and fitted parts, with load, rename, duplicate and delete. **Server tunes** shares copies with author credit; copying one does not fit parts or change the car. Fuel strategy estimates laps remaining from your own driving and can show an optional HUD; it does not add pit servicing.
- **Grid → Proximity radar** adds transparent directional arcs using BeamNG's nearby-car data. It starts off; choose lower left/centre/right and brightness, saved on your device. Live ahead/behind time and route-distance estimates return to the race HUD alongside BJR's official interval.
### New for server owners
- Verified Rivals needs BeamMP Server 3.9.4 or newer with server time, positions and vehicle-configuration APIs. Without them runs refuse to start. The server checks its own gate crossings, elapsed time and the car configuration it received; the player's displayed clock alone cannot verify a lap.
- Race-control staff can **Remove time**, **Block driver** or **Unblock** from Challenges. Removed/blocked records cannot rank or become targets; original history stays saved.
- **Race rules → Event preset** fills the existing editor with Stock Cup, B-class road cars, Street A, a server-available spec car, Endurance preparation or Open class. Review the draft and Save. Endurance preparation does not set race distance or create pit stops.
- **Eligibility → Named series** selects a series name, required model and optional exact factory configuration. Fixed setup also checks factory tuning values. Minimum skill and safety-grade requirements apply at Join and Ready; each selected rating needs 5 scored races. Skill/safety grid orders put provisional drivers behind established drivers.
- Skill is displayed on a 1000–5000 scale and safety as F through S. Existing saved ratings are kept. These are BJR:ME ratings, not Forza's rating algorithm.
- Race awards can be posted to Discord, off by default. Configure the server-only `awards-discord.json`; no bot token is needed. Failed or interrupted posts are held for inspection instead of automatically sent again.
### Changes
- Only server-verified Rivals laps rank on the new boards. Different layouts, rules and classes remain separate. Rivals does not add race wins, race counts or skill.
- A saved tune requires matching hardware and legal values; it never silently fits new parts or clamps a tune to another event's rules. Upgrades → Undo last change can undo a tune load.
### Fixes
- Missing finishing positions no longer count as podiums. Invalid or disqualified laps do not become track bests; a car's later rating is not substituted into an old result. Repeated saves do not count the same BJR race twice.
- Interrupted result and driver updates retry without deliberately replacing the previous good files. See the [data-file guide](docs/distribution/USAGE.md#server-data-files) for the limits of older files.
### Upgrade notes
- Back up the whole server data folder, especially history, drivers, skills, championships and rules. New saved data includes `records-pending.json`, `skill-pending.json`, `shared-tunes.json`, `weekly-rivals.json`, `rivals-moderation.json` and `awards-discord-queue.json`.
- After changing car mods, run the usual launcher so the server's available-car list and upgrade parts are refreshed. Players reconnect for new client files. See [2.20.0](#2200-beta--2026-10-27) for factory-car support included in this release.

## 2.17.0 — 2026-10-23
### New for players
- **Race weekend** opens practice, qualifying and race as phases of one BJR event and one lobby. Optional timed practice/qualifying lead to the counted race; announcements, standings and sectors follow the current phase.
- Qualifying, reversed and handicap grids use BJR's own racer identities. Accepted penalties appear in BJR standings. A qualifying lap with a recorded track-limit cut cannot set your grid place.
### New for server owners
- Weekends require a **phase-enabled BJR build**. The bridge names 2.0.1 as its minimum, but BJR's released 2.0.1 does not provide phases. Use a compatible phase-enabled development build; check the startup **BJR API** capability lines for missing phase functions/events.
- **Motorsport settings → Race weekend** defaults to 10 minutes practice, 10 minutes qualifying and a 5-lap race. Set either timed phase to 0 to omit it. Weekend permission defaults to mod and above; rules/track editing to admin and above; race control to mod and above.
### Changes
- Only the final race counts for race history, statistics, championships and progression. Practice/qualifying session records are kept separately. BJR owns the clocks, positions and final penalty-inclusive result.
- BJR:ME does not replace BJR server files or its client ZIP. Install and update BJR separately with its own tools.
### Upgrade notes
- Back up your settings and saved results. Confirm that BJR's phase features are available before scheduling a weekend; the old separate free-roam practice/qualifying workflow is not the new weekend format.

## 2.16.2 — better-looking rubbered line
- The rubbered racing line now looks like real track rubber (mottled, with fine tyre streaks and
  ragged edges) instead of a smooth dark smudge. No performance cost; grip is unchanged.

## 2.16.1 — servers started without the launcher
- If your host starts BeamMP itself and you can't use `start-bjrme-server`, start it normally:
  BJR:ME now builds parts for new or changed cars in the background when the server starts, then
  asks for `reloadmods` (or sends it itself when the server runs in tmux). The launcher stays the
  recommended way to start.

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
