-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Race rules for parts and nitrous (GE side, used by the RacePrep window).
--
-- "Factory parts only" compares every installed part, slot by slot, with the
-- car's factory configuration: the part its .pc file lists for that slot, or
-- otherwise the slot's default from the parent part. If the driver picked a
-- config they saved themselves ("Custom"), the model's default config is the
-- reference, so a saved tuned config cannot pass as factory.
--
-- Slots are grouped by their slot name (works for Automation exports, which
-- name their slots Camso_*, and for most BeamNG cars). Slots that fit no group
-- (body, trim, paint) are never checked.

local P = {}

P.CATEGORIES = {
    { key = "engine", label = "Engine" },
    { key = "drivetrain", label = "Drivetrain" },
    { key = "suspension", label = "Suspension and brakes" },
    { key = "tyres", label = "Wheels and tyres" },
    { key = "body", label = "Body" },
}

-- checked in this order: the first match wins
local GROUPS = {
    { key = "body", words = { "rp_body_" } }, -- Race Prep weight reduction (raceprep/weight)
    { key = "aero", words = { "aero", "downforce", "drag_model" } },
    { key = "nitrous", words = { "n2o", "nitrous" } },
    { key = "tyres", words = { "wheel", "tire", "tyre" } },
    { key = "drivetrain", words = { "transmission", "gearbox", "differential", "finaldrive", "transfercase",
        "transfer_case", "driveshaft", "clutch", "rangebox", "converter" } },
    { key = "suspension", words = { "coilover", "swaybar", "sway_bar", "spring", "shock", "damper", "suspension",
        "strut", "brake", "hub_bearing", "steering" } },
    { key = "engine", words = { "engine", "intake", "internals", "management", "ecu", "revlimiter", "rev_limiter",
        "balancing", "turbo", "supercharger", "exhaust", "camshaft", "radiator", "oilcooler", "intercooler" } },
}

local function groupOf(slotID, native)
    local s = string.lower(tostring(slotID or ""))
    if native and (s:find('spoiler',1,true) or ('_'..s..'_'):find('_wing_',1,true)) then return 'aero' end
    if s == "camso_tuning_parameters" then return "aero" end
    for _, g in ipairs(GROUPS) do
        for _, w in ipairs(g.words) do
            if s:find(w, 1, true) then
                return g.key
            end
        end
    end
end
P.groupOf = groupOf

local function partLabel(vdata, part)
    if not part or part == "" then
        return "none"
    end
    local data = vdata and vdata.activePartsData and vdata.activePartsData[part]
    local info = data and data.information
    return info and info.name or part
end

-- slot default from the parent part's slot list (slots2 = format 2 jbeam)
local function slotDefault(vdata, parentPart, slotID)
    local data = vdata and vdata.activePartsData and vdata.activePartsData[parentPart]
    if not data then
        return nil
    end
    for _, s in ipairs(data.slots2 or {}) do
        if s.name == slotID then
            return s.default or ""
        end
    end
    -- old slot tables: header row, then {type, default, description}
    for i, s in ipairs(data.slots or {}) do
        if i > 1 and type(s) == "table" and s[1] == slotID then
            return s[2] or ""
        end
    end
    return nil
end

--- the parts list of the factory config this car is compared with
local function factoryConfigParts(vehData)
    local config = vehData.config or {}
    local model = config.model
    local key = config.partConfigFilename and config.partConfigFilename:match("([^/]+)%.pc$")
    local modelData = model and core_vehicles and core_vehicles.getModel and core_vehicles.getModel(model)
    local configInfo = modelData and modelData.configs and key and modelData.configs[key]
    local usedKey = key
    if not configInfo or configInfo["Config Type"] == "Custom" then
        usedKey = modelData and modelData.model and modelData.model.default_pc or key
    end
    if not model or not usedKey then
        return nil, nil
    end
    local pc = jsonReadFile(string.format("vehicles/%s/%s.pc", model, usedKey))
    if type(pc) ~= "table" or type(pc.parts) ~= "table" then
        return nil, usedKey
    end
    return pc.parts, usedKey
end

--- every installed slot: {id, group, part, stock, label, stockLabel}
local function compare(vehData)
    local factory, reference = factoryConfigParts(vehData)
    local vdata = vehData.vdata
    local out = {}
    local native=false
    for _,device in pairs(vdata and vdata.powertrain or {}) do
        local kind=device.type or device[1]
        if kind=='camsoEngine' then native=false;break end
        if kind=='combustionEngine' or kind=='electricMotor' then native=true end
    end
    -- Native-runtime Automation exports still use their Automation slot tree.
    local config=vehData.config or {}
    if (factory and factory.Camso_Engine) or (config.parts and config.parts.Camso_Engine) or
        (config.partsTree and config.partsTree.children and config.partsTree.children.Camso_Engine) then native=false end
    local function walk(node, parentPart)
        if node.id and node.id ~= "main" then
            local group = groupOf(node.id,native)
            if group then
                local part = node.chosenPartName or ""
                local stock
                if factory and factory[node.id] ~= nil then
                    stock = factory[node.id]
                else
                    stock = slotDefault(vdata, parentPart, node.id)
                end
                table.insert(out, {
                    id = node.id,
                    group = group,
                    nativeAero = native and group=='aero' or nil,
                    part = part,
                    stock = stock,
                    label = partLabel(vdata, part),
                })
            end
        end
        for _, child in pairs(node.children or {}) do
            walk(child, node.chosenPartName)
        end
    end
    if vehData.config and vehData.config.partsTree then
        walk(vehData.config.partsTree, nil)
    end
    return out, reference, factory ~= nil, native
