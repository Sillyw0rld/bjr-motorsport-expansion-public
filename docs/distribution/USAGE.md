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
parts. Do not start BeamMP directly when you need generation or a staged update
installed. See [installation](INSTALLATION.md) for permissions and custom paths.

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
current value, then apply the changes and use **Save setup** to keep the build.
Fitted parts determine which controls are editable. Final drive and individual
gear ratios have separate permissions; fitting a final drive does not unlock
all gears. Setup figures are estimates, not measurements of your last lap.

### Race weekend, results and driver records

Use **Grid** and **Race weekend** for the race and its procedures (practice,
qualifying, grid). **Motorsport settings** holds the permissions (who can start a
weekend or change rules), the race rules and the track settings. Class, PI and
upgrade caps can block a build from entering; check **Motorsport settings → Race
rules** before changing the car to qualify.

**Results** shows race timing and lap/sector details; cuts can invalidate a best
lap. **Drivers** shows skill, statistics and safety, with provisional status for
new records. **Championship** covers series standings. Records should come from
completed sessions; if they remain empty, report the car, track, session type,
version and server log rather than assuming races were counted. See the
[current status](../STATUS.md) for what this beta has and hasn't been checked on.

During races and sessions the standings tower, timing box and gap strip show at
the top of the screen; start lights, flags and track-limit warnings show at the
top centre.

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
