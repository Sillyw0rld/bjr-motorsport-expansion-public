-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- offline test for raceprep/upgrades: slot listing from a car's parts tree,
-- slot change, rules. luajit tests/test_upgrades.lua (repo root)
package.path = "client/lua/?.lua;" .. package.path
local U = require("ge/extensions/raceprep/upgrades")
local ok = true
local function check(name, cond) print(string.format("%-64s %s", name, cond and "ok" or "FAIL")) ok = ok and cond end

-- an Automation-style car: main -> engine -> intake / internals / management; transmission; n2o
local tree = { chosenPartName = "car", children = {
    Camso_Engine = { chosenPartName = "eng", children = {
        Camso_Intake_d4ce4 = { chosenPartName = "intake_stock", children = {} },
        Camso_EngineInternals_d4ce4 = { chosenPartName = "int_stock", children = {} },
        Camso_EngineManagement_d4ce4 = { chosenPartName = "ecu_stock", children = {} } } },
    Camso_Transmission = { chosenPartName = "seq", children = {} },
    Camso_n2o_shot = { chosenPartName = "n2o_50", children = {} },
    Camso_Body = { chosenPartName = "body", children = {} },
} }
local partsData = {
    car = { slots2 = { { name = "Camso_Engine", allowTypes = { "Camso_Engine" }, description = "Engine", coreSlot = true },
        { name = "Camso_Transmission", allowTypes = { "Camso_Transmission" }, description = "Transmission" },
        { name = "Camso_n2o_shot", allowTypes = { "Camso_n2o_shot" }, description = "Nitrous shot" },
        { name = "Camso_Body", allowTypes = { "Camso_Body" }, description = "Body" } } },
    eng = { slots2 = { { name = "Camso_Intake_d4ce4", allowTypes = { "Camso_Intake_d4ce4" }, description = "Intake" },
        { name = "Camso_EngineInternals_d4ce4", allowTypes = { "Camso_EngineInternals_d4ce4" }, description = "Internals" },
        { name = "Camso_EngineManagement_d4ce4", allowTypes = { "Camso_EngineManagement_d4ce4" }, description = "Engine management" } } },
}
local compat = {
    Camso_Engine = { "eng" }, Camso_Intake_d4ce4 = { "intake_stock", "intake_race" },
    Camso_EngineInternals_d4ce4 = { "int_stock", "int_sport", "int_race" },
    Camso_EngineManagement_d4ce4 = { "ecu_stock", "ecu_race" },
    Camso_Transmission = { "seq", "manual" }, Camso_n2o_shot = { "n2o_50", "n2o_100" }, Camso_Body = { "body", "body2" },
}
local info = { intake_race = { description = "Race Intake" }, ecu_race = { description = "Race Engine Management" } }
core_vehicle_manager = { getVehicleData = function() return { config = { partsTree = tree }, vdata = { activePartsData = partsData }, ioCtx = {} } end }
local list = U.list(1, function(def) return compat[def.allowTypes[1]] end, info)
local by = {}
for _, e in ipairs(list) do by[e.slot] = e end
check("engine upgrades listed (intake, internals, management)", by.Camso_Intake_d4ce4 and by.Camso_EngineInternals_d4ce4 and by.Camso_EngineManagement_d4ce4 and by.Camso_Intake_d4ce4.group == "engine")
check("single-option slot (engine itself) not listed", by.Camso_Engine == nil)
check("body is not an upgrade", by.Camso_Body == nil)
check("transmission in drivetrain", by.Camso_Transmission and by.Camso_Transmission.group == "drivetrain")
check("nitrous slot offers None", by.Camso_n2o_shot and by.Camso_n2o_shot.options[1].name == "")
check("part titles from the part database", (function()
    for _, o in ipairs(by.Camso_EngineManagement_d4ce4.options) do if o.name == "ecu_race" then return o.title == "Race Engine Management" end end
end)())
local changed = U.changedTree(tree, by.Camso_Intake_d4ce4.path, "intake_race")
check("change: new part set, original tree untouched", changed.children.Camso_Engine.children.Camso_Intake_d4ce4.chosenPartName == "intake_race" and
    tree.children.Camso_Engine.children.Camso_Intake_d4ce4.chosenPartName == "intake_stock")
