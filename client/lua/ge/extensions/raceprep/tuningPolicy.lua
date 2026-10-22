-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Race-part ownership is distinct from per-event permission to tune.
-- radiator_*: a very slight PI bump for an upgraded radiator (owner 2026-10-18)
local P={BONUSES={transmission=.025,differential=.015,suspension=.02,radiator_sport=.005,radiator_race=.01}}
local function text(value) return tostring(value or ''):lower() end
local function has(value,words)
    for _,word in ipairs(words) do if value:find(word,1,true) then return true end end
    return false
end
local function finalDrive(slot,title)
    return has(text(slot)..' '..text(title),{'finaldrive','final drive','final_drive'})
end
-- activeParts keys are full slot paths in BeamNG 0.39
-- ("/Camso_Trim/Camso_suspension_F/.../Camso_wheels_front/<part>"): the
-- slot is the last segment before the part. Ancestors must not count (tyres
-- sit under the suspension slot).
function P.slotId(key,part)
    key=tostring(key or '')
    if not key:find('/',1,true) then return key end
    local segs={}
    for s in key:gmatch('[^/]+') do segs[#segs+1]=s end
    if part and segs[#segs]==part and #segs>1 then return segs[#segs-1] end
    return segs[#segs] or key
end
function P.role(slot,part)
    local s=text(slot)..' '..text(part)
    if has(s,{'differential','diff','centre split','center split'}) then return 'differential' end
    if has(s,{'transmission','gearbox','gear ratio','final drive','finaldrive','$gear','gear_'}) or s:match('^gear %w') or s:match(' gear %w')
        or s:match('^gear$') then return 'transmission' end
    if has(s,{'coilover','suspension','spring','damper','shock','sway','camber','ride height','anti-roll','$toe_','toe adjust','trackoffset','wheel offset'}) then return 'suspension' end
    if has(s,{'downforce','aero'}) then return 'aero' end
    if has(s,{'boost','turbo','supercharger'}) then return 'induction' end
    if has(s,{'camshaft','cam timing'}) then return 'cam' end
    -- Automation's rev limiter / idle settings live on the engine part; the
    -- race ECU (engine management) is what unlocks them
    if has(s,{'ecu','ignition','timing','management','revlimit','rev limit','rpm limit','rpm drop','soft limit',
        'cut time','idlerpm','idle rpm'}) then return 'ecu' end
end
-- which axle a slot, part or variable belongs to: "front", "rear", "centre"
-- or nil (whole car). Automation uses _F / _R suffixes and front/rear words.
function P.axle(...)
    local s=text(table.concat({...},' '))
    if has(s,{'center','centre','transfer'}) then return 'centre' end
    if has(s,{'front'}) or s:match('_f$') or s:match('_f[_%s]') then return 'front' end
    if has(s,{'rear'}) or s:match('_r$') or s:match('_r[_%s]') then return 'rear' end
end
--- a race differential is fitted on this axle (position: front/rear/centre/other)
function P.raceDifferential(vdata,position)
    for slot,part in pairs(vdata.activeParts or {}) do
        local data=(vdata.activePartsData or {})[part]
        local title=data and data.information and data.information.name or part
        local sid=P.slotId(slot,part)
        if P.role(sid,title)=='differential' and P.isRace(part,data) then
            local a=P.axle(sid,part)
            if not position or position=='other' or not a or a==position then return true end
        end
    end
    return false,'Needs a race '..(position=='centre' and 'centre' or position or '')..' differential'
end
function P.isRace(name,data)
    return text(name):find('race',1,true)~=nil or text(data and data.information and data.information.name):find('race',1,true)~=nil
end
function P.owners(vdata)
    local owners={}
    for name,data in pairs(vdata.activePartsData or {}) do
        for _,variable in pairs(data.variables or {}) do
            if type(variable)=='table' then
                local id=variable.name or variable[1]
                if type(id)=='string' and id:sub(1,1)=='$' then
                    owners[id]=owners[id] or {}
                    owners[id][#owners[id]+1]={part=name,title=(data.information or {}).name or name,race=P.isRace(name,data)}
                end
            end
        end
    end
    for name,role in pairs(vdata.raceprepVariableOwners or {}) do
        for part,data in pairs(vdata.activePartsData or {}) do
            if P.role(part,(data.information or {}).name)==role then
                owners[name]=owners[name] or {}
                owners[name][#owners[name]+1]={part=part,title=(data.information or {}).name or part,race=P.isRace(part,data)}
            end
        end
    end
    return owners
end
function P.allowed(vdata,name,meta,owners)
    local s=text(name)..' '..text(meta and meta.title)
    if has(s,{'tirepressure','tyrepressure','tire pressure','tyre pressure','psi','brake balance','brakebias','brake bias','brake pressure','brakepressure','fuel'}) then
        return true,nil,'always'
    end
    -- Final drive is open on every car's own transmission (owner 2026-10-17):
    -- no part needed, so it adds no PI (tuning never changes PI). Individual
    -- gear ratios still need a race transmission.
    if finalDrive(name,meta and meta.title) then return true,nil,'final-drive' end
    -- sound / cosmetic settings never affect performance
    if has(s,{'volume','whine','sound','camera','brake offset','brakeoffset'}) then return true,nil,'cosmetic' end
    owners=owners or P.owners(vdata)
    local list=owners[name] or {}
    local role=P.role(name,meta and (meta.title or meta.category))
    -- Aero kits expose bounded controls and are valid even for Street/Sport.
    if role=='aero' and vdata.raceprepAero and (name=='$rpAeroFront' or name=='$rpAeroRear') then return true,nil,'aero-kit' end
    for _,owner in ipairs(list) do
        -- Final drives share the transmission role for shop/PI bookkeeping,
        -- but cannot grant permission to adjust the gearbox's individual gears.
        if owner.race and not (role=='transmission' and finalDrive(owner.part,owner.title)) then return true,nil,owner.part end
    end
    -- Final-drive and centre-split controls can live on a separate export
    -- child part. For these agreed categories the fitted race assembly owns
    -- the setup control, while the raw defining part remains in owners().
    -- An axle-specific setting (_F / _R / front / rear) needs the race part
    -- of that axle: race front coilovers do not unlock rear springs.
    if role=='transmission' or role=='differential' or role=='suspension' or role=='ecu' then
        local want=P.axle(name,meta and meta.title)
        for slot,part in pairs(vdata.activeParts or {}) do
            local data=(vdata.activePartsData or {})[part]
            local sid=P.slotId(slot,part)
            local title=(data and data.information and data.information.name) or part
            if P.role(sid,title)==role and P.isRace(part,data)
                and not (role=='transmission' and finalDrive(sid,title)) then
                local a=P.axle(sid,part)
                if not want or not a or a==want then return true,nil,part end
            end
        end
    end
    local label=({transmission='transmission',differential='differential',suspension='suspension',aero='aero kit',induction='forced induction',ecu='ECU',cam='camshaft'})[role]
    if not label then return false,'Stock part - not adjustable','unsupported' end
    return false,'Needs a race '..label,#list>0 and list[1].part or 'unmapped'
end
function P.catalogBonus(parts,roles,pi)
    local share,seen=0,{}
    for _,name in pairs(parts or {}) do
        local role=roles and roles[name]
        if not seen[name] and P.BONUSES[role] then seen[name]=true;share=share+P.BONUSES[role] end
    end
    return math.floor(pi*share+.5),share
end
function P.bonus(vdata,pi)
    local share,parts=0,{}
    local seen={}
    for slot,name in pairs(vdata.activeParts or {}) do
        local data=(vdata.activePartsData or {})[name]
        local role=P.role(P.slotId(slot,name),(data and data.information and data.information.name) or name)
        local radiator=data and data.raceprepEngine and data.raceprepEngine.radiator
        if radiator then role='radiator_'..tostring(radiator) end
        if not seen[name] and P.BONUSES[role] and (radiator or P.isRace(name,data)) then
            seen[name]=true;share=share+P.BONUSES[role]
            parts[#parts+1]={part=name,role=role,share=P.BONUSES[role]}
        end
    end
    table.sort(parts,function(a,b) return a.part<b.part end)
    return math.floor(pi*share+.5),parts,share
end
return P
