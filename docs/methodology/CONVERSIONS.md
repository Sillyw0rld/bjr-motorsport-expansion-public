# How the upgrades and conversions are generated

BJR:ME gives every Automation car on a server a full upgrade path, including engine and drivetrain
conversions, without changing the car mods themselves. This is how that works and how it was tested.

## Principles
- **Additive, never edits.** Every upgrade is a real BeamNG part, generated from the car's own export
  and plugged into the slots the car already has. The original car files are untouched, and
  removing BJR:ME leaves every car as it was.
- **Generated on the server, identical for everyone.** The server builds the parts and ships them to
  every player, so ratings and race rules match for all.
- **Incremental and checked.** At start, only new or changed cars and donors get parts. Each build
  happens in a scratch folder and is checked before anything live is replaced.
- **Grounded in the car's own data.** Engine stages work through the export's engine data, tyre
  compounds come from real Automation tyres, wider tyres widen the rim and gain grip through load
  sensitivity, radiators scale the core and fan.

## Engine conversions
A curated lineup of donor engines (my own Automation exports) can be fitted to other cars.

**Choosing donors.** I scanned 287 Automation exports and classified their engines from the embedded
design data (cylinder layout, aspiration, fuel), not from file names. The lineup covers common
layouts from small turbo triples to V12s. Every donor file is pinned by checksum: if a donor changes,
it has to be checked again before it's used.

**Will it fit?** A conversion is only offered when:
- **it can run** in that car: the right engine runtime is available, and the fuel system is
  converted when the donor needs a different fuel;
- **it fits the engine bay:** the bay's shape comes from the car's Automation body data. I use a
  deliberately conservative envelope (the narrowest width, full length and lowest roof line, with
  20 mm of clearance), and the donor block, turned to the car's engine orientation, must fit inside
  it. Before trusting a car's bay data, its wheel positions and wheelbase must agree with the body
  data to within 2 mm. If anything is missing or doesn't agree, the car falls back to the strict
  rule: the new block must fit inside the old one.

**What changes.** The donor brings its torque curve, inertia, block mass and its own upgrade parts.
The car keeps its gearbox, final drive, differentials, body, tyres, and its engine's look and sound.

**How it was tested.** In an isolated game instance: full torque curves compared with the donor's,
inertia and mass checked exactly (the car's mass changes by precisely the difference between the
engine blocks), driven forwards in realistic gearbox mode with no damage, broken beams or fuel
leaks, and saved and reloaded with the conversion and its upgrades intact.

Today: 18 donor engines, about 680 checked engine and car pairs across 68 cars.

## Drivetrain conversions
Any Automation car can be converted between FWD, RWD and AWD.

**Donors.** Three donor cars of mine, identical except for their layout, so the difference between
them is the drivetrain alone. That gives exact mass steps: RWD weighs 30.6 kg more than FWD, and AWD
65.9 kg more than RWD.

**What changes.** Only the transfer case and differentials are replaced. The car keeps its own
gearbox, clutch, ratios and final drive. Converted cars get helical limited-slip differentials, with
race and welded options, and AWD gets a centre differential with an adjustable split. The extra or
saved mass is spread over the car's own chassis so balance stays realistic, and it adds up correctly
with an engine conversion.

**How it was tested.** Three cars covering all three stock layouts, each converted to the other two.
Torque was measured at every wheel (driven wheels get it, the others get none). They were driven
forwards and in reverse, with no broken beams or leaks. Engine power was unchanged and the mass steps
were exact. Undo, back-to-stock, saving and the race rules were all checked. The performance results
made sense: RWD launches quicker than FWD on a powerful car, and AWD's extra weight costs a slow car.

Today: 136 layout conversions across 68 cars.

## The rest of the workshop
Tyres (compounds and widths), aero kits, weight-reduction stages, brakes, engine stages, forced
induction, coolers and radiators are generated the same way: additive parts, checked per car, rated
by the PI system like everything else. Values come from the car's own data or from measurements.
Radiators, for example, were sized from cars that overheated in testing.

Server owners can add their own donors; see [CUSTOM-DONORS.md](../distribution/CUSTOM-DONORS.md).
