# Everyday use

## Install and start

1. Extract the native Windows x64 or Linux x64 release into your stopped BeamMP
   server. Install BJR separately. No system Python is needed.
2. Put your normal Automation car ZIPs in `Resources/Client/`.
3. Start `start-bjrme-server.cmd` (Windows), or
   `./start-bjrme-server.sh ./BeamMP-Server` (Linux).
4. Wait for preflight to finish and BeamMP to start, then join normally. Players
   download the generated client mod through BeamMP.

The first start generates the upgrades locally. Later starts skip unchanged
parts. The launcher is required to install staged software updates. If your host starts
BeamMP directly, parts are checked in the background; follow the console prompt
for `reloadmods` and have players reconnect for changed parts. See [installation](INSTALLATION.md) for permissions and custom paths.

## Players: build, tune and race

Join a server running the expansion. BeamMP downloads the client mod; players
have nothing to generate locally. Open **Motorsport Expansion** from BJR's side
menu. Expand the window for more working space.

### Upgrades

1. Choose a category across the top, then a part type on the left.
2. Select a Stock/Street/Sport/Race option or a compatible factory part along
   the bottom. The side panel explains it; the centre shows the dyno or
   performance estimates for the category.
3. Use **Apply upgrades** for queued choices. Engine packages and body stages
   fit immediately where the interface says so. Check the fitted indicator
   rather than assuming that highlighting an option installed it.
4. Use **Undo last change** to restore the previous build/settings, or discard
   queued choices before applying them.

On supported Automation cars, **Engine conversion** offers donors that pass fit
and runtime checks. Apply a conversion on its own, then choose upgrades for the
new engine. Drivetrain conversions change the driven layout; they do not mean
every recipient can use every donor. Native cars instead offer their compatible
factory hardware. A missing option can mean no compatible part or a race-rule
restriction, rather than an unlock you have not purchased.

### Setup

Choose a setup category and adjust the available sliders. Read the units and
current value, then apply the changes. Open **Saved setups** to keep an applied tune.
Fitted parts determine which controls are editable. Final drive and individual
gear ratios have separate permissions; fitting a final drive does not unlock
all gears. Setup figures are estimates, not measurements of your last lap.

### Saved setups

In **Setup → Saved setups**:

1. Apply or discard pending tuning, differential and upgrade edits.
2. Enter a name and click **Save applied tune**. Use a fresh name for each version.
3. Select **Load** on a compatible tune. It restores applied tuning and
   differential settings together and preserves your fuel through the rebuild.
4. To **Rename** or **Duplicate**, enter the new name in the name field first,
   then click that action on the saved tune. Deleting requires a second click.

A tune requires the same model and fitted parts, and must satisfy current
race rules and slider ranges. It does not install parts or silently clamp a
saved tune to different rules. The displayed difference count compares saved
sliders with the applied car, not unapplied edits. **Undo last change** in
Upgrades restores the previous tuning and differential settings after a load.

**Save full build to vehicle selector** is the separate BeamNG configuration
save, including parts. The local tune library does not replace those files.
It stores at most 100 named tunes in alternating snapshots at
`settings/raceprep/setup-library-a.json` and `setup-library-b.json` in your
BeamNG user folder. Keep both files when backing up. These files hold your local library. Sharing is optional and server-local:

1. In **My tunes**, select **Share** on a compatible saved tune; add a short
   description so other drivers know what it is intended for.
2. Open **Server tunes** and refresh to browse tunes for your current model.
   Author and inherited author credit appear with each tune.
3. **Copy to local library** downloads a copy; it does not change your car.
   Switch back to My tunes and **Load** when the fitted parts match.
4. Only the author can remove their server copy. Removal requires confirmation.

Publishing the same model/name updates your own server entry. The server stores
at most 20 tunes per author and 200 total in `shared-tunes.json`; back it up with
other server data. Hardware and race-rule checks still apply when loading.
Sharing a tune does not include a lap ghost.

### Rivals clean-lap challenges

Open **Challenges → Class leaderboards** and refresh the records.
Choose a class, then the layout/rules board. Optionally filter to a car and
click **Chase** on a target. Your personal best and its gap to that target are
shown above the table. With the matching layout/rules and a rated car in the
required class, choose **Start Rivals run**. Leave any BJR race or practice first.

- **Go to start** moves your car to an available grid position on that layout.
  Otherwise drive to the first gate. Orange gate posts guide your run and respect
  BJR's activity-marker visibility setting.
- Cross the start line to begin timing. Close the main window for the live
  lap clock, clean/invalid status and signed delta: negative means ahead.
- The server samples only active Rivals cars at 20 Hz, checks every gate in
  order and interpolates crossings using its own steady clock. The local lap
  clock/delta is provisional until **Server-verified lap saved** appears.
- Cuts reported by the game invalidate the lap. Resetting voids the current
  attempt; cross the start again. Changing parts, tune, car, map or activity
  ends the run. Use **End run** to stop explicitly.
- A timing mismatch, missed gate, teleport, stale positions or expired lap
  confirmation is explained in the run card. Strong network jitter can void
  an otherwise clean attempt; cross the line for another lap.
- **Ghosts:** once your lap starts, an orange see-through car shows where the
  target was at the same moment of their lap, and a fainter blue one shows your
  best lap of this run. They fade when you're alongside, can't be hit, and only
  you see them. Turn each off under **Target ghost** / **Your best ghost** in the
  run card; the choice is saved. They hide with BJR's activity markers.
- Server-sampled reference lines support the live delta. Client traces and
  local personal references are display data, never verification evidence.
- Only verified personal Rivals laps rank. Old Rivals and ordinary-race times
  remain archived, unverified for this board, and hidden by default. An empty
  layout can still be selected: start without a target to record its first lap.
- Verification requires a complete rated parts map matching BeamMP's received
  configuration. BeamNG's own cars in factory configurations use the parts
  lists shipped with the server (`native-identity.json`); a car whose rating
  has no parts list at all is refused with **Server parts identity unavailable**.
  Merely naming a cached rating key is insufficient.
- Runs award no race wins, race counts or skill. Ordinary BJR race timing and
  results are independent of this verifier.

Staff with the existing **raceControl** Motorsport permission see **Remove time**
and **Block driver** beside board entries. Confirm the action and refresh.
Blocked drivers can be unblocked below the board. History files are retained;
`rivals-moderation.json` records the action, staff identity and time. A damaged
moderation file blocks Rivals until staff restore its backup.

The server-local catalogue scans 1,000 recent result files. Different layouts,
rules and classes form separate boards. Weather and grip still
vary. Verification means server-observed crossings and elapsed time, not
proof of stock physics or authentic network packets. The server cannot prove unchanged local vehicle physics or detect every shortcut
between gates. Use enough well-placed gates and staff moderation.

### Weekly Rivals