check("change: other slots kept", changed.children.Camso_Transmission.chosenPartName == "seq")
-- rules
check("free roam: allowed", U.allowed("engine", nil, true, false) == true)
check("elsewhere (race running): not allowed", U.allowed("engine", nil, false, false) == false)
local rules = { parts = { engine = "stock", drivetrain = "any" }, nitrous = false }
check("grid, engine factory-only: blocked", U.allowed("engine", rules, false, true) == false)
check("grid, drivetrain any: allowed", U.allowed("drivetrain", rules, false, true) == true)
check("grid, nitrous banned: blocked", U.allowed("nitrous", rules, false, true) == false)
rules.nitrous = true
check("grid, nitrous allowed even with engine factory-only", U.allowed("nitrous", rules, false, true) == true)
-- apply + undo go through BeamNG's config API
local applied = {}
extensions = { core_vehicle_partmgmt = { setPartsTreeConfig = function(t, respawn) table.insert(applied, t) end,
    saveLocal = function(fn) applied.saved = fn return true end } }
check("apply rebuilds with the new tree", U.apply(1, by.Camso_Transmission, "manual", { class = "B", pi = 600 }) and
    applied[1].children.Camso_Transmission.chosenPartName == "manual" and U.lastChange.before.pi == 600)
check("undo restores the previous tree", U.undo(1) and applied[2].children.Camso_Transmission.chosenPartName == "seq")
local sOk = U.save("Neonna GT (A 655)")
check("save setup writes a .pc config", sOk and applied.saved == "Neonna GT (A 655).pc")
check("save needs a name", U.save("  ") == false)

-- balancing that would stop a light engine (real values: TATA Dot 0.06997, Neonna GT 0.1106)
local stockBal, lightened, ultra = { mainEngine = nil }, { mainEngine = { ["$+inertia"] = -0.04 } }, { mainEngine = { ["$+inertia"] = -0.07 } }
check("TATA Dot: ultra light balancing blocked (0.06997 - 0.07 < 0)", U.inertiaProblem(0.06997, stockBal, ultra) ~= nil)
check("TATA Dot: lightened balancing allowed (0.030 left)", U.inertiaProblem(0.06997, stockBal, lightened) == nil)
check("Neonna GT: ultra light allowed (0.041 left)", U.inertiaProblem(0.1106, stockBal, ultra) == nil)
check("Miota R (0.02): lightened blocked", U.inertiaProblem(0.02, stockBal, lightened) ~= nil)
check("from lightened back to stock is always fine", U.inertiaProblem(0.03, lightened, stockBal) == nil)
check("custom balancing at its default factor is fine", U.inertiaProblem(0.07, stockBal, { mainEngine = { ["$*inertia"] = "$EngineInertiaMod" } }) == nil)

