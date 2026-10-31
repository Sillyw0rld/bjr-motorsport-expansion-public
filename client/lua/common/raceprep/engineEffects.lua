-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Shared, deterministic engine effects for runtime, dyno previews and PI.
-- Values implement the owner's 1.8.0 brief; empirical validation is separate.
local E={}
-- Turbo lag does not show in a steady curve: PI evaluation ("pi" rating mode)
-- discounts the turbo's torque gain. Dyno labels (rated=true) show it in full.
E.INDUCTION_DESCRIPTIONS={twin_charged='Supercharger response at low rpm; turbo takes over at 50–65% of the rev limit.',turbo_sequential='Small turbo boosts by 30% of the rev limit; large turbo takes over at 45–60%.'}
E.LAG_PI_DISCOUNT={turbo_small=.10,turbo_large=.15,twin_charged=.04,turbo_sequential=.06}
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function ramp(r,a,b) return clamp((r-a)/(b-a),0,1) end
E.PACKAGES={
    {intake='sport',exhaust='sport',ecu='sport'},
    {intake='race',exhaust='race',ecu='race',cam='sport'},
    {intake='race',exhaust='race',ecu='race',cam='race',forged=true,displacement='sport'},
}
function E.required(spec)
    if (spec.induction=='turbo_large' or spec.induction=='supercharger_race' or spec.induction=='stock_upgrade' or spec.induction=='twin_charged' or spec.induction=='turbo_sequential') and not spec.forged then
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
        kg=kg+(spec.induction=='twin_charged' and 35 or spec.induction=='turbo_sequential' and 30 or (spec.induction=='turbo_large' or spec.induction=='supercharger_race') and 25 or 15)
    end
    return kg+(spec.intercooler and 5 or 0)+(spec.oilcooler and 5 or 0)+(spec.radiator=='race' and 5 or spec.radiator=='sport' and 3 or 0)
end
-- Dimensionless boost coefficient, shared by torque, PI and gauge publication.
function E.induction(rpm,stock,spec,rated,boost)
    local r=rpm/stock
    local induction,supercharger=0,0
    local kind=spec.induction
    if kind=='supercharger_sport' or kind=='supercharger_race' then
        local shape=spec.superchargerType=='centrifugal' and clamp(r,0,1)^2 or
            ramp(r,0,.20)*(1-.10*ramp(r,.20,1))
        induction=(kind=='supercharger_race' and .45 or .30)*shape;supercharger=induction
    elseif kind=='turbo_small' or kind=='turbo_large' then
        local spool=kind=='turbo_large' and .55 or .35
        induction=(kind=='turbo_large' and .70 or .40)*ramp(r,spool,math.min(1,spool+.10))
        if spec.turboLayout=='twin' then induction=induction*.95 end
    elseif kind=='twin_charged' then
        local takeover=ramp(r,.50,.65)
        local handover=takeover*(boost or 1)
        supercharger=.45*ramp(r,0,.20)*(1-.10*ramp(r,.20,1))*(1-handover)
        induction=supercharger+.70*handover
    elseif kind=='turbo_sequential' then
        local takeover=ramp(r,.45,.60)
        induction=(.40*ramp(r,.25,.30)*(1-takeover)+.70*takeover)*(boost or 1)
    elseif kind=='stock_upgrade' then
        local pressure=spec.pressurePoints and E.interpolate(spec.pressurePoints,rpm) or 1
        local gain=(not rated and spec.factoryBoostTarget) and (clamp(spec.factoryBoostTarget,0,115)/100-1) or .15
        induction=gain*math.max(0,pressure-1)/math.max(1,pressure)
    end
    if induction>0 then
        local multiplier=((rated or not spec.inductionRace or kind=='stock_upgrade' and spec.factoryBoostTarget) and 1 or clamp(spec.boostGain or 1,0,1))*((kind=='twin_charged' or kind=='turbo_sequential') and 1 or (boost or 1))
        induction=induction*multiplier;supercharger=supercharger*multiplier
    end
    if rated=='pi' and E.LAG_PI_DISCOUNT[kind] then induction=induction*(1-E.LAG_PI_DISCOUNT[kind]);supercharger=supercharger*(1-E.LAG_PI_DISCOUNT[kind]) end
    return induction,supercharger