The weekly card in **Challenges → Weekly Rivals** picks an existing layout and class on
this server's loaded map. It uses a server-verified Rivals lap as its target, including
that lap's car and PI. **Start weekly run** starts a personal Rivals attempt;
a quicker clean lap produces a “Weekly target beaten!” confirmation.

Picks reset on Monday at 00:00 UTC and are saved in `weekly-rivals.json`. Once
published, a target stays fixed even if its original driver improves. Each map
gets its own pick when requested, without switching the shared server map.
A missing car, changed layout or changed rules makes the old pick unavailable
rather than silently replacing it. Previously published unverified or moderated
targets are also preserved but unavailable until the next UTC week. With no
eligible baseline, record a server-verified personal Rivals lap first. An
ordinary BJR race can seed the layout catalogue, but cannot seed a verified
target. Beating the published target awards weekly XP; season points are optional, as
described under [Medals and XP](#medals-and-xp) and [Seasons](#seasons).

### Post-race awards

The **Results** screen shows awards after a counted BJR race, including the race
phase of a weekend:

- **Fastest valid lap** excludes invalid and disqualified laps.
- **Most places gained** compares the recorded starting grid with the final
  finishing place. A positive gain is required.
- **Comeback of the race** requires losing at least two places after the grid,
  then recovering at least two places from the worst observed position.
- **Cleanest driver** requires a finish, track-limit monitoring, sufficient
  telemetry coverage and no recorded cuts, fault contacts, resets or penalties.
  Missing evidence does not count as a clean drive.

Ties share the award. Some races legitimately have fewer than four awards.
BJR position changes can come from penalties or finishes as well as passes;
these awards do not claim to count confirmed on-road overtakes. Client-reported
contact data retains its existing limits. In a race weekend, awards are for
the race only; practice and qualifying never count.

See [Discord posts](#discord-posts) to enable optional award announcements.

### Proximity radar

In **Grid**, enable **Proximity radar**, choose Lower left, Lower centre or
Lower right, and adjust **Radar brightness**. Position, brightness and the
on/off preference are saved on your client. Choose a position clear of your
other BeamNG apps. Close the main window to see it while driving.

The centre has no background fill. Thin directional arcs and small dots show
nearby cars: white nearby, amber close, red very close. The display fades out
when no cars are detected and hides if its data becomes stale. It does not
capture mouse input. It uses BeamNG's native vehicle-radar stream, including
its detection limits; it is an aid rather than a guarantee that a space is clear.
The expansion does not alter the native radar app's settings.

### Fuel and tyre strategy

**Setup → Fuel** shows tank levels and a measured laps-remaining estimate after
you complete laps in a BJR race or Rivals run. The small **Fuel strategy HUD**
can be switched on or off with the gear icon (My preferences) at the top of the window. It uses observed consumption, not a fixed car estimate.
For a lap-limited race, the recommendation includes one reserve lap. Refuelling,
resetting or changing the car clears the old estimate; different driving styles
can change what fuel you actually need.

When KTS publishes tyre telemetry, the same panel shows tyre condition,
temperature and pressure. Without that stream it says telemetry is unavailable.
It does not predict tyre lifetime or introduce pit servicing.

### Curated event presets

Staff can open **Motorsport settings → Race rules**, choose an **Event preset**
and click **Use preset**. Review the resulting draft and use the existing Save
button to apply it to the selected rule scope. Editing a preset marks it custom.

- **Stock Cup**: factory upgrade caps and road tyres.
- **B-class road cars**: B-class/PI limits with sport-level upgrade caps.
- **Street A**: A-class 601–700 PI, road tyres and no engine/drivetrain swaps.
- **Spec <car>**: generated from the server car list, with a required model and
  its known factory configuration, factory parts/caps and fixed setup. **Spec-car
  preparation** is a starting point for choosing your own required car.
- **Endurance preparation**: fuel, tyre wear and track-limit rules; set race
  distance in BJR. This does not add pit servicing or set a race length.
- **Open class**: start from unrestricted expansion rules.

Presets use the existing rule editor and do not start an event or change the map.
In **Eligibility → Named series**, edit the name, required car and optional exact
configuration code. Save in the intended scope; the series name appears on Grid.
BeamNG's base cars come from the shipped native catalogue; Automation mod cars
come from the server car catalogue and must still have their source ZIP present.
The normal generator refreshes this list for Automation and other car mods,
requiring real model/configuration/main-part files; upgrade-only folders and
skin packs do not become extra spec cars. Run the normal generator after
adding/changing/removing car mods. Older installs fall back to their last
Automation generation manifest until the new catalogue is first written.

A fixed-setup spec car is checked against its factory tuning values, so entering
with an already-saved tuned configuration does not bypass disabled sliders.
Fuel load remains adjustable when the fuel rule permits it. A blank configuration
allows factory variants under the remaining rules; choose an exact configuration
for a single-variant spec field. This does not apply per-car Balance of Performance
adjustments or automatically replace everyone's build. Load the required factory
configuration in BeamNG, then use the existing Ready workflow.

### Driver ratings and entry limits

**Drivers** and **Grid** show skill on a 1000–5000 display scale and safety grades
F, E, D, C, B, A and S. Saved Elo/safety values are preserved; this is BJR:ME's
own result/PI-adjusted Elo and incident/lap safety system, not Forza's algorithm.
The skill display is `1000 + clamp(Elo, 0, 3000) × 4/3`, rounded to an integer.
Safety thresholds on the existing /5 scale are F <0.5, E ≥0.5, D ≥1, C ≥2,
B ≥3, A ≥4 and S ≥4.5.

A `?` means fewer than five scored races for that rating. Skill requires scored
races with at least two drivers. Safety-scored races are counted separately from
total races; existing safety values are retained, but the new counter starts at
zero for older profiles rather than claiming unrecorded scoring provenance.

Staff can set **Minimum skill** and **Minimum safety grade** in Race rules →
Eligibility. Zero skill / No limit leaves entry open. A restricted event requires
five scored races for each selected rating; provide unrestricted races first.
BJR's native Join/Ready hooks enforce these requirements with a visible reason.

Race rules → **Start and grid** adds **Skill: highest first** and **Safety: highest
first**. Provisional drivers start behind established drivers; equal ratings
retain BJR's supplied order. These rating-based grid options apply to ordinary races. Weekends use the
join, qualifying, reverse and handicap options described below.

### Live race gaps

Close the Motorsport Expansion window and enable **Driving HUD** to see the
race timing panel. In an ordinary BJR race with another participant, the rows
below it show the drivers immediately ahead and behind in BJR's standings.

- **~ seconds** is a continuously sampled local estimate. It compares the
  following driver's route position with when the leading car crossed that
  same position; it needs enough history before it appears.
- **~ metres** is estimated separation along the checkpoint route, including
  completed laps, rather than straight-line distance between cars. The initial
  checkpoint approximation improves as your line between gates is recorded.
- **BJR interval** retains the official checkpoint interval or lap difference.
  BJR still decides positions, penalties and results.

A dash means unavailable, not zero. Estimates need synced vehicle positions
and progress beyond the first gate. They clear on a reset, car replacement,
disconnect or discontinuous progress and can briefly warm up again when the
recorded route improves. Branching layouts and repeated point-to-point runs
retain BJR intervals without local distance estimates. These figures are
informational; they do not change race scoring or transmit extra telemetry.

### Race weekends

Weekends run in one of two modes. BJR:ME picks the mode at every server start
from what your BeamJoy-Revived offers, and prints the choice in the console.

| | **Full weekend** | **Classic weekend** |
| --- | --- | --- |
| Needs | A BJR build with race phases (development builds; tested with build 2488) | Any BJR 2.0.1+, including the released 2.0.1 |
| Practice / qualifying | BJR phases inside one event and lobby | BJR:ME timed sessions in free roam on the weekend's track |
| Race | Same BJR event | A normal BJR race lobby; any player opens it in BeamJoy's race menu |
| Grid | From qualifying, reverse or handicap | The same, applied by BJR's grid hook when the countdown starts |
| Penalties | Inside BJR's standings and totals | Added by BJR:ME to its own results (BJR's standings show times without them) |

**Classic mode** is used when BJR has no race phases. A yellow block in the server
console then explains it and how to switch. To try a BJR development build, run
`bj update channel development`, then `bj update`, then restart BeamMP.
Development builds are test snapshots of BJR's newest code. To go back, run
`bj update channel release`: the next BJR release then installs as usual. To
return to the release straight away, stop BeamMP and restore the previous copy
BJR moved to `BeamJoyData/update/backup-...`, or reinstall the release ZIP. Saved
BJR data is not touched. BJR:ME switches to full weekends by itself on the next
start once phases are available.

On a BJR without phases, also: licence, skill and safety minimums are checked at
Ready rather than Join, and the Most places gained, Comeback and Cleanest driver
awards are not given (BJR does not report the events they need).

Verified Rivals separately needs BeamMP Server 3.9.4+ with its server-time,
raw-position and vehicle-configuration APIs.

**Full weekend**

1. Open **Race weekend**, select a saved BJR race and review practice minutes,
   qualifying minutes, race laps and grid order.
2. Staff with **weekend** permission can open the event. Drivers join the same
   BJR lobby and follow its Ready/start procedure throughout.
3. Practice and qualifying are timed best-lap phases. When time expires, BJR's
   finish-current-lap behavior applies. The race is the only counted phase.
4. Staff can end a phase or close the weekend. BJR owns the clocks, standings,
   penalties and final result.

**Classic weekend**

1. Start the weekend from **Race weekend** as above.
2. Practice and qualifying run in free roam on that track. Drive through the
   checkpoints; BJR:ME times each lap and shows the standings. Staff can skip to
   the next session.
3. When qualifying ends, everyone is told to open the race lobby. Any player
   can open it from BeamJoy's race menu, usually the one who started the weekend.
   The qualifying grid is applied when the countdown starts.
4. Only the race counts, exactly as in a full weekend.

**Pit stops:** BeamJoy-Revived's own pit system is still in development and is
not part of BJR:ME yet. Weekends have no pit servicing; fuel strategy only
estimates laps remaining.

**Motorsport settings → Race weekend** saves defaults with **rules** permission:

| Setting | Default | What it does |
| --- | --- | --- |
| Practice minutes | 10 | Timed practice; 0 omits it; allowed 0–120. |
| Qualifying minutes | 10 | Timed qualifying; 0 omits it; allowed 0–120. |
| Race laps | 5 | Counted race distance; allowed 1–1000. |
| Grid order | Qualifying | Join order, qualifying, reverse or handicap (lowest PI first). |
| Grid source | Rules | Take grid choices from the selected race's rules, or use these weekend defaults. |

Qualifying laps with a recorded cut do not set a grid place. Practice and
qualifying do not add races, wins, skill, race XP or race awards. Their session
records remain available separately from the final race result.

### Race HUD and results

Use **Grid → Driving HUD** and **Timing tower** for the timing panel and
standings. Both start on. Close the main window while driving. The HUD shows
the current phase, countdown or laps, sectors, penalties, start lights and flags.
The ahead/behind estimates described under [Live race gaps](#live-race-gaps)
supplement BJR's official intervals; they do not decide positions or results.
**Fuel strategy HUD** also starts on; **Proximity radar** starts off.

**Results** has lap/sector details and history. **Drivers** has ratings and
statistics. **Championship** is the existing staff-run series system, separate
from the new seasons. A missing time is not a zero; check the session, car,
version and server log before assuming a result counted.

### Driver licences

Open **Drivers → Licence and stats** to see your licence and what remains for
the next. Licences are automatic and do not buy parts or change car PI.
Letters R/D/C/B/A/P appear beside names.

| Licence | Recorded races | Safety grade or better | Minimum skill |
| --- | ---: | --- | ---: |
| Rookie | 0 | Any | None |
| D | 5 | C (2/5) | None |
| C | 15 | B (3/5) | None |
| B | 30 | B (3/5) | 3000 |
| A | 50 | A (4/5) | 3400 |
| Pro | 100 | S (4.5/5) | 3800 |

“Recorded races” follows the driver's race count, not only wins or finishes.
Drivers without safety-scored races keep their default safety for licence
checks. In the progress list, C+/B+/A+ means that grade or better.

**Motorsport settings → Licences** needs **rules** permission. **Demotion**
can be Immediately, After N races, or Never; the default is **After 3** and N
can be 1–10. Count only consecutive safety-scored races below the current bar,
including the first; a scored recovery resets the count. Races without safety
scoring neither count nor reset it. Demotion is one licence at a time, for
safety only. Losing skill never demotes you.

**Race rules → Eligibility → Minimum licence** defaults to no limit and is
checked at Join and Ready. Licence achievements remain earned after demotion.

### Medals and XP

Medals belong to each Rivals layout/rules/class board. Only verified, unblocked
laps qualify. A provisional medal is shown from the first qualifying time:
**Provisional: confirmed when another driver sets a time**.

| Medal | Within this much of the best verified time | Total medal XP |
| --- | --- | ---: |
| Gold | 2% | 200 |
| Silver | 5% | 100 |
| Bronze | 10% | 50 |

With fewer than two distinct eligible drivers on a board, medals are
provisional: no medal XP, season medal points or gold-achievement progress.
The next medal check after a second driver arrives confirms eligible medals,
without another lap from you. The time is judged again against the current
best: provisional Gold can become Silver, Bronze or no medal. An already
confirmed medal never drops; later improvements pay only the XP increase.

Race finish XP is **100 + 20 per car beaten**; a clean-race award adds **50**.
Beating a published weekly target pays **150 XP**, once per driver/map/week
target. Weekend practice/qualifying pay no race XP. Total XP for level L is
`100 × (L−1) × (L+4)`; level 1 starts at 0 XP. There is no currency or spending.

On first startup, BJR:ME imports existing driver totals and up to the latest
1,000 result files once. Old unverified times do not become verified. The log
line **Progression backfill: N drivers, N results, N trusted race results.**
reports this one-time import. Missing historical clean/pole evidence is not
invented. The import does not replay old reward cards.

### Achievements, titles and reward pop-ups

Open **Drivers → Achievements and titles** for XP/level and the achievement
list. Rarity is the percentage of drivers with a race finish or verified
Rivals lap who earned the achievement, not all accounts that connected.
Choose an earned title and press **Use title**; it appears under your grid name
and on your card. Achievements cover licences, racing, clean driving, distance,
Rivals, qualifying, seasons and levels; the list names each milestone.

After a counted race, online drivers see a bottom-centre card with their actual
XP lines, before/after level and XP, newly earned achievements and any licence
change. Cards queue and close on click or after **12 seconds**, without taking
keyboard/controller focus. Offline cards are not stored. Missing a pop-up does
not remove saved XP. Practice, qualifying and the first-start import show no card.

Medal confirmations/improvements, Rivals/weekly achievements and weekly XP use
**six-second** top-right notices. **Grid → Reward pop-ups** is on by default,
saved on your device, and controls both. It is separate from Rival notices.

### Crews

Open **Crews**, enter a name, a **2–4 character** tag and a colour, then Create.
Any player can create a crew and can belong to only one at a time. Leaders
invite known drivers; invitees accept. Drivers without a crew can request to
join; the leader approves. Leaders can hand over leadership voluntarily.
Leaving hands leadership to the longest-standing remaining member; the last
member leaving removes the crew. These crews are separate from BJR's own crews.

**Motorsport settings → Crews → Maximum members** needs **rules** permission:
**4** by default, allowed **2–12**. Lowering the cap does not expel existing
members, but blocks new joins until there is space. Staff with **raceControl**
permission can rename or remove a crew. Earned season contributions stay with
the crew they were earned for when a driver moves elsewhere.

### Seasons

Open **Seasons** and switch **Drivers | Crews** for the current standings,
**Hall of Fame** or **Season history**. Crew rows show members' contributions.
Archived pages load when opened. Season history and Hall of Fame are saved
inside `seasons.json`; existing Championships remain separate.

**Motorsport settings → Seasons**, with **rules** permission, controls:

| Setting | Default | What it does |
| --- | --- | --- |
| Name | Server season | Name shown above the standings. |
| Length | Monthly | Weekly, monthly, custom end date or open-ended. |
| Repeat | On | Start a successor when this season ends. |
| Race finishes | On | Award the editable finishing-points table. |
| Finish points | 25,18,15,12,10,8,6,4,2,1 | Points by counted finishing position. |
| Clean-race bonus | On; 5 points | Extra points for a clean-race award. |
| Rivals medals | Off; Bronze/Silver/Gold 5/10/20 | Confirmed medals only; improvements pay the increase. |
| Weekly targets | Off; 10 points | Each published target once per driver in that season. |
| Separate class tables | Off | When on, points and wins use finishers' positions within each class. Otherwise use overall positions. |
| Minimum races | 1 | Races needed to appear as ranked; allowed 0–1000. |
| Drop worst results | 0 (off) | Ignore that driver's worst N race scores, including their clean bonuses; allowed 0–1000. |
| Scoring crew members | 2 | Best members scoring per race, board or weekly target; allowed 1–12. |

Seasons use UTC: weekly starts Monday and monthly follows calendar months.
A custom end date includes that whole UTC day; repeating custom seasons reuse
the original duration. Open-ended seasons wait for staff to end them. Scoring
changes apply to the next season; turning Repeat off prevents a successor.
Staff can rename, extend or end the active season, or start one after it ends.

Only finishers occupy class finishing places. The official result is unchanged.
Dropped driver scores do not rewrite earned crew contributions. Medal points
belong to the season active at confirmation; crew membership is taken when
points are earned. At season end, champions/top three are archived and season
achievements are awarded; Crew Champion uses membership at the end. Points
reset for the next season, while licences, XP, medals and achievements remain.

### Driver cards

Click a driver's name in **Grid** or **Drivers** to open the side card: licence
requirements, crew, XP/level, title, achievements/rarity, medals, season ranks
and lifetime race statistics. The card scrolls independently; Close driver card
returns to the same screen. Provisional medals show their explanation here too.

### Rival notices

When another driver's new verified board best passes your previously faster
time, an **eight-second** top-right notice names the driver, race, class and
gap to **two decimal seconds**. A first-time challenger can notify you; ties,
your own laps and improvements by someone already ahead do not. Removing the
source lap or blocking the driver removes the affected notices.

On joining, a list shows the **newest five unseen** notices. Each driver's
inbox retains the **newest 20**. **Grid → Rival notices** is on by default and
saved locally; muted notices are still marked seen rather than waiting until
you unmute. This setting is independent of Reward pop-ups.

**Race their ghost** uses the rival's current verified, unblocked best and the
normal Rivals start checks. On another map it says **Join map to race this
ghost**; missing targets say **This lap is no longer available**. A wrong car,
class or changed rules can still prevent starting. The server cannot confirm that the game received a notice: a disconnect at delivery can suppress a notice.

### Motorsport permissions and race rules

Everyone can read **Motorsport settings**; saving requires the relevant BJR
group permission. Default minimum groups are **weekend: mod**, **rules: admin**,
**raceControl: mod**. The highest BJR group always has access; staff with rules
permission can change these minimum groups in **Permissions**. Rules permission
also covers licences, crews/seasons settings, track settings and the Discord
records switch. Race-control permission covers Rivals moderation and crew
rename/remove. A normal player can manage their own crew and title.

Choose server defaults or a specific saved race before editing Race rules.
These are fresh defaults; an existing server's saved rules take precedence:

| Controls | Fresh default | Meaning |
| --- | --- | --- |
| Classes and PI | All E–X classes; no minimum/maximum | Restrict eligible builds; PI uses 100–999. |
| Minimum skill/safety/licence | 0 / No limit / No limit | Optional Join/Ready requirements. |
| Series/model/configuration | Blank | Optional required car/configuration. |
| Factory-only part groups | Any | Engine, drivetrain, suspension, tyres and body allowed unless capped. |
| Engine/weight/brake upgrades | Race maximum | Limit installed upgrade levels. |
| Induction/engine swaps/radiators/nitrous | Allowed | Allow or prohibit those parts. |
| Drivetrain conversion | Any | Limit the driven-wheel conversion. |
| Tyre compound/width | Slick maximum / +40 mm | Limit compound and width upgrades. |
| Slick compounds | All four allowed | Supersoft, soft, medium and hard can be restricted individually. |
| Setup/fuel/aero/differential changes | Allowed | Whether the corresponding adjustments are available. |
| Differential modes | Open, LSD, locked allowed | Limit the differential type. LSD means limited-slip differential. |
| Centre split | Adjustable, 0.2–0.8 | Allowed share of drive sent through the centre differential. |
| Maximum preload / lock | 500 / 100 | Limits in the units shown by Setup. |
| ABS / traction control / stability control | Driver choice | Driving aids can be forced on or off. |
| Tyre wear | Driver choice | Allow the selected wear setting. |
| Fixed track temperature | Off; 30 °C when enabled | Override varying track temperature. |
| Start/grid | Standing / Join order | Grid alternatives include qualifying, reverse and handicap; reverse-top defaults to 6. |
| Legacy rule practice/qualifying minutes | 0 / 0 | Separate from the weekend defaults above; 0 means none. |
| Start lights / false-start penalty | Off / 0 seconds | Optional start procedure; movement tolerance defaults to 0.75 m. |
| Pace speed | 80 km/h | Pace/rolling procedure speed. |
| Safety scoring / yellow flags | Off / Off | Enable incident scoring or race-control flags. |
| Track limits | Invalidate lap | Off, invalidate lap, or time penalties. |
| Cut penalty | After 3 allowed cuts; 5 seconds each | Used only in penalty mode. |

Use the current slider labels for units and legal ranges. Saved rules can
restrict parts even when the workshop offers them outside that event. The
rules do not turn server verification into a guarantee of unmodified car physics.

### Track settings

**Motorsport settings → Track settings** needs **rules** permission. Settings
are per map. Rubber, wind and weather overrides start **off**:

| Group | Fresh defaults | What changes when enabled |
| --- | --- | --- |
| Rubber | Initial 20%; full build-up 40 laps; dry bonus 3%, wet penalty 5%; close/far marble size 5×/12× | Racing-line grip/build-up and visible marble size. Legacy distance-based build-up uses 50 km. |
| Wind | 15 km/h, direction 0°, gust 5 km/h, period 12 s | Shared wind and gust pattern. |
| Weather | Cloud 0.3, fog 0.0002, rain 0; noon 24 °C, dusk 19 °C, midnight 13 °C, dawn 15 °C | BJR-synced weather and the temperature cycle. |

Read the help beside each slider before applying it. Race-specific fixed
conditions can override general track conditions. BJR weather changes are read
back into the track panel. KTS is optional; tyre telemetry is unavailable when
it does not supply that data. Fluid Spill remains a separate mod with its own
server plugin; these settings do not install pit servicing.

### Client display settings

These are personal controls, not staff permissions:

| Control | Default | Saved on this device? |
| --- | --- | --- |
| Grid: Driving HUD / Timing tower | On / On | For this UI session. |
| Grid: Fuel strategy HUD | On | For this UI session. |
| Grid: Proximity radar | Off | Yes. |
| Radar position / brightness | Lower centre / 75% (30–100%) | Yes. |
| Rivals: Target ghost / Your best ghost | On / On | Yes; also follow BJR activity markers. |
| Grid: Reward pop-ups | On | Yes; race cards and reward notices. |
| Grid: Rival notices | On | Yes; overtakes and join list; delivery still marks seen. |

## Add a car, engine or drivetrain

Stop BeamMP first. Add recipient cars to `Resources/Client/`. Add donor exports
to `BJRME-donors/custom/engines/` and/or `custom/drivetrains/`; place a copy in
both to offer both independently. Run the launcher again. No source editing or
manual part extraction. See [custom donors](CUSTOM-DONORS.md) for supported
formats, duplicates and removal. Changing donors/cars is handled by preflight;
the console software-update command below has a different purpose.

## BeamMP console commands

Type these in the **server console**, not in-game chat or the GE Lua console:

| Command | Action |
| --- | --- |
| `bjrme help` | List the commands. |
| `bjrme check-update` | Check the configured GitHub repository for a newer stable release. |
| `bjrme update` | Download the native release, check its SHA-256 and file manifest, and stage it for the next launcher start. |
| `bjrme update-status` | Show the last result or error. |
| `bjrme optional` | List optional mods (Kagoni's Tyre Simulation, Fluid Spill, Dynamic Damage Particles) that are missing or not at the version BJR:ME was tested with, and check again. |
| `bjrme get <mod>` | Download `kts`, `fluidspill` or `ddp` from its official page, check it is the tested version, and stage it for the next launcher start (Fluid Spill comes with its own server plugin). |
| `bjrme optional ignore <mod>` | Stop reminding you about a mod you don't want; `bjrme optional unignore <mod>` brings the reminder back. Staff can do the same from Motorsport settings → Optional mods. |

Checking/downloading runs in the background. It does not stop a race, rewrite
live plugins, change the active mod ZIP or issue `reloadmods`. Commands are
registered only on BeamMP's console-input hook; no player chat command is added.

After `bjrme update` reports **verified and staged**:

1. Finish the session and stop BeamMP normally. Wait for the launcher to exit.
2. Start the supplied launcher again. Its staged executable backs up and installs
   the release while BeamMP is stopped, then normal preflight regenerates parts.
3. Have players reconnect. They download the updated client mod when joining.

If a lock remains after a crash, inspect running processes before removing it.
Never delete a lock from a running server. Failed file installation restores
already-written files. Backups are in `.raceprep-update/backups/<timestamp>/`.
If installation succeeds but the new generator fails, BeamMP stays stopped;
fix the source error or restore that backup before retrying. Keep backups until
satisfied; remove old backup folders manually when no longer needed.

Custom donors, `updates.json`, rules/ratings/history, original BJR files and
other client car mods are excluded from managed replacement. The release
manifest also removes obsolete **previously release-owned** files; it does not
remove arbitrary files in the installation. Update staging/status/logs remain
local and are not shipped to players.

## Automatic update checks

Releases come from **https://github.com/Sillyw0rld/bjr-motorsport-expansion-public/releases**. The server checks at startup and then
every 24 hours, and tells you in the console when a newer release is out. It
**notifies only**: it never downloads or installs by itself. `bjrme update`
downloads the new release for your edition (Play or Custom) and platform, checks
its SHA-256, and stages it for the next launcher start.

To change the interval (1–168 hours) or switch checks off, copy
`Resources/Server/RacePrep/updates.example.json` to `updates.json` beside it and
edit it; `"enabled": false` disables the checker and console downloads. Your
`updates.json` survives updates; releases ship only the example.

If a command fails, use `bjrme update-status` and read `.raceprep-update.log`
in the server directory. A missing release, rate limit, missing native asset,
invalid version or missing/mismatched SHA-256 is reported and leaves the running
server alone. Requests have network timeouts; stalled requests must be resolved
before retrying. Do not remove `request.lock` while its process is active.

## Outside the console

From the server directory, use the native executable:

```sh
./bjrme-generator/bjrme-generator --beammp . --update-check
./bjrme-generator/bjrme-generator --beammp . --update-stage
./bjrme-generator/bjrme-generator --beammp . --check
```

Windows executable: `bjrme-generator\bjrme-generator.exe`.
The last command checks **generated parts**, rather than software releases.
Always install staged releases through the launcher; it can replace the old
Windows executable while running the separate staged executable.


## Discord posts

Both kinds of posts are **off by default**. Configure the existing awards
webhook before enabling either:

1. Make sure `curl` is available to the server.
2. Copy `Resources/Server/RacePrep/awards-discord.example.json` to
   `awards-discord.json` in the same folder.
3. Add your Discord incoming webhook URL and set `enabled` to `true`. Keep
   this file private: it contains the secret URL. No bot token is needed.
4. Newly saved **race awards** can now post the race name and award winners.
   Weekend awards use only the race phase. BJR's own Discord posts are separate.
5. For **Rivals record changes**, also enable **Motorsport settings → Permissions
   → Post new Rivals records to Discord** and Save, with rules permission.
   This second switch defaults off. Only a different driver taking the record
   posts; empty-board seeds and the current holder's improvements are silent.

Posts use names, race/class and time, not account identifiers; mentions are
disabled. `awards-discord-queue.json` holds pending and completed requests.
Sending runs in the background with a 15-second request limit. Failed or
interrupted posts are held for inspection instead of automatically resent,
because Discord might already have accepted them. Do not delete the saved
requests as cleanup. Stop the server for manual recovery after checking Discord
and ensuring no old sender is active. Temporary `.cfg` files also contain the
webhook and must remain private. Setting webhook `enabled` to false stops new
sends, though an already-running request may finish.

## Server data files

All names below are relative to `Resources/Server/RacePrep/`. **Back up the whole
folder while the server is stopped**, plus your BJR data, car mods, custom
donors and client saved setups. Do not restore only one linked progression file
while leaving the others from a different backup.

For the newer features, a damaged file stops that feature from writing; the
original remains available to restore. **Older settings, ratings and track
files are not uniformly protected this way**: some fall back to defaults or
ignore unreadable entries and may later overwrite them. Restore their backup
before restarting or saving anything. A missing file may use its `.bak` when
one exists; a present but unreadable file is not automatically replaced by its
backup. Never delete data or active lock files to dismiss an error.

| File or file family | Holds | Back up? | If missing or damaged |
| --- | --- | --- | --- |
| `rules.json` | Default and per-race rules | Yes | Missing/unreadable rules can be replaced with defaults at startup; restore before starting. |
| `motorsport.json` | Permissions, weekend, licence, crew, season and Discord-record settings | Yes | Missing/unreadable settings use defaults; restore before saving. |
| `ratings.json` | Saved car ratings | Yes | Falls back to shipped ratings where possible; startup fails without usable ratings. Restore custom ratings. |
| `skills.json` | Skill ratings and the information linking driver progress | Essential | Invalid data starts a new store; restore it together with driver/progression files before racing. |
| `drivers.json` | Races, wins, distance and safety | Essential | Legacy profile loading can use an empty store; progression import stops on an existing unreadable file. Restore before racing. |
| `championships.json` | Staff-run championships | Yes | Invalid structure can start an empty championship store; restore first. |
| `history/*.json` | Race, session and verified Rivals results | Essential | Unreadable results are skipped, not repaired; restore missing/corrupt files for complete records. |
| `skill-pending.json` | Skill changes waiting to save | Yes | Restore with skills/history; do not clear pending changes manually. |
| `records-pending.json` | Driver/championship updates waiting to save | Yes | Restore with profiles/history; legacy loading is not a blanket corruption safeguard. |
| `progression.json` | Licences, XP, achievements, titles, medals and import status | Essential | Missing starts fresh; damaged stops progression writes and licence-limited entry until restored. |
| `progression-pending.json` | Progress waiting to finish saving | Essential | Damaged stops progression writes; restore with progression/history. |
| `crews.json` | Crews and membership history | Essential | Missing starts empty; damaged stops crew/season changes until restored. |
| `seasons.json` | Active season, old standings and Hall of Fame | Essential | Missing starts fresh; damaged stops crew/season changes. |
| `league-pending.json` | Crew/season changes waiting to finish saving | Essential | Damaged stops further changes; restore with crews/seasons/progression. |
| `weekly-rivals.json` | Published map/week targets | Yes | Missing can pick targets; damaged disables weekly targets until restored. |
| `rivals-moderation.json` | Removed times, blocked drivers and staff actions | Essential | Missing starts empty; damaged blocks Rivals rather than ignoring restrictions. |
| `rival-notices.json` | Rival inboxes and seen notices | Yes | Missing starts empty; damaged stops saving notices without replacing the file. |
| `shared-tunes.json` | Shared tunes and author credits | Yes | Missing starts empty; damaged disables sharing writes until restored. |
| `track.json` | Per-map track settings and build-up | Yes | Unreadable data can fall back to old rubber settings/defaults and be rewritten later. |
| `rubber_<map>.json` | Recorded racing line for each map | Yes, to keep the line | Invalid cells are ignored; later saves can replace unreadable content. Restore first to retain it. |
| `marbles_<map>.json` | Rubber debris on each map | Optional | Invalid cells are ignored; debris can be rebuilt by driving. |
| `rubber.json`, `marbles.json` | Older track-data files retained by updates | If present | Keep for recovery; modern line/debris use per-map files. |
| `awards-discord.json` | Private webhook and enable switch | Yes, securely | Missing/invalid configuration stops posts; it is not replaced with a new secret. |
| `awards-discord-queue.json` | Saved Discord post requests/status | Yes, securely | Damaged stops posting; interrupted sends stay held for inspection. |
| `awards-discord-job-*` (`.json`, `.cfg`, `.status`, `.response`) | Temporary post files; `.cfg` contains the webhook | Preserve during recovery; keep private | Do not change while a sender is active; inspect Discord before retrying. |
| `updates.json` | Update-check preferences | If customised | Missing uses `updates.example.json`; invalid configuration can stop checks/staging. Restore or correct it. |
| `optional-mods.json` | Which optional-mod reminders to ignore | If customised | Missing/invalid settings ignore no mods; preferences can be saved again. |
| `optional-mods-status.json` | Last optional-mod check | No | Rebuilt by the next check. |
| `updater/generation-state.json` | Which cars/donors already have parts | Optional | Missing/invalid information causes parts to be checked/rebuilt. |
| `updater/server-car-catalogue.json` | Available mod cars/configurations | No | Regenerated by the launcher; spec-car choices may be unavailable until refreshed. |
| `updater/last-run.json`, `updater/last-run.log`, `updater/tools/last-run.log` | Generator status and diagnostics | Keep for a fault report | Recreated by generation; they are not driver progress. |
| `updater/generation.lock`, `updater/server-session.lock` | Running-generator/server protection | No; inspect, do not restore as data | A remaining lock can block generation; check processes before removing it with the server stopped. |
| `updater/preflight-required.json` | Launcher/generator instructions shipped with the package | Keep the release copy | Missing or damaged support files should be restored from the matching release. |
| `host.json`, `ratings-seed.json`, `native-identity.json`, `series-native-cars.json`, `*.example.json`, `updater/` support files | Shipped defaults and support data | Keep the release; back up custom changes separately | Restore from the matching release; do not replace them with unrelated versions. |
| `*.tmp`, `*.bak` alongside the above | Temporary saves or recovery copies | Retain while recovering | Do not delete while running; inspect and restore a known good backup with the server stopped. |

Update downloads/status/backups live outside this folder in `.raceprep-update/`;
optional-mod downloads use `.bjrme-optional/`. Keep their active request locks
and backups until installation/recovery is complete. Never publish runtime
files containing private webhook URLs or player information.

## Drivers, crews and seasons (2.27)

Open **Drivers → Licence and stats** to see each licence requirement and the gap
remaining. **Achievements and titles** shows earned and locked achievements,
rarity and title chips. Click a driver in Drivers or Grid to open their card on
the right; close it with ✕. Opening the menu requests your latest progress.

In **Crews**, choose a name, a unique 2–4 letter/number tag and one of nine colour
swatches. The preview shows how your tag will appear. Your crew lists members
and its leader. Leaders can invite known drivers, accept or decline requests,
and hand over leadership. The directory shows capacity, requests and season rank.
Leaving requires confirmation; a departing leader passes leadership to the
longest-standing remaining member. The last departure removes the crew.

Staff use **Motorsport settings → Crews**, rather than the player crew screen.
**Manage crews** (Mod+ by default, configurable in Permissions) controls crew size,
scoring members, rename, tag, colour, leadership and removals. Save the limits
separately from individual crew actions. Removal requires confirmation; previously
earned season points stay recorded. Existing colours remain readable; choosing a
new colour uses the nine supported swatches. Rules permission remains necessary
to change other Motorsport settings and permissions.

**Seasons** shows the current scoring rules and remaining time. Switch Drivers /
Crews and Current season / Hall of Fame / Past seasons. Past seasons load on
demand; use **View final table** to expand one. Crew contributions identify the
members whose points counted.

## Starting a preset race (2.28)

In **Grid → Start a race**, select the current map’s layout, laps and start type.
Pick a featured Staff pick, or search All presets by name/category. **Open race
lobby** uses BJR’s API; then join and Ready through BJR. BJR refusals are shown
in the window. Leave an existing BJR or Rivals session before opening another.
The chosen preset’s current PI, car and upgrade rules apply at Ready.

Staff use **Motorsport settings → Race presets** (Rules permission). Add or
select a preset, set its name, description, category, default laps and Offered
status. At most four may be Staff picks. **Edit preset rules** uses the normal
rule editor, with a banner identifying the preset. Save writes that preset,
not the layout’s rules. Return with **Back to presets**. Duplicate starts an
unoffered copy; removing a preset requires confirmation and preserves results.
Active lobbies retain their original rule snapshot when the library changes.

Back up **`presets.json`** alongside the other persistent server JSON files.
It stores the library and lobby snapshots. A damaged file is not overwritten.
Factory Barstow muscle is a spec series: Barstow only, factory-level caps, no
conversions. Wet weather remains in Track settings; the new presets do not
silently change global weather for unrelated races.

## Daily, weekly and personal challenges (2.29)

Open **Challenges**. The top cards show one daily and two weekly targets, their
class, preset, reward and UTC expiry. Select a rated car in that class and Start.
An empty target pays for your first qualifying verified score; otherwise beat
the frozen score. Daily completion is 100 XP, each weekly 250 XP, once per pick.
Old weekly XP stays earned; old `weekly-rivals.json` is retained for backfill.

**All challenges** filters by class, preset and type. Choose a board and Start
a run even when it says **No times yet: be the first**. Close the menu to drive.
Standing-start distance requires holding still on the first grid position for
two seconds, then waiting through the five-second countdown. Consistency needs
five valid laps within one second; Tyre saver requires wear enabled and a streak
within 2% of your run's best. The marked Speed trap requires a valid completed
lap; a drive through the trap alone does not publish a score.

Select a leaderboard entry for a target. **Race ghost** appears for lap-based
types. Sector attack and Speed trap have no lap ghost. Medal thresholds display
in the board's units; provisional medals pay only when confirmed by a second
verified driver. **Rivals** shows the next driver ahead on played boards, your
notice inbox, and comparisons against any driver with a shared board.

Staff use **Motorsport settings → Challenges** (Rules permission) to enable
types/rotations and set distance laps, trap width/position and minimum tyre-saver
laps. Keep at least three types enabled for all three featured picks. Layouts
without usable start positions/straight geometry, or presets without tyre wear,
do not offer the corresponding type. Publications need layouts, offered presets
and rated server cars. Rule/layout changes can make a frozen pick unavailable.

Back up **`challenges.json`** with the existing progression and history files.
It contains frozen publications, not client claims. A damaged file must be
restored from backup; BJR:ME does not replace it with empty data.

## Rating newly installed cars (2.30)

Open **Motorsport settings → Cars and ratings** to see rated/total default cars,
Rating…, Not rated yet, or Could not rate with its reason. **Rate now** requires
Rules permission and checks for an eligible client. The worker runs automatically
when a staff member has been idle for 30 seconds in free roam, outside BJR and
Rivals. It uses one temporary default car at a time and shows **Rating new cars
(n/total)…**. Start driving or join a session to stop it. Your existing car and
parts are preserved; the background car is removed after acknowledgement.

This BeamMP build sends background spawns to the server, so regular players'
games are not used. Staff may briefly see a background vehicle during collection.
A default car whose rating was invalidated by a formula change is pending again;
a modified version of that car does not count as its factory default. Unsupported
cars stop after three attempts per UTC day and show their last failure reason.
Restarts do not reset that cap. Back up **`rating-jobs.json`** with `ratings.json`
and the other persistent files. A damaged queue must be restored, not deleted
as a routine retry mechanism.

## Upgrade any eligible car into a class (2.31)

In **Grid → Start a race → Build to class**, choose Build to D/C/B/A/S/R.
A car's factory PI must be at or below that class's top; its current PI must
be inside the class before Ready. For example, an S 704 build targeting A is
**4 PI over the A limit**. A factory-A car cannot enter Build to B by downgrading.
Missing factory PI asks you to wait for the default rating; it is not guessed.

Selecting a build preset also prepares its upgrade rules in free roam. Open
**Upgrades** and use **Quick upgrade to A** (or the selected class). Wait for
estimation, review the pending parts/tyres/weight stages, adjust any choice and
**Apply** when ready. Quick upgrade leaves a 5 PI margin under the class/preset
cap and spreads its budget across grip, brakes, weight and power. It never fits
a build without Apply. Not every car can reach every class with the allowed
parts; a draft below the minimum tells you to adjust it or choose another car.
Engine and drivetrain conversions are applied separately before searching
that engine's compatible upgrades.

**PI estimates** shows each part's estimated change and the whole draft's old
→ estimated class/PI. It is enabled normally only for the validated formula and
constants. You can turn it off locally; an unvalidated formula exposes the
explicit **Experimental PI estimates** opt-in. Unsupported estimates show a
reason. After Apply, the measured/current rating replaces the draft. If it ends
above the limit, **Over by N PI → Fit to class** prepares a removal draft. It
keeps the closest valid prediction among the combinations checked; review it
and Apply, then confirm the actual PI and Ready eligibility.

Staff can set **Build-to-class target** in the existing preset/race rule editor;
other PI/part/tyre/spec caps still apply. Existing libraries gain the six presets
once. Keep backing up `presets.json`; a migration/write failure preserves the
previous file. Preview calculations run on the client and do not authorize a
server entry. Ready and verified challenge start make the final checks.


## Engine build potential (2.33 beta)

Engine upgrades fill a share of the fitted engine's remaining potential, rather
than adding the same percentage to every engine. If an engine already makes
near its layout/size ceiling, Race intake, ECU and exhaust still reshape it,
but the peak gain may be small. Fully built Sport/Race parts retain a 3%/5%
tune floor. All part choices, rev-limit effects, boost response, mass and tuning
controls remain. Electric motors are unchanged.

**Why can't I add more power?** Your engine is close to its potential already. Fit a turbo or
supercharger (if the race allows it) or a bigger displacement to raise the limit, or swap in a
bigger engine. Engines with eight or more cylinders that are small for their layout keep more of
their potential, because they rev higher. Sport displacement counts the engine as 6 % bigger and
Race displacement as 12 % bigger.

The potential uses NA values until a turbo/supercharger is actually fitted;
merely allowing induction in the rules does not count. Draft PI estimates use
the draft's fitted aspiration. A swap uses the donor engine's layout, size and
stock curve. Existing race engine caps continue to restrict what can be fitted.

**Server settings:** beside `RacePrep.lua`, copy `engine-potential.example.json`
to `engine-potential.json`, edit it, then restart the server. The example lists
all layout ceilings in hp and reference displacements in litres, stage headroom
fractions, Sport/Race tune floors, displacement scaling bounds and the missing-
data taper. Keep the complete schema and positive numeric values. Stage
fractions must ascend and stay at or below 1; displacement bounds must be
ordered, and taper thresholds must ascend. Invalid JSON/settings are logged;
the file is left intact and the shipped defaults are used. Clients receive the
server policy automatically; editing a client's copy is not configuration for
the server. Back up **`engine-potential.json`**. It is persistent data and is
not replaced by an update. The `.example.json` and internal defaults may update.

Missing layout or displacement retains the old package percentages below
300 hp, tapering linearly to one quarter at 1,000 hp and above. Generation logs
each affected engine once. Native engines retain their real parts and use a
private compiled factory reference; no stock engine or third-party file is
rewritten. Old computed ratings are recollected; class boundaries do not change.

### Induction and boost setup (2.33.0 beta)

For an eligible NA Automation engine, fit forged internals and an upgraded
radiator, then choose **Twin-charged** or **Sequential twin turbo** in Upgrades.
Twin-charging gives immediate supercharger response before turbo takeover;
sequential turbos bring boost in early and hand over to a larger turbo. Review
the draft and Apply as usual. HUD boost gauges show the simulated pressure.
Factory-boosted engines keep their own induction devices instead of receiving a
second simulated system.

On a factory-boosted Automation engine, fit the **Race boost upgrade** to unlock
**Factory boost target** in Setup. 100% keeps stock positive boost, lower values
reduce it, and up to 115% raises it. The default is 115%, matching the Race
upgrade's former maximum. Power remains bounded by the engine-potential policy;
PI uses maximum permitted tuning even when you turn boost down. Stock and Sport
parts do not unlock this slider. Native BeamNG engines keep their existing
part-specific wastegate/boost settings.

At the package's peak-power allowance, another part may add no peak hp while
still changing low-rpm torque, response, cooling or revs. Check the dyno curve;
the displayed gains follow the fitted engine's shared build-potential budget.

### Fitted induction sounds (2.34.0 beta)

Fit a BJR:ME turbo or supercharger to an eligible naturally aspirated Automation
engine in **Upgrades**, then Apply. The added induction now uses BeamNG's own
vehicle sounds: turbo spin and hiss, Sport flutter or Race blow-off on lift,
and supercharger whine. Twin-charged builds blend the two; sequential twins
bring in the larger turbo's lower tone as revs rise. Turbo spin follows spool,
so it builds after the throttle opens. Anti-lag suppresses blow-off while it
holds boost. Ignition off or a stalled engine silences these sounds.

Use BeamNG's normal vehicle audio volume controls. There are no extra audio
files or BJR:ME sound settings. Engines with a factory turbo or supercharger
keep their own sound sources; native BeamNG induction parts remain unchanged.
Resets and part changes remove the old added sources. This changes sound only,
not power, PI or gauge behaviour.

## My preferences (2.35 beta)

The gear icon at the top of the Motorsport Expansion window opens **My preferences**: driving HUD,
timing tower, fuel strategy HUD, proximity radar (position and brightness), reward pop-ups and
rival notices. They're saved on your own computer only. Flags, false starts and penalties always
show, whatever you switch off.

### Factory-vehicle PI and the bottom of Class E (2.36.0 beta)

Buses, semis, the MD series, the trophy truck and supported heavy machinery now
show PI badges in the vehicle selector, using the same classes as cars. A
Class E event uses the normal eligibility check: these vehicles can enter when
their displayed PI meets its rules. Build to class continues to use the same
factory/current PI checks and the parts actually available for that vehicle.
It does not promise that a loader has enough upgrades to reach a higher class.

The low end now spreads slow vehicles through E rather than clipping them all
to E 100. Displayed PI is never below 100. Each existing value above 300 is
preserved; a below-300 speed or technical PI may change even when overall PI
is higher. Tuning sliders still do not change PI.

A failed or unstable measurement is flagged and uses the formula estimate,
not a lap recorded while the vehicle was damaged or tipping. The Pigeon keeps
its measured rating. The Covet Skidplate has rear skids instead of tyres and
remains unrated. Unpowered factory crash-test rigs, props, trailers and
simplified AI vehicles are outside the rated fleet.

After updating, computed cache entries from the previous formula revision are
recollected automatically. Staff-set ratings are retained. No server setting
or vehicle ZIP edit is required.
