-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Shared rating validation/store policy. No BeamMP globals; usable in LuaJIT tests.
-- AGPL-3.0-or-later (see LICENSE). Client reports are estimates, never trusted as measured calibration.
local M={}
local function finite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
M.CURVE = { knee = 300, cap = 999, a = 0.495, b = 0.58, c = 0.29 }
function M.curve(raw, c)
    assert(finite(raw), "Invalid rating")
    local p = c == nil and M.CURVE or (type(c) == "table" and (tonumber(c.knee) and c or type(c.curve) == "table" and c.curve)) or nil
    if not p then return math.max(100, math.min(999, math.floor(raw + 0.5))) end
    local knee, cap = tonumber(p.knee) or 300, tonumber(p.cap) or 999
    if raw <= knee then return math.max(100, math.min(cap, math.floor(raw + 0.5))) end
    local h = cap - knee
    local u = (raw - knee) / h
    local a, b, d = tonumber(p.a) or 0.495, tonumber(p.b) or 0.58, tonumber(p.c) or 0.29
    local z = u + (a * u * u + b * u ^ 4) / (1 + d * u ^ 3)
    return math.max(100, math.min(cap, math.floor(knee + h * (1 - math.exp(-z)) + 0.5)))
end
local function rawOf(e,field)
    local r=type(e)=='table' and type(e.raw)=='table' and tonumber(e.raw[field])
    return r or (type(e)=='table' and tonumber(e[field])) or nil
end
function M.classOf(pi)
    for _,b in ipairs({{999,'X'},{901,'P'},{801,'R'},{701,'S'},{601,'A'},{501,'B'},{401,'C'},{301,'D'}}) do
        if pi>=b[1] then return b[2] end
    end
    return 'E'
end
function M.validate(p,identity,constants)
    if type(p)~='table' then return nil,'Invalid payload' end
    for _,field in ipairs({'model','config'}) do
        local pattern=field=='config' and '^[%w_ %-]+$' or '^[%w_-]+$'
        if type(p[field])~='string' or #p[field]>128 or not p[field]:match(pattern) then return nil,'Invalid '..field end
    end
    local raw={}
    local src=type(p.raw)=='table' and p.raw or p
    for _,field in ipairs({'pi','pi_speed','pi_technical'}) do
        local r=src[field]
        if not finite(r) or r%1~=0 or r<100 or r>2500 then return nil,'Invalid '..field end
        if src~=p and p[field]~=nil and (not finite(p[field]) or p[field]%1~=0 or p[field]<100 or p[field]>999) then
            return nil,'Invalid '..field
        end
        raw[field]=r
    end
    if type(p.parts)~='table' then return nil,'Missing installed parts' end
    local parts,count={},0
    for path,part in pairs(p.parts) do
        if type(path)~='string' or #path>512 or type(part)~='string' or #part>256 or part=='' or
            path:find('[%c]') or part:find('[%c]') then return nil,'Invalid installed part' end
        count=count+1
        if count>2000 then return nil,'Too many parts' end
        parts[path]=part
    end
    if count==0 then return nil,'Empty parts identity' end
    local h=identity.hash(parts)
    local pi=M.curve(raw.pi,constants)
    local entry={model=p.model,config=p.config,parts=parts,partsHash=h,raw=raw,pi=pi,
        pi_speed=M.curve(raw.pi_speed,constants),pi_technical=M.curve(raw.pi_technical,constants),class=M.classOf(pi),
        source='computed',assumptions='Sport / 40 kg fuel / warm KTS tyres',anchored=p.anchored==true or nil}
    if p.model=='firestarter_clone_kalalalac' then entry.flag='Suspected gearbox fault: hunts / 134 km/h' end
    return entry,p.model..'/'..p.config..'/'..h
end
function M.accept(entries,p,identity,constants)
    local e,key=M.validate(p,identity,constants)
    if not e then return nil,key end
    if entries[key] then return key,false,entries[key] end
    entries[key]=e
    return key,true,e
