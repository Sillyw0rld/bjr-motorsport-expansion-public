-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Forza-style weight reduction (Upgrades > Body) as real car parts.
--
-- Automation exports scale every node by $nodeWeightScale: the body part sets
-- "scalenodeWeight" at part level, BeamNG turns that into a vehicle option
-- seeding every node row, so mass drops by exactly the stage's share and the
-- centre of gravity stays put. The variable only exists when a part defines
-- it, so Race Prep generates per car (tools/generate_upgrade_body.py):
--   rp_body_<id>_<stage>  in slot rp_body_<id>: defines $nodeWeightScale at
--                         the stage's fixed value
--   rp_body_<id>_holder   in camso_tuning_parameters: no aero change, only
--                         carries that slot when no aero kit is fitted (the
--                         aero kits carry it too)
-- Being parts, stages join the rating identity, "Factory parts only" and
-- undo like any upgrade. Node weight is read when the car loads, so fitting
-- reloads the car.
local W={}
W.VAR='$nodeWeightScale'
W.TUNING_SLOT='camso_tuning_parameters'
W.STAGES={
    {key='stock',label='Stock body',scale=1,percent=0},
    {key='street',label='Street: spare wheel and tools',scale=0.96,percent=4},
    {key='sport',label='Sport: all seats removed',scale=0.93,percent=7},
    -- no extra PI on top of the lower mass: the rig showed the formula already
    -- captures it (+3 % over-rated, owner 2026-10-21); a stage may still set
    -- bonus=<share> and every consumer follows
    {key='race',label='Race: stripped race car',scale=0.85,percent=15},
}
local function finite(n) n=tonumber(n);return n and n==n and math.abs(n)<math.huge and n or nil end
function W.find(key) for _,st in ipairs(W.STAGES) do if st.key==key then return st end end end
local function modelOf(d) return d and ((d.vdata or {}).model or (d.config or {}).model) end
--- this car's generated body parts: {ident, slot, holder, stages={key=name}} or nil
function W.parts(catalog,model)
    if not catalog or not model then return nil end
    if catalog._indexedParts~=catalog.parts or not catalog.byModel then
        local byModel={}
        for name,p in pairs(catalog.parts or {}) do
            if type(p)=='table' and p.model then
                local m=byModel[p.model]
                if not m then m={};byModel[p.model]=m end
                m[name]=p
            end
        end
        catalog.byModel,catalog._indexedParts,catalog._bodyByModel=byModel,catalog.parts,{}
    end
    catalog._bodyByModel=catalog._bodyByModel or {}
    local cached=catalog._bodyByModel[model]
    if cached~=nil then return cached or nil end
    local out
    for name,p in pairs(catalog.byModel[model] or {}) do
        if p.model==model and (p.kind=='body' or p.kind=='bodyHolder') then
            local id=name:match('^rp_body_(%x+)_')
            out=out or {ident=id,slot='rp_body_'..id,stages={}}
            if p.kind=='bodyHolder' then out.holder=name else out.stages[p.stage]=name end
        end
    end
    catalog._bodyByModel[model]=out or false
    return out
end
local function findSlot(node,slot)
    for id,child in pairs(node and node.children or {}) do
        if id==slot then return child end
        local found=findSlot(child,slot);if found then return found end
    end
end
local function copyTree(t)
    if type(t)~='table' then return t end
    local out={};for k,v in pairs(t) do out[k]=copyTree(v) end;return out
end
--- stage key of a parts tree
function W.treeStage(tree,catalog,model)
    local p=W.parts(catalog,model);local tp=p and findSlot(tree,W.TUNING_SLOT)
    local node=tp and tp.children and tp.children[p.slot]
    local name=node and node.chosenPartName
    for key,part in pairs(p and p.stages or {}) do if part==name then return key end end
    return 'stock'
end
--- the parts tree with a body stage fitted, or nil and why
function W.applyTree(tree,catalog,model,key)
    local p=W.parts(catalog,model)
    if not p or not p.holder then return nil,'This car has no body upgrades.' end
    if key~='stock' and not p.stages[key] then return nil,'Unknown body stage.' end
    local t=copyTree(tree);local tp=findSlot(t,W.TUNING_SLOT)
    if not tp then return nil,'This car has no body upgrade slot.' end
    local current=tp.chosenPartName or ''
    local own=(catalog.parts[current] or {}).kind
    if current~='' and own~='aero' and own~='bodyHolder' then
        return nil,"Remove Automation's advanced tuning parameters (aero kit slot) first."
    end
    if key=='stock' then
        if current==p.holder then tp.chosenPartName='';tp.children={}
        elseif tp.children and tp.children[p.slot] then tp.children[p.slot]={chosenPartName='',children={}} end
    else
        if current=='' then tp.chosenPartName=p.holder;tp.children={} end
        tp.children=tp.children or {}
        tp.children[p.slot]={chosenPartName=p.stages[key],children={}}
    end
    return t
end
--- an aero kit change keeps the fitted body stage (kits and holder share the slot)
function W.carry(oldTree,newTree,catalog,model)
    local key=W.treeStage(oldTree,catalog,model)
    if key=='stock' then return newTree end
    return W.applyTree(newTree,catalog,model,key) or newTree
end
function W.available(d,catalog)
    return W.parts(catalog,modelOf(d))~=nil and d.config~=nil and findSlot(d.config.partsTree,W.TUNING_SLOT)~=nil
end
--- fitted stage (from the car's installed parts)
function W.stage(d,catalog)
    local p=W.parts(catalog,modelOf(d))
    for _,name in pairs(((d or {}).vdata or {}).activeParts or {}) do
        for key,part in pairs(p and p.stages or {}) do if part==name then return W.find(key) end end
    end
    return W.find('stock')
end
--- node weight now (nil when no part defines the variable)
function W.scale(d)
    local m=(((d or {}).vdata or {}).variables or {})[W.VAR]
    if type(m)~='table' then return nil end
    return finite(((d.config or {}).vars or {})[W.VAR]) or finite(m.val) or finite(m.default)
end
--- extra PI share for a rating's parts
function W.bonusShare(parts)
    for _,name in pairs(type(parts)=='table' and parts or {}) do
        local stage=type(name)=='string' and name:match('^rp_body_%x+_(%a+)$')
        local st=stage and W.find(stage)
        if st and st.bonus then return st.bonus end
    end
    return 0
end
--- why the car may not race with its weight, or nil. The parts rules check
--- "Factory parts only" (slot group "body"); this checks the value itself.
function W.problem(d,catalog)
    local s=W.scale(d);if not s then return nil end
    local st=W.stage(d,catalog)
    if math.abs(s-st.scale)>1e-4 then return 'Car weight was changed outside Race Prep: fit a body stage (Upgrades > Body).' end
end
--- stage buttons for the UI; mass in kg of the car as it is now
function W.rows(d,catalog,mass)
    if not W.available(d,catalog) then return {} end
    local fitted=W.stage(d,catalog)
    local stockMass=finite(mass) and mass/fitted.scale or nil
    local out={}
    for _,st in ipairs(W.STAGES) do
        out[#out+1]={key=st.key,label=st.label,percent=st.percent,fitted=fitted==st,
            kg=stockMass and math.floor(stockMass*(1-st.scale)+0.5) or nil,
            bonus=st.bonus and math.floor(st.bonus*100+0.5) or nil}
    end
    return out
end
return W