end
function E.rawFactor(rpm,stock,spec,rated,boost)
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
    local kind=spec.induction
    local induction=E.induction(rpm,stock,spec,rated,boost)
    -- Race intercooler: a cooler intake charge, worth +2 % on boosted engines
    -- (added charger or the export's own); nothing on naturally aspirated ones.
    local cooler=spec.intercooler and (induction>0 or spec.stockForcedInduction) and 1.02 or 1
    return (1+intake*ramp(r,.30,.70))*(1+exhaust*ramp(r,.40,.80))*(1+ecu)*cam*(1+displacement)*(1+induction)*cooler
end
function E.factor(rpm,stock,spec,rated,boost)
    return E.rawFactor(rpm,stock,spec,rated,boost)*(spec._powerScale or 1)
end
local defaults
function E.settings(input)
    if not defaults then defaults=require('common/raceprep/enginePotentialDefaults') end
    local function validate(value,reference)
        if type(value)~=type(reference) then return false end
        if type(reference)=='number' then return value==value and value>0 and value<1e6 end
        if type(reference)=='table' then
            for k,v in pairs(reference) do if not validate(value[k],v) then return false end end
            for k in pairs(value) do if reference[k]==nil then return false end end
        end
        return true
    end
    if input==nil then return defaults end
    assert(validate(input,defaults) and input.schema==1,'Invalid engine potential settings')
    assert(input.headroom[1]<=input.headroom[2] and input.headroom[2]<=input.headroom[3] and input.headroom[3]<=1,'Invalid stage fractions')
    assert(input.displacementClamp[1]<=input.displacementClamp[2] and input.fallback.fullBelowHP<input.fallback.quarterAboveHP and input.fallback.minimumScale<=1,'Invalid potential bounds')
    return input
end
function E.potential(spec)
    local cfg=E.settings(spec.potentialSettings);local layout=spec.layout
    local row=layout and cfg.ceilings[layout]
    if not row and type(layout)=='string' then
        local cylinders=tonumber(layout:match('(%d+)$'));local distance=math.huge
        -- Stable tie break: inline, boxer, then V. Exact layouts win above.
        for _,name in ipairs({'I3','I4','I5','B4','B6','I6','V6','V8','V10','V12','W16'}) do
            local d=cylinders and math.abs(cylinders-tonumber(name:match('%d+')))
            if d and d<distance then row=cfg.ceilings[name];distance=d end
        end
    end
    if not row or row.reference and (type(spec.litres)~='number' or spec.litres<=0) then return nil end
    local forced=spec.stockForcedInduction or spec.fittedForcedInduction or spec.induction and spec.induction~='stock'
    -- Bigger bore/stroke counts as a bigger engine: Sport +6 %, Race +12 % litres.
    local litres=row.reference and spec.litres*(spec.displacement=='race' and 1.12 or spec.displacement=='sport' and 1.06 or 1)
    local scale=row.reference and clamp(litres/row.reference,cfg.displacementClamp[1],cfg.displacementClamp[2]) or 1
    -- Small engines with 8+ cylinders rev higher, so they keep more of their row's
    -- ceiling below the reference size (fourth root instead of linear).
    local cylinders=type(layout)=='string' and tonumber(layout:match('(%d+)$'))
    if cylinders and cylinders>=8 and scale<1 then scale=scale^.25 end
    return (forced and row.forced or row.na)*scale
end
function E.peak(points)
    local peak=0;for _,p in ipairs(points) do peak=math.max(peak,p[1]*p[2]/7127.0) end;return peak
end
local function strength(spec)
    if spec.nativeBuildStrength then return spec.nativeBuildStrength end
    return math.max(0,E.rawFactor(8000,8000,spec,true,1)-1)
end
function E.tier(spec)
    if spec.nativeTier then return spec.nativeTier end
    if spec.forged or spec.displacement or spec.cam=='race' then return 3 end
    if spec.cam=='sport' or spec.intake=='race' or spec.exhaust=='race' or spec.ecu=='race' then return 2 end
    return 1
end
function E.limitNative(curve,reference,spec)
    local hp,raw=E.peak(reference),E.peak(curve)
    if hp<=0 or raw<=hp+math.max(1,hp*.005) then return curve,1 end
    spec.nativeBuildStrength=(raw-hp)/hp
    local scale=(hp+E.gain(hp,spec))/raw;local result={}
    for _,p in ipairs(curve) do result[#result+1]={p[1],p[2]*scale} end
    return result,scale
end
function E.gain(stockHP,spec)
    local cfg=E.settings(spec.potentialSettings)
    local weights={};for i,p in ipairs(E.PACKAGES) do weights[i]=strength(p) end
    local share=math.min(strength(spec),weights[E.tier(spec)]);if share<=0 then return 0 end
    local fraction,floor
    if share<=weights[1] then fraction=cfg.headroom[1]*share/weights[1];floor=cfg.tuneFloor.sport*share/weights[1]
    elseif share<=weights[2] then
        local t=(share-weights[1])/(weights[2]-weights[1]);fraction=cfg.headroom[1]+t*(cfg.headroom[2]-cfg.headroom[1]);floor=cfg.tuneFloor.sport+t*(cfg.tuneFloor.race-cfg.tuneFloor.sport)
    else
        local t=clamp((share-weights[2])/(weights[3]-weights[2]),0,1);fraction=cfg.headroom[2]+t*(cfg.headroom[3]-cfg.headroom[2]);floor=cfg.tuneFloor.race
    end
    local potential=E.potential(spec)
    if not potential then
        local f=cfg.fallback;local taper=1-(1-f.minimumScale)*clamp((stockHP-f.fullBelowHP)/(f.quarterAboveHP-f.fullBelowHP),0,1)
        return stockHP*math.max(math.min(share,weights[3])*taper,floor)
    end
    return math.max(math.max(0,potential-stockHP)*fraction,stockHP*floor)
end
-- Normalize the entire steady curve once. Uniform scaling preserves its RPM
-- shape and the original transient boost ratio; it never changes revs or mass.
function E.prepare(points,stock,spec)
    spec._powerScale=nil
    if not spec.potentialEnabled and not spec.layout then return end
    local stockHP=E.peak(points);local peak=0
    for rpm=0,E.revLimit(stock,spec),50 do peak=math.max(peak,rpm*E.torque(points,rpm,stock,spec,true,1)/7127.0) end
    local gain=E.gain(stockHP,spec)
    spec._powerScale=gain>0 and peak>0 and (stockHP+gain)/peak or 1
    return stockHP,gain
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
    E.prepare(points,stock,spec)
    local out={}
    local limit=E.revLimit(stock,spec)
    for rpm=0,limit,step or 100 do out[#out+1]={rpm,E.torque(points,rpm,stock,spec,rated,boost)} end
    if out[#out][1]~=limit then out[#out+1]={limit,E.torque(points,limit,stock,spec,rated,boost)} end
    return out,limit
end
-- kPa for streams; electrics conversion belongs to the publisher.
function E.gauge(spec,rpm,stock,throttle,state)
    local kind=spec.induction
    if not kind or kind=='stock' or kind=='stock_upgrade' then return nil end
    local peak=spec._gaugeMax
    if not peak then
        peak=0;for i=0,100 do peak=math.max(peak,E.induction(stock*i/100,stock,spec,false,1)) end
        spec._gaugeMax=peak
    end
    local coefficient,supercharger=E.induction(rpm,stock,spec,false,state)
    local pressure=100*coefficient*clamp(throttle or 0,0,1)
    local low=100*supercharger*clamp(throttle or 0,0,1)
    return {boost=pressure,maxBoost=peak*100,rpm=rpm,
        turboBoost=(kind:find('turbo',1,true) or kind=='twin_charged') and (pressure-low) or 0,
        superchargerBoost=low}
end
function E.boost(state,spec,rpm,stock,throttle,dt)
    if spec.induction~='turbo_small' and spec.induction~='turbo_large' and spec.induction~='twin_charged' and spec.induction~='turbo_sequential' then return 1 end
    local spool=spec.induction=='turbo_large' and .55 or spec.induction=='twin_charged' and .50 or spec.induction=='turbo_sequential' and .25 or .35
    local seconds=spec.induction=='turbo_large' and 1.5 or spec.induction=='twin_charged' and .5 or spec.induction=='turbo_sequential' and .35 or .5
    if spec.turboLayout=='twin' then seconds=seconds*.7
    elseif spec.turboLayout=='twin_scroll' then seconds=seconds*.8 end
    if spec.inductionRace and spec.antiLag then seconds=seconds*.5 end
    local target=throttle>.65 and rpm/stock>=spool and 1 or 0
    local rate=target==1 and 1/seconds or 4
    return clamp((state or 0)+(target==1 and rate or -rate)*math.max(0,dt or 0),0,1)
end
return E
