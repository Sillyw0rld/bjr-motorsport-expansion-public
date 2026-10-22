-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Shared, deterministic engine effects for runtime, dyno previews and PI.
-- Values implement the owner's 1.8.0 brief; empirical validation is separate.
local E={}
-- Turbo lag does not show in a steady curve: PI evaluation ("pi" rating mode)
-- discounts the turbo's torque gain. Dyno labels (rated=true) show it in full.
E.LAG_PI_DISCOUNT={turbo_small=.10,turbo_large=.15}
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function ramp(r,a,b) return clamp((r-a)/(b-a),0,1) end
E.PACKAGES={
    {intake='sport',exhaust='sport',ecu='sport'},
    {intake='race',exhaust='race',ecu='race',cam='sport'},
    {intake='race',exhaust='race',ecu='race',cam='race',forged=true,displacement='sport'},
}
function E.required(spec)
    if (spec.induction=='turbo_large' or spec.induction=='supercharger_race' or spec.induction=='stock_upgrade') and not spec.forged then
        return false,'Needs forged internals before fitting this forced-induction part.'
    end
    if spec.induction=='stock_upgrade' and not spec.stockForcedInduction then
        return false,'This engine has no existing forced-induction system to upgrade.'
    end
    if spec.induction and spec.induction~='stock' and spec.induction~='stock_upgrade' and spec.stockForcedInduction then
        return false,'This engine already has forced induction.'
    end
    return true
end
--- shop rule on top of required(): forced induction added to a naturally
--- aspirated engine needs an upgraded radiator (owner 2026-10-18). Not part of
--- required(), so cars already fitted that way keep their engine effects.
function E.shopRequired(spec)
    local ok,why=E.required(spec)
    if not ok then return ok,why end
    if spec.induction and spec.induction~='stock' and spec.induction~='stock_upgrade' and not spec.stockForcedInduction and not spec.radiator then
        return false,'Forced induction needs a High performance or Race radiator.'
    end
    return true
end
function E.revLimit(stock,spec)
    return stock+(spec.ecu=='race' and 300 or 0)+
        (spec.forged and (spec.cam=='race' and 1000 or spec.cam=='sport' and 500 or 0) or 0)
end
function E.mass(spec)
    local kg=spec.displacement=='race' and 10 or spec.displacement=='sport' and 5 or 0
    if spec.induction and spec.induction~='stock' and spec.induction~='stock_upgrade' then
        kg=kg+((spec.induction=='turbo_large' or spec.induction=='supercharger_race') and 25 or 15)
    end
    return kg+(spec.intercooler and 5 or 0)+(spec.oilcooler and 5 or 0)+(spec.radiator=='race' and 5 or spec.radiator=='sport' and 3 or 0)
end
function E.factor(rpm,stock,spec,rated,boost)
    local r=rpm/stock
    local intake=spec.intake=='race' and .06 or spec.intake=='sport' and .03 or 0
    local exhaust=spec.exhaust=='race' and .06 or spec.exhaust=='sport' and .03 or 0
    local ecu=spec.ecu=='race' and .05 or spec.ecu=='sport' and .02 or 0
    -- Timing adjustment expresses remaining tuning headroom, not a second
    -- package stage. Rated collection always uses the best allowed setting.
    if spec.ecu=='race' then ecu=ecu*(rated and 1 or clamp(spec.ecuGain or 1,0,1)) end
    local cam=1
    if spec.cam=='sport' or spec.cam=='race' then
        local low,high=spec.cam=='race' and -.10 or -.05,spec.cam=='race' and .12 or .06
        cam=1+low+(high-low)*ramp(r,.50,.75)
        if spec.cam=='race' then cam=1+(cam-1)*(rated and 1 or clamp(spec.camGain or 1,0,1)) end
    end
    local displacement=spec.displacement=='race' and .12 or spec.displacement=='sport' and .06 or 0
    local induction=0
    local kind=spec.induction
    if kind=='supercharger_sport' or kind=='supercharger_race' then
        local shape=spec.superchargerType=='centrifugal' and clamp(r,0,1)^2 or
            ramp(r,0,.20)*(1-.10*ramp(r,.20,1))
        induction=(kind=='supercharger_race' and .45 or .30)*shape
    elseif kind=='turbo_small' or kind=='turbo_large' then
        local spool=kind=='turbo_large' and .55 or .35
        induction=(kind=='turbo_large' and .70 or .40)*ramp(r,spool,math.min(1,spool+.10))
        if spec.turboLayout=='twin' then induction=induction*.95 end
    elseif kind=='stock_upgrade' then
        local pressure=spec.pressurePoints and E.interpolate(spec.pressurePoints,rpm) or 1
        induction=.15*math.max(0,pressure-1)/math.max(1,pressure)
    end
    if induction>0 then induction=induction*((rated or not spec.inductionRace) and 1 or clamp(spec.boostGain or 1,0,1))*(boost or 1) end
    if rated=='pi' and E.LAG_PI_DISCOUNT[kind] then induction=induction*(1-E.LAG_PI_DISCOUNT[kind]) end
    -- Race intercooler: a cooler intake charge, worth +2 % on boosted engines
    -- (added charger or the export's own); nothing on naturally aspirated ones.
    local cooler=spec.intercooler and (induction>0 or spec.stockForcedInduction) and 1.02 or 1
    return (1+intake*ramp(r,.30,.70))*(1+exhaust*ramp(r,.40,.80))*(1+ecu)*cam*(1+displacement)*(1+induction)*cooler
end
function E.interpolate(points,rpm)
    if rpm<=points[1][1] then return points[1][2] end
    for i=2,#points do
        local a,b=points[i-1],points[i]
        if rpm<=b[1] then return a[2]+(b[2]-a[2])*(rpm-a[1])/(b[1]-a[1]) end
    end
    return points[#points][2]
end
function E.torque(points,rpm,stock,spec,rated,boost)
    local t=E.interpolate(points,math.min(rpm,stock))
    if rpm>stock then
        local slope=(E.interpolate(points,stock)-E.interpolate(points,stock*.9))/(stock*.1)
        -- Past the original limit, declining torque must also keep power
        -- non-increasing, even if the top-ten-percent slope was positive.
        t=math.max(0,math.min(t+slope*(rpm-stock),t*stock/rpm))
    end
    return t*E.factor(rpm,stock,spec,rated,boost)
end
function E.curve(points,stock,spec,rated,boost,step)
    local out={}
    local limit=E.revLimit(stock,spec)
    for rpm=0,limit,step or 100 do out[#out+1]={rpm,E.torque(points,rpm,stock,spec,rated,boost)} end
    if out[#out][1]~=limit then out[#out+1]={limit,E.torque(points,limit,stock,spec,rated,boost)} end
    return out,limit
end
function E.boost(state,spec,rpm,stock,throttle,dt)
    if spec.induction~='turbo_small' and spec.induction~='turbo_large' then return 1 end
    local spool=spec.induction=='turbo_large' and .55 or .35
    local seconds=spec.induction=='turbo_large' and 1.5 or .5
    if spec.turboLayout=='twin' then seconds=seconds*.7
    elseif spec.turboLayout=='twin_scroll' then seconds=seconds*.8 end
    if spec.inductionRace and spec.antiLag then seconds=seconds*.5 end
    local target=throttle>.65 and rpm/stock>=spool and 1 or 0
    local rate=target==1 and 1/seconds or 4
    return clamp((state or 0)+(target==1 and rate or -rate)*math.max(0,dt or 0),0,1)
end
return E
