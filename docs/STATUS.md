# Current status: open beta

BJR:ME runs on my own server and is raced there with friends. This is the first public release, so
it's an **open beta**: everything below works, but it has been tested on one server, not many.
Reports help: bugs and questions go to the [Discord](https://discord.gg/m6urHk6EAK).

Built and tested on **BeamNG.drive 0.40**, **BeamMP 3.9** and **BeamJoy-Revived 2.0**.

## What's in it

| Area | In this release | Still being checked or worked on |
|---|---|---|
| Ratings | PI and classes for Automation and BeamNG cars; measured cars use their measured rating; parts change PI, tuning never does | Same-PI lap times on real circuits; tyre compounds re-measured per car |
| Automation workshop | Tyres and widths, brakes, weight stages, aero, engine stages, induction and cooling; dyno and performance figures | More cars and race nights |
| Conversions | Engine conversions (18 donors, engine-bay checked) and FWD / RWD / AWD drivetrain conversions | |
| BeamNG cars | Their compatible factory parts in the workshop, under the race rules | Generated upgrades (tyres, weight, aero, brakes, engine stages) for BeamNG cars |
| Setup | Part-dependent permissions, gearing graph, performance estimates, saved setups | |
| Racing | Race weekend (practice, qualifying, grid), start lights, penalties, track limits, flags, grids, race HUD; permissions and upgrade caps per race | |
| Records | Results and history, championships, driver skill, statistics and safety | Contacts and distance are reported by each player's game |
| Living track | Rubbered line, marbles, track temperature, wind and weather (synced through BeamJoy-Revived) | |
| Installation | Play and Custom editions, standalone generator for Windows and Linux (no Python needed), checked parts generation before the server starts | First installs on other people's servers |
| Updates | Startup and daily update check (notifies only), `bjrme update` stages the new release for the next start | |

## Good to know
- After adding or changing cars or donors, stop the server and start it with the launcher; players
  rejoin to receive the new parts.
- Performance figures in the workshop are estimates from car data, not measured laps.
- The server distributes the parts and applies the rules, but some statistics come from each player's
  game.

See the [roadmap](../ROADMAP.md) for what's next.