end

local cache = { key = nil, result = nil }

--- slot comparison for a vehicle, cached until its parts change
P.inspect = function(gameVehID)
    local ext = rawget(_G, "extensions")
    local vehData = gameVehID and ext and ext.core_vehicle_manager and
        ext.core_vehicle_manager.getVehicleData(gameVehID)
    if not vehData or not vehData.config then
        return nil
    end
    local key = tostring(gameVehID) .. ":" .. tostring(vehData.config.partsTree)
    if cache.key ~= key then
        local slots, reference, haveFactory, native = compare(vehData)
        cache.key = key
        cache.result = { slots = slots, reference = reference, haveFactory = haveFactory, native = native }
    end
    return cache.result
end

--- BeamNG factory engine parts for the upgrade caps (owner 2026-10-21: mapped
--- to the existing caps): a turbo / supercharger kit counts as forced
--- induction, any other factory engine part as an engine conversion. Gearbox,
--- suspension / brakes, wheels / tyres and wings keep their own rules (the
--- per-area "factory only" rows and the aero rule). Race Prep's own generated
--- parts (rp_*) are classified by raceprep/upgrades instead.
function P.factoryRuleItem(name, label)
    name = tostring(name or "")
    if name == "" or name:match("^rp_") then return nil end
    local text = (name .. " " .. tostring(label or "")):lower()
    if text:find("turbo", 1, true) or text:find("supercharg", 1, true) or text:find("blower", 1, true) or text:find("twincharg", 1, true) then
        return { kind = "induction", factory = false, title = label or name }
    end
    return { kind = "engineConversion", title = label or name }
end

--- the factory engine parts a BeamNG car has that differ from its spawned
--- configuration, as upgrade-cap items (empty for Automation cars)
function P.factoryRuleItems(gameVehID)
    local info = P.inspect(gameVehID)
    local out = {}
    if not info or not info.native then return out end
    for _, s in ipairs(info.slots) do
        if s.group == "engine" and s.stock ~= nil and s.part ~= s.stock then
            local item = P.factoryRuleItem(s.part ~= "" and s.part or nil, s.label)
            if item then out[#out + 1] = item end
        end
    end
    return out
end

--- the spawned configuration's part for a slot of a BeamNG car (nil when unknown or Automation)
function P.factoryPart(gameVehID, slotID)
    local info = P.inspect(gameVehID)
    if not info or not info.native then return nil end
    for _, s in ipairs(info.slots) do if s.id == slotID then return s.stock end end
end

--- why the car breaks the parts or nitrous rules, or nil; plus the full list
---@return string? short, string[] details
P.violation = function(gameVehID, rules)
    local parts = type(rules.parts) == "table" and rules.parts or {}
    local anyStock = false
    for _, c in ipairs(P.CATEGORIES) do
        anyStock = anyStock or parts[c.key] == "stock"
    end
    if rules.nitrous ~= false and rules.aero ~= false and not anyStock then
        return nil, {}
    end
    local info = P.inspect(gameVehID)
    if not info then
        return nil, {}
    end
    local details = {}
    local short
    for _, s in ipairs(info.slots) do
        if s.group == "aero" and rules.aero == false and ((s.nativeAero and s.stock~=nil and s.part~=s.stock) or (s.part ~= "" and tostring(s.part):match("^rp_aero_"))) then
            table.insert(details, (s.nativeAero and "Non-stock aero fitted: " or "Aero kit fitted: ") .. s.label)
            short = short or "aero must be stock"
        elseif s.group == "nitrous" and rules.nitrous == false and s.part ~= "" then
            table.insert(details, "Nitrous fitted: " .. s.label .. " (" .. s.id .. ")")
            short = short or "nitrous not allowed"
        elseif parts[s.group] == "stock" and s.stock ~= nil and s.part ~= s.stock then
            local label = "?"
            for _, c in ipairs(P.CATEGORIES) do
                if c.key == s.group then label = c.label end
            end
            table.insert(details, string.format("%s: %s fitted, factory part is %s (%s)",
                label, s.label, s.stock == "" and "none" or s.stock, s.id))
            short = short or (string.lower(label) .. " must be factory parts")
        end
    end
    if anyStock and not info.haveFactory then
        table.insert(details, "The factory configuration of this car could not be read; parts were compared with slot defaults.")
    end
    return short, details
end

return P
