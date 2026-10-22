-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Race rules for upgrades (Motorsport settings > Race rules > Upgrades): caps on
-- what a car may have fitted for a race, on top of its class / PI limit. PI
-- limits overall speed; these caps make Stock, Street or Sport series possible.
--
-- rules.upgrades (server RacePrep.lua sanitizes it; missing = most permissive):
--   engine               none | street | sport | race   (engine parts level)
--   induction            none | factory | allow         (turbo / supercharger)
--   engineConversion     true | false
--   drivetrainConversion off | fwdrwd | any
--   compound             road | sport | semi | slick    (softest tyre allowed)
--   width                0 | 20 | 40                    (mm over stock)
--   weight               none | street | sport | race   (body stages)
--   brakes               factory | sport | race
--   radiators            true | false                   (radiators and coolers)
-- Aero kits and nitrous keep their own rules (rules.aero, rules.nitrous).
--
-- An item is one fitted (or offered) upgrade, classified by upgrades.lua:
--   {kind='engine', rank=1..3}   rank 1 street, 2 sport, 3 race (see ENGINE_RANK)
--   {kind='induction', factory=bool}  {kind='cooling'}
--   {kind='engineConversion'}  {kind='drivetrainConversion', layout='FWD'|'RWD'|'AWD'}
--   {kind='tyre', compound=..., offset=mm}  {kind='body', stage=...}
--   {kind='brake', level=...}  {kind='aero'}  {kind='nitrous'}
-- Plain Lua, no game API: tests run it directly.
local R = {}

R.DEFAULTS = { engine = "race", induction = "allow", engineConversion = true, drivetrainConversion = "any",
    compound = "slick", width = 40, weight = "race", brakes = "race", radiators = true }

local LEVEL = { none = 0, street = 1, sport = 2, race = 3 }
local LEVEL_LABEL = { none = "none", street = "Street", sport = "Sport", race = "Race" }
local BRAKE = { factory = 0, sport = 1, race = 2 }
local COMPOUND_RANK = { road = 0, sport = 1, semi = 2, slick = 3 }
local COMPOUND_LABEL = { road = "Road", sport = "Sport", semi = "Semi-slick", slick = "Slick" }

--- engine part level from its effect, matching the engine packages: Stage 1
--- (sport intake / exhaust / ECU) is Street, Stage 2 (race intake / exhaust /
--- ECU, sport cam) is Sport, Stage 3 (race cam, forged internals, displacement)
--- is Race. nil = not an engine-level part (induction, coolers...).
R.ENGINE_RANK = {
    intake = { sport = 1, race = 2 }, exhaust = { sport = 1, race = 2 }, ecu = { sport = 1, race = 2 },
    flywheel = { sport = 1, race = 2 }, cam = { sport = 2, race = 3 }, displacement = { sport = 3, race = 3 },
}
function R.engineRank(effect)
    if type(effect) ~= "table" then return nil end
    local rank
    if effect.forged then rank = 3 end
    for kind, levels in pairs(R.ENGINE_RANK) do
        local r = levels[effect[kind]]
        if r and (not rank or r > rank) then rank = r end
    end
    return rank
end

--- tyre compound name (catalogue / KTS) -> road | sport | semi | slick
function R.compoundClass(compound)
    compound = tostring(compound or "")
    if compound:match("^race") then return "slick" end
    if compound == "semi_slick" then return "semi" end
    if compound == "sport" then return "sport" end
    return "road"
end

--- the caps in force: rules.upgrades merged over the most permissive defaults
function R.caps(rules)
    local u = type(rules) == "table" and type(rules.upgrades) == "table" and rules.upgrades or {}
    local out = {}
    for k, v in pairs(R.DEFAULTS) do
        if u[k] ~= nil then out[k] = u[k] else out[k] = v end
    end
    return out
end

--- why this item is not allowed under the race rules, else nil
function R.block(rules, item)
    if type(item) ~= "table" then return nil end
    local c = R.caps(rules)
    local k = item.kind
    if k == "engine" then
        local cap = LEVEL[c.engine] or 3
        if (item.rank or 0) > cap then
            return cap == 0 and "Race rules: no engine upgrades" or ("Race rules: engine parts max " .. LEVEL_LABEL[c.engine])
        end
    elseif k == "induction" then
        if c.induction == "none" then return "Race rules: no forced induction" end
        if c.induction == "factory" and not item.factory then return "Race rules: factory forced induction only" end
    elseif k == "cooling" then
        if c.radiators == false then return "Race rules: no radiator or cooler upgrades" end
    elseif k == "engineConversion" then
        if c.engineConversion == false then return "Race rules: no engine conversions" end
    elseif k == "drivetrainConversion" then
        if c.drivetrainConversion == "off" then return "Race rules: no drivetrain conversions" end
        if c.drivetrainConversion == "fwdrwd" and item.layout == "AWD" then return "Race rules: FWD and RWD conversions only" end
    elseif k == "tyre" then
        local cap = COMPOUND_RANK[c.compound] or 3
        local class = R.compoundClass(item.compound)
        if COMPOUND_RANK[class] > cap then return "Race rules: tyres max " .. COMPOUND_LABEL[c.compound] end
        local width = tonumber(c.width) or 40
        if (tonumber(item.offset) or 0) > width then
            return width == 0 and "Race rules: no wider tyres" or ("Race rules: tyres up to +" .. width .. " mm")
        end
    elseif k == "body" then
        local cap = LEVEL[c.weight] or 3
        if (LEVEL[item.stage] or 0) > cap then
            return cap == 0 and "Race rules: no weight reduction" or ("Race rules: weight reduction max " .. LEVEL_LABEL[c.weight])
        end
    elseif k == "brake" then
        local cap = BRAKE[c.brakes] or 2
        if (BRAKE[item.level] or 0) > cap then
            return cap == 0 and "Race rules: factory brakes only" or ("Race rules: brakes max " .. (c.brakes == "sport" and "Sport" or "Race"))
        end
    elseif k == "aero" then
        if type(rules) == "table" and rules.aero == false then return "Race rules: stock aero" end
    elseif k == "nitrous" then
        if type(rules) == "table" and rules.nitrous == false then return "Race rules: no nitrous" end
    end
    return nil
end

--- first fitted item the race rules do not allow: reason, item; nil when all allowed
function R.violation(rules, items)
    for _, item in ipairs(items or {}) do
        local why = R.block(rules, item)
        if why then return why .. (item.title and (" (" .. tostring(item.title) .. " fitted)") or ""), item end
    end
    return nil
end

return R
