# Credits

BJR:ME depends on other people's work. This page distinguishes the expansion's
own work, the projects it integrates with and the tools used to build it.
Upstream projects and separately installed mods retain their own authorship
and licences; inclusion here does not imply endorsement.

## Project author and maintainer

**[Sillyw0rld](https://github.com/Sillyw0rld)** — project direction and racing
concept, PI methodology/calibration, Automation conversion architecture,
vehicle/donor creation, test requirements, review and release decisions.
See [authorship and milestones](docs/AUTHORSHIP.md).

## Foundations and integrations

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

The bundled default donors are **Sillyw0rld's author-owned exports**, reduced to
source data needed for generation; their meshes/audio are not bundled. Other
servers' installed car mods are not thereby part of BJR:ME or relicensed under
its licence. Retain each mod's attribution and distribution permissions.

## Design inspiration

**Forza Motorsport**, by **Turn 10 Studios / Xbox Game Studios**, inspired the
class/PI presentation and workshop/setup interaction. This is an independent
BeamNG expansion, not an official Forza product. Reference screenshots are not
permission to redistribute another game's artwork.

## Development tools

- [Python and its contributors / Python Software Foundation](https://www.python.org/)
  — generation and packaging tooling; the standalone generator bundles a Python
  runtime. Python's own licence notices remain applicable.
- [PyInstaller and contributors](https://pyinstaller.org/)
  — standalone packaging. Its [licensing exception](https://pyinstaller.org/en/stable/license.html)
  permits distributing the generated application under its own licence.
- The build dependency projects listed in `packaging/requirements.txt` in the source repository:
  altgraph, packaging, pyinstaller-hooks-contrib, setuptools, and Windows build
  helpers pefile and pywin32-ctypes. This is a build-tool list, not a claim that
  every dependency is shipped as an application component.
- AI coding tools **Claude, Codex, Gemini, SWE-2 and GLM-5.3** assisted implementation,
  refactoring and review. They are tools, not additional human maintainers;
  design and release decisions belong to the project owner.

## Testing and corrections

Thanks to the friends, racers and community members who report bugs and test
race nights. Specific public names should be added with an accurate description
of their contribution and their preferred credit. We do not invent contributor
names or treat use of a mod as authorship of that mod.

Missing or incorrect credit? Open an issue or contact the maintainer with the
project, preferred public name/link and contribution so it can be corrected.

See [NOTICE](NOTICE) for legal attribution and [LICENSE](LICENSE) for the
expansion's licence.
