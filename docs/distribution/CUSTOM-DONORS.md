# Custom Automation donors

Build and export a normal Automation vehicle to BeamNG. Keep the export ZIP,
including its `.car` design, default `.pc`, JBeam parts and info JSON. Do not
extract it or edit Python, Lua or JBeam. Use only exports you have permission to
redistribute; importing locally does not grant permission to publish them.

Both editions accept custom donors. The **Play** edition also has the bundled
donors; the **Custom** edition has none, so its conversions come only from the
donors you add. In the Custom edition, drivetrain conversions need a full set:
one FWD, one RWD and one AWD donor (with fewer, they are switched off and the
log says so). Engine donors work one by one in both editions.

With BeamMP stopped, put the ZIP in:

- **Engine:** `<server>/BJRME-donors/custom/engines/`
- **Drivetrain:** `<server>/BJRME-donors/custom/drivetrains/`
- **Both:** copy the same ZIP into both directories. These are independent
  conversion choices; selecting one never selects the other.

Run the launcher or `bjrme-generator --beammp <server>` before startup.
The log reports default/custom source counts (an export in both roles counts
once per role). Engine choices retain the export's readable configuration name,
layout, displacement and listed power. Compatible conversions appear in the
existing conversion shop; a discovered donor need not fit every recipient.

## Supported sources

The importer reuses the existing Automation scanner, factory-config selection,
engine-bay checks and engine/drivetrain builders. It resolves configured parts
by their JBeam identities rather than assuming export member filenames.

- The engine needs a recognized `.car` design, default configuration, real
  supported torque curve, positive inertia and block geometry/mass. Only the
  existing `camsoEngine` and `combustionEngine` runtimes are supported. Existing
  runtime and engine-bay restrictions still apply. The recipient's meshes/audio,
  gearbox, tyres, body and other chassis parts remain installed.
- Drivetrains need supported Automation ICE FWD/RWD/AWD graphs and the original
  structural, suspension, wheel, differential and engine-structure data. This
  is not a generic BeamNG or EV/hybrid donor importer.
- Additional drivetrain choices reuse the existing trio builder. A custom
  target replaces that layout in the reference trio; other layouts retain the
  bundled reference. Existing measured mass ordering **FWD < RWD < AWD** is
  required. An export that fails this policy is rejected, never lightened or
  retuned automatically. Recipient gearbox/ratios, existing LSD tuning behavior
  and the conversion's established 35/65 AWD split remain unchanged.
- An archive may provide multiple models, but only one selected configuration
  per model is supported. Different configurations for the same model are
  reported as a conflict; export distinct model identities if necessary.

## Identity, duplicates and updates

Custom IDs derive from model/config identity, so replacing a ZIP with an updated
export retains its identity. Relevant source members are hashed. Identical
imports with different filenames are deduplicated within each role. Conflicting
content for the same model/config in two files is an error; remove the old copy.
Similar display names with distinct model identities are allowed.

Replace the existing custom ZIP to update it. Remove it to remove that donor,
then run preflight. The affected catalogue and generated conversion files are
rebuilt; unrelated expansion assets are retained. Saved setups referencing a
removed/incompatible conversion cannot be promised to load that absent part:
restore the export or choose stock before saving again.

Bundled defaults are pinned compact author-owned sources. Their original JBeam,
config and design members are retained unchanged, with original and compact
archive hashes in manifests. Do not replace files in `default/`; add your export
under `custom/`. A damaged default is an installation error: restore the release.

`RACEPREP_DONORS` remains a lookup path for legacy direct builder tools. Public
custom discovery uses the explicit role directories above, avoiding accidental
import of every ZIP from an old mod search folder.
