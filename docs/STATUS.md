# Current status: open beta

This is documentation for the next **2.26.1 beta**, covering changes since the
2.16 public release. BJR:ME has been used on the maintainer's server; that does
not mean every new feature below has been exercised in a real multiplayer race.

## What has been checked

| Area | Evidence available | Still needs real multiplayer checking |
| --- | --- | --- |
| Ratings, Automation workshop, conversions and Setup | Earlier game measurements and maintainer-server use; automated checks for ratings, parts and permissions | More cars, same-PI races and other server setups |
| BeamNG factory/add-on parts | Earlier isolated-game part checks; factory configuration matching checked against saved car information | Tyre PI accuracy and wider model coverage |
| Rubbered line, marbles, wind and weather | Earlier in-game visual checks and maintainer-server use | Different maps, graphics settings and long sessions |
| BJR phase weekends and HUD | Automated phase/grid/result checks and browser previews | A full race night on a compatible phase-enabled BJR build |
| Verified/class Rivals, weekly targets, ghosts and moderation | Automated timing/gate/configuration and recorded-car checks; visual previews | Real network timing, ghost playback, reconnects and map changes |
| Awards, presets, shared tunes and strategy | Automated logic and UI checks | Race-night awards, tune exchange and fuel use across more cars |
| Licences, XP, medals, achievements and titles | Automated rules, recovery and copied-history import checks; browser previews | Real BJR event ordering and end-to-end multiplayer progress |
| Crews, seasons and driver cards | Automated membership/scoring/history checks; browser previews | Long-running seasons, crew changes and actual storage failures |
| Reward cards and rival notices | Automated amount/delivery logic and browser click/mute/expiry checks | Native input focus, overlay placement, join delivery and real ghost-button starts |
| Discord records/awards | Automated message/queue checks | Live webhook delivery; no real post was part of these feature checks |
| Updates and packages | Automated installation/allowed-file and export checks | First installs on more hosts and native Windows recovery behavior |

The recent competition/progression checks were offline or browser-based. They
are useful evidence, not a claim that the game was running for those checks.
See [how changes are tested](methodology/TESTING.md) for the wider process.

## Requirements and known limitations

- **Weekends require BJR phases.** The bridge names 2.0.1 as its minimum, but
  released BJR 2.0.1 has no phases. Use a compatible phase-enabled development
  build and read the startup BJR API capability lines before scheduling an event.
- **Verified Rivals needs BeamMP Server 3.9.4+ APIs:** server time, raw vehicle
  positions and received vehicle configurations. Missing APIs disable runs.
  Strong jitter can invalidate a lap. Server-observed checks cannot prove
  unchanged local vehicle physics or detect every shortcut between gates.
- **Native tyre PI is still being refined.** Workshop performance figures are
  estimates, not measured lap promises. Driver contacts/distance include data
  reported by players' games. Fuel strategy adds no pit servicing.
- **Data protection differs by file.** Newer progression/crew/season/inbox files
  stop writing when damaged; some older settings/profile/track files instead
  use defaults or skip unreadable entries. Restore backups before restarting or
  saving. The [data-file table](distribution/USAGE.md#server-data-files) explains each.
- A disconnect during delivery can suppress a notice. Failed writes can leave
  changes only in memory; restore storage before restarting after an error.
  A missed reward card does not remove already saved XP.
- Added/changed cars need parts generation and players must reconnect for changed
  mods. The launcher does this before starting; panel-started servers use the
  background check and the console's `reloadmods` instructions. Staged software
  updates require the launcher.

Report problems with the version, car, map, activity and relevant server-log
messages on [Discord](https://discord.gg/m6urHk6EAK). Remove private webhook URLs
and player information before sharing logs. See the [roadmap](../ROADMAP.md).