-- anchoring: an upgraded car's rating is its measured stock PI + the formula's change
do
    local readJson = function(path)
        local f = io.open("client" .. path, "r"); if not f then return nil end
        f:close()
        local h = io.popen("python3 -I tests/json2lua.py client" .. path)
        local lua = h:read("*a"); h:close()
        return assert(loadstring(lua))()
    end
    jsonReadFile = readJson
    deepcopy = function(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = deepcopy(v) end return o end
    log = function() end
    package.loaded["ge/extensions/raceprepRatings"] = nil
    local R = dofile("client/lua/ge/extensions/raceprepRatings.lua")
    local base = R.anchorBase("tata_dot")
    check("stock entry with formula baseline found (TATA Dot, measured)", base and base.source == "measured" and base.formula and tonumber(base.formula.pi))
    -- an upgrade the formula rates 20 over its stock formula value: anchored
    -- to the measured stock + 20 (whatever the formula version's baseline is)
    local fb = base.formula
    local rating = require("ge/extensions/raceprep/rating")
    local e = R.anchor({ pi = fb.pi + 20, pi_speed = fb.pi_speed + 20, pi_technical = fb.pi_technical + 20 }, "tata_dot")
    check("anchored PI = measured stock + formula change (+20) in raw space, then curved",
        e.raw.pi == base.raw.pi + 20 and e.pi == rating.curve(base.raw.pi + 20) and e.anchored and e.class == rating.classOf(e.pi))
    check("speed / technical anchored the same way",
        e.raw.pi_speed == base.raw.pi_speed + 20 and e.pi_speed == rating.curve(base.raw.pi_speed + 20) and
        e.raw.pi_technical == base.raw.pi_technical + 20 and e.pi_technical == rating.curve(base.raw.pi_technical + 20))
    local unknown = R.anchor({ pi = 500, pi_speed = 500, pi_technical = 500 }, "no_such_car")
    check("cars without a stock rating keep the blind formula value (curved once)",
        unknown.raw.pi == 500 and unknown.pi == rating.curve(500) and not unknown.anchored)
end
-- blocked parts are never fitted (missing forged internals, second charger, too-light engine)
do
    local fitted = 0
    extensions = { core_vehicle_partmgmt = { setPartsTreeConfig = function() fitted = fitted + 1 end } }
    local entry = { path = { "x" }, title = "Forced induction",
        options = { { name = "big_turbo", unsafe = "Needs forged internals before fitting this forced-induction part." },
                    { name = "small_turbo" } } }
    core_vehicle_manager = { getVehicleData = function() return { config = { partsTree = { chosenPartName = "car",
        children = { x = { chosenPartName = "", children = {} } } }, vars = {} }, vdata = {} } end }
    local okFit, why = U.apply(1, entry, "big_turbo")
    check("blocked part refused with its reason", okFit == false and tostring(why):find("forged", 1, true) and fitted == 0)
    check("allowed part in the same slot is fitted", U.apply(1, entry, "small_turbo") == true and fitted == 1)
end
-- race slick compounds (1.8.5): fitted compound, KTS preset, race rule, both axles in one rebuild
do
    U.catalog.stocks = { ["slickcar/front"] = { part = "w_front", compound = "race_soft", widthMM = 245 },
        ["slickcar/rear"] = { part = "w_rear", compound = "race_soft", widthMM = 295 } }
    U.catalog.parts.rp_hard_f = { kind = "tyre", model = "slickcar", axle = "front", compound = "race_hard", offsetMM = 0 }
    U.catalog.parts.rp_hard_r = { kind = "tyre", model = "slickcar", axle = "rear", compound = "race_hard", offsetMM = 0 }
    U.catalog.parts.rp_sport_r = { kind = "tyre", model = "slickcar", axle = "rear", compound = "sport", offsetMM = 0 }
    U.catalog.parts.rp_sport_f = { kind = "tyre", model = "slickcar", axle = "front", compound = "sport", offsetMM = 0 }
    local wheels = { chosenPartName = "car", children = {
        Camso_wheels_front = { chosenPartName = "w_front", children = {} },
        Camso_wheels_rear = { chosenPartName = "w_rear", children = {} } } }
    local rebuilt
    core_vehicle_manager = { getVehicleData = function() return { config = { partsTree = wheels, model = "slickcar" }, vdata = { model = "slickcar" } } end }
    extensions = { core_vehicle_partmgmt = { setPartsTreeConfig = function(t) rebuilt = t end } }
    check("stock Soft Race slicks: KTS preset soft", U.slickPreset(1) == "soft")
    local rules = { slickCompounds = { supersoft = false, soft = false, medium = true, hard = true } }
    check("banned stock compound blocks Ready with its name", tostring(U.compoundViolation(1, rules)):find("Soft is not allowed", 1, true) ~= nil)
    check("all compounds allowed by default", U.compoundViolation(1, {}) == nil and U.slickAllowed(nil, "supersoft"))
    wheels.children.Camso_wheels_front.chosenPartName = "rp_hard_f"
    wheels.children.Camso_wheels_rear.chosenPartName = "rp_hard_r"
    check("Hard slicks fitted: preset hard, allowed", U.slickPreset(1) == "hard" and U.compoundViolation(1, rules) == nil)
    wheels.children.Camso_wheels_rear.chosenPartName = "rp_sport_r"
    check("one slick axle decides the preset", U.slickPreset(1) == "hard")
    wheels.children.Camso_wheels_front.chosenPartName = "w_front"
    wheels.children.Camso_wheels_rear.chosenPartName = "rp_sport_r"
    check("Soft front + Sport rear: preset soft", U.slickPreset(1) == "soft")
    check("KTS type: a slick axle makes the car race", U.ktsProfile(1) == "race")
    wheels.children.Camso_wheels_front.chosenPartName = "rp_sport_f"
    check("KTS type: Sport on both axles", U.ktsProfile(1) == "sport")
    local entries = { { path = { "Camso_wheels_front" } }, { path = { "Camso_wheels_rear" } } }
    check("both axles in one rebuild", U.applyMany(1, { { entries[1], "rp_hard_f" }, { entries[2], "rp_hard_r" } }, "Hard") == true
        and rebuilt.children.Camso_wheels_front.chosenPartName == "rp_hard_f"
        and rebuilt.children.Camso_wheels_rear.chosenPartName == "rp_hard_r"
        and U.history[#U.history].label == "Hard")
end
print(ok and "ALL OK" or "FAILURES")
os.exit(ok and 0 or 1)