end
-- Seed migration: seed entries replace missing, computed and older measured
-- ones (admin-set ratings are kept). When a car's measured stock rating
-- changes (re-measure), the computed ratings of its other part combinations
-- were anchored to the old value, and accept() never replaces a stored entry:
-- drop them so each is recomputed against the new base when spawned.
function M.mergeSeed(store,seed)
    local merged,dropped,changed=0,0,{}
    if type(seed)~='table' or type(seed.entries)~='table' then return 0,0 end
    for k,e in pairs(seed.entries) do
        local old=store.entries[k]
        if not old or (old.source~='admin' and old~=e) then
            if old and e.source=='measured' and old.pi~=e.pi and e.model then changed[e.model]=true end
            store.entries[k]=e;merged=merged+1
        end
    end
    for k,e in pairs(store.entries) do
        if e.source=='computed' and not seed.entries[k] and (changed[e.model] or (seed.constants and seed.constants.curve and not e.raw)) then
            store.entries[k]=nil;dropped=dropped+1
        end
    end
    if seed.constants then store.constants=seed.constants end
    store.flags=store.flags or {}
    for k,v in pairs(seed.flags or {}) do if store.flags[k]==nil then store.flags[k]=v end end
    store.baselines=store.baselines or {}
    for k,v in pairs(seed.baselines or {}) do store.baselines[k]=v end
    return merged,dropped
end
-- Display/race PI includes the existing parts-based tuning/body bonuses.
-- Keep these transient: the persisted calibration entry remains the unbonused PI.
function M.presentation(p)
    local m=type(p)=='table' and p.presentation
    if type(m)~='table' then return nil end
    local share=m.tuningShare
    if not finite(share) or share<0 or share>.2 then return nil end
    if m.weightShare~=0 and m.weightShare~=.03 then return nil end
    local name=m.carName
    if type(name)~='string' or #name>120 or name:find('[%c]') then return nil end
    return {tuningShare=share,weightShare=m.weightShare,carName=name}
end
function M.present(e,m,constants)
    if not e then return nil end
    if not m then
        if type(e.raw)=='table' or (type(constants)=='table' and not constants.curve and not tonumber(constants.knee)) then return e end
        local out={};for k,v in pairs(e) do out[k]=v end
        out.raw={pi=rawOf(e,'pi'),pi_speed=rawOf(e,'pi_speed'),pi_technical=rawOf(e,'pi_technical')}
        for _,f in ipairs({'pi','pi_speed','pi_technical'}) do
            if out.raw[f] then out[f]=M.curve(out.raw[f],constants) end
        end
        if out.pi then out.class=M.classOf(out.pi) end
        return out
    end
    local out={};for k,v in pairs(e) do out[k]=v end
    local rpi=rawOf(e,'pi')
    local basePI=rpi and M.curve(rpi,constants) or e.pi
    out.performancePI=basePI;out.carName=m.carName
    out.tuningPotentialPI=rpi and (M.curve(rpi*(1+m.tuningShare),constants)-basePI) or math.floor(e.pi*m.tuningShare+.5)
    out.weightBonusPI=rpi and (M.curve(rpi*(1+m.weightShare),constants)-basePI) or math.floor(e.pi*m.weightShare+.5)
    local raw={}
    for _,f in ipairs({'pi','pi_speed','pi_technical'}) do
        local rf=rawOf(e,f)
        if rf then
            raw[f]=math.max(100,math.floor(rf*(1+m.tuningShare+m.weightShare)+.5))
            out[f]=M.curve(rf*(1+m.tuningShare+m.weightShare),constants)
        end
    end
    if next(raw) then out.raw=raw end
    out.class=M.classOf(out.pi)
    return out
end
function M.classes(input,base)
    local out={}
    for _,c in ipairs({'E','D','C','B','A','S','R','P','X'}) do
        out[c]=type(input)=='table' and type(input[c])=='boolean' and input[c] or nil
        if type(input)=='table' and input[c]==false then out[c]=false
        elseif out[c]==nil then out[c]=not base or base[c]~=false end
    end
    return out
end
function M.bound(value,fallback)
    if value==false then return false end
    if finite(value) then return math.floor(math.max(100,math.min(999,value))+0.5) end
    return fallback or false
end
return M
