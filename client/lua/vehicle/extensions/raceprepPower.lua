-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Automation engine parts (intake, exhaust, ECU, cam, internals, displacement,
-- flywheel, forced induction, coolers): reshape camsoEngine's torque, friction
-- and fuel maps per part. Always derived from a retained stock copy, never
-- from maps already changed by a previous reset/apply (no compounding).
local M={}
local Effects,Selection,InductionSound
local function modules()
    Effects=Effects or require('common/raceprep/engineEffects')
    Selection=Selection or require('common/raceprep/engineSelection')
    InductionSound=InductionSound or require('common/raceprep/inductionSound')
end
local function clone(t)
    local out={}
    for k,x in pairs(t or {}) do out[k]=type(x)=='table' and clone(x) or x end
    return out
end
local function scaled(t,factor)
    local out={}
    for k,x in pairs(t or {}) do out[k]=type(x)=='table' and scaled(x,factor) or type(x)=='number' and x*factor or x end
    return out
end
function M.applySpec(engine,spec)
    modules()
    if engine.type~='camsoEngine' then return false end
    InductionSound.configure(engine,spec)
    local base=engine._raceprepPowerBase
    if not base then
        base={torque=clone(engine.torqueThrottleMap),friction=clone(engine.frictionTorqueTable),
            fuel=clone(engine.FuelUsedThrottleMap),pressure=clone(engine.peakPressureCurve),
            pressureMap=clone(engine.PressureThrottleMap),idleTorque=engine.idleTorque,limits={},maxRPM=engine.maxRPM,inertia=engine.inertia}
        for _,key in ipairs({'maxTorqueRating','maxOverTorqueDamage'}) do base.limits[key]=engine[key] end
        engine._raceprepPowerBase=base
    end
    base.pressure=base.pressure or clone(engine.peakPressureCurve)
    base.pressureMap=base.pressureMap or clone(engine.PressureThrottleMap)
    local stock=spec.stockRevLimit or base.maxRPM
    spec.pressurePoints={}
    for rpm=0,stock,100 do spec.pressurePoints[#spec.pressurePoints+1]={rpm,base.pressure[rpm] or 1} end
    -- The parts' limit, moved by the driver's own RPM Limit tuning (race ECU,
    -- $revLimitRPM; its default is the stock limit). It was overridden before.
    local tuned=tonumber(spec.revLimitTuning) or 0
    local limit=math.max(1000,Effects.revLimit(stock,spec)+tuned)
    local friction,fullMaps,fuels,pressure={},{},{},{}
    for rpm=0,limit+1 do
        local from=math.min(rpm,stock)
        local f=Effects.factor(rpm,stock,spec,false,1)
        friction[rpm]=(base.friction[from] or 0)*f
        pressure[rpm]=base.pressure[from] or 1
    end
    -- Past the stock limit only the full-throttle row is extrapolated (net
    -- torque, friction added back). Other rows keep their stock-limit share
    -- of it: extrapolating each row's net torque clamped closed throttle to
    -- exactly the friction, so revs hung at the raised limit in neutral.
    local full=base.torque[99] or {}
    local points={}
    for rpm=0,stock,100 do points[#points+1]={rpm,(full[rpm] or 0)-(base.friction[rpm] or 0)} end
    if points[#points][1]~=stock then points[#points+1]={stock,(full[stock] or 0)-(base.friction[stock] or 0)} end
    Effects.prepare(points,stock,spec)
    -- The same normalization must scale friction as well as gross torque.
    for rpm=0,limit+1 do friction[rpm]=(base.friction[math.min(rpm,stock)] or 0)*Effects.factor(rpm,stock,spec,false,1) end
    local fullAbove={}
    for rpm=stock+1,limit+1 do fullAbove[rpm]=Effects.torque(points,rpm,stock,spec,false,1)+friction[rpm] end
    local fullAtStock=full[stock] or 0
    for throttle,row in pairs(base.torque) do
        local result={}
        local share=fullAtStock>0 and (row[stock] or 0)/fullAtStock or 0
        for rpm=0,limit+1 do
            result[rpm]=rpm<=stock and (row[rpm] or 0)*Effects.factor(rpm,stock,spec,false,1) or fullAbove[rpm]*share
        end
        fullMaps[throttle]=result
    end
    for throttle,row in pairs(base.fuel or {}) do
        fuels[throttle]={}
        for rpm=0,limit+1 do fuels[throttle][rpm]=(row[math.min(rpm,stock)] or 0)*Effects.factor(rpm,stock,spec,false,1) end
    end
    engine.torqueThrottleMap,engine.frictionTorqueTable=fullMaps,friction
    -- Factory Race tuning changes the export's pressure map AND the matching
    -- torque/fuel maps. camsoEngine itself then steers its wastegate and gauges.
    -- Always rebuild from retained originals; removing the part restores them.
    local target=spec.induction=='stock_upgrade' and spec.inductionRace and spec.factoryBoostTarget
    local maps=clone(base.pressureMap)
    if target then
        local ratio=math.max(0,math.min(115,target))/100
        local function adjusted(p)return p>1 and 1+(p-1)*ratio or p end
        for _,row in pairs(maps)do
            for rpm=0,limit+1 do row[rpm]=adjusted(row[rpm] or row[math.min(rpm,stock)] or 1)end
        end
        for rpm,p in pairs(pressure)do pressure[rpm]=adjusted(p)end
    end
    if next(maps) then engine.PressureThrottleMap=maps end
    engine.torqueCurve,engine.FuelUsedThrottleMap,engine.peakPressureCurve=fullMaps[99],fuels,pressure
    engine.maxRPM,engine.maxAV=limit,limit*math.pi/30
    if engine.tempRevLimiterAV and engine.tempRevLimiterAV>=stock*math.pi/30 then engine.tempRevLimiterAV=engine.maxAV*10 end
    if engine.maxPhysicalAV then engine.maxPhysicalAV=math.max(engine.maxPhysicalAV,engine.maxAV) end
    local maxFactor=1
    for rpm=0,stock,100 do maxFactor=math.max(maxFactor,Effects.factor(rpm,stock,spec,false,1)) end
    for key,value in pairs(base.limits) do engine[key]=value>0 and value*maxFactor or value end
    if spec.flywheel then
        local original=spec.stockInertia or base.inertia
        if original then
            engine.inertia=math.max(.015,.25*original,original*(spec.flywheel=='race' and .6 or .8))
            engine.invInertia=1/engine.inertia
        end
    end
    engine.raceprepEngineSpec=spec
    engine.raceprepBoost=spec.induction and (spec.induction:find('turbo',1,true) or spec.induction=='twin_charged') and 0 or 1
    -- Native dyno queries use the steady curve. During physics, lightweight
    -- row proxies apply transient boost without rewriting 100 RPM maps each
    -- frame. The wrapper always restores proxies, including error paths.
    local getter=engine._raceprepTorqueGetter or engine.getTorqueData
    engine._raceprepTorqueGetter=getter
    local proxyMaps={}
    local function ratio(rpm)
        return Effects.factor(rpm,stock,spec,false,engine.raceprepBoost)/Effects.factor(rpm,stock,spec,false,1)
    end
    for throttle,row in pairs(fullMaps) do
        proxyMaps[throttle]=setmetatable({}, {__index=function(_,rpm)
            local t=row[rpm];return t and t*ratio(rpm) or nil
        end})
    end
    -- camsoEngine reads friction as t[rpm] or t[#t]: past the table end (rev
    -- limiter overshoot in neutral) a proxy has #t == 0 and t[0] is 0 rpm
    -- friction (0), so revs hung with nothing slowing the engine. Hold the
    -- last value instead, as camso's own table does.
    local top=limit+1
    local proxyFriction=setmetatable({}, {__index=function(_,rpm)
        local t=friction[rpm]
        if t==nil and type(rpm)=='number' and rpm>top then t=friction[top];rpm=top end
        return t and t*ratio(rpm) or nil
    end})
    engine.getTorqueData=function(self,...)
        local oldMaps,oldFriction=self.torqueThrottleMap,self.frictionTorqueTable
        self.torqueThrottleMap,self.frictionTorqueTable=fullMaps,friction
        local ok,value=pcall(getter,self,...)
        self.torqueThrottleMap,self.frictionTorqueTable=oldMaps,oldFriction
        if not ok then error(value) end
        return value
    end
    engine.torqueData=engine:getTorqueData()
    engine.maxPower,engine.maxTorque=engine.torqueData.maxPower,engine.torqueData.maxTorque
    engine.maxPowerThrottleMap=(engine.maxPower or 0)*735.499
    if engine.sendTorqueData then engine:sendTorqueData() end
    engine.torqueThrottleMap,engine.frictionTorqueTable=proxyMaps,proxyFriction
    return true
end
function M.applyNativeScale(engine,scale)
    modules()
    if engine.type~='combustionEngine' then return false end
    assert(type(scale)=='number' and scale==scale and scale>0 and scale<1000,'Invalid native engine scale')
    local base=engine._raceprepNativeBase
    if not base then
        base={curve=clone(engine.torqueCurve),friction=engine.friction,dynamicFriction=engine.dynamicFriction}
        engine._raceprepNativeBase=base
    end
    engine.torqueCurve=clone(base.curve);engine.friction=base.friction;engine.dynamicFriction=base.dynamicFriction
    for rpm,t in pairs(base.curve) do engine.torqueCurve[rpm]=t*scale end
    engine.friction=base.friction*scale;engine.dynamicFriction=base.dynamicFriction*scale
    engine.torqueData=engine:getTorqueData();engine.maxPower=engine.torqueData.maxPower;engine.maxTorque=engine.torqueData.maxTorque
    return true
end
function M.applyNativeScales(scales)
    for _,engine in pairs(powertrain.getDevicesByCategory('engine') or {}) do
        if scales[engine.name] then M.applyNativeScale(engine,scales[engine.name]) end
    end
end
function M.apply()
    modules()
    InductionSound.reset()
    local data=v and v.data or {}
    local selected,reason=Selection.spec(data.model,data.activeParts,data.variables and (v.config and v.config.vars) or {},data)
    M.lastError=reason
    if not selected then return end
    -- RPM Limit tuning: the setting against its own default (0 = untouched)
    local vars=v and v.config and v.config.vars or {}
    local def=data.variables and data.variables['$revLimitRPM']
    local set,default=tonumber(vars['$revLimitRPM']),def and tonumber(def.default)
    selected.revLimitTuning=(set and default) and set-default or 0
    local changed=false
    for _,field in ipairs({'intake','exhaust','ecu','cam','forged','displacement','flywheel','induction','intercooler','oilcooler'}) do
        if selected[field] then changed=true end
    end
    if changed then
        for _,engine in pairs(powertrain.getDevicesByCategory('engine') or {}) do M.applySpec(engine,selected) end
    end
end
-- Publish only in the absence of any factory induction device. Device writers
-- retain ownership even if a foreign/old generated part is fitted accidentally.
function M.publishBoost(engine,spec,rpm,dt,devices)
    modules()
    for _,e in pairs(devices or {}) do
        if e.turbocharger and e.turbocharger.isExisting or e.supercharger and e.supercharger.isExisting then return end
    end
    local gauge=Effects.gauge(spec,rpm,spec.stockRevLimit,engine.throttle or 0,engine.raceprepBoost)
    if not gauge then return end
    local values=electrics and electrics.values
    if values then
        values.boost=gauge.boost/6.8947572932;values.boostMax=gauge.maxBoost/6.8947572932
        values.turboBoost=gauge.turboBoost/6.8947572932
        values.superchargerBoost=gauge.superchargerBoost/6.8947572932
    end
    if streams and gui and streams.willSend('forcedInductionInfo') then
        gui.send('forcedInductionInfo',{boost=gauge.boost,maxBoost=gauge.maxBoost,rpm=gauge.rpm})
    end
end
function M.updateGFX(dt)
    if not Effects then return end
    local devices=powertrain.getDevicesByCategory('engine') or {}
    for _,engine in pairs(devices) do
        local spec=engine.raceprepEngineSpec
        if spec then
            local rpm=(engine.outputAV1 or 0)*30/math.pi
            engine.raceprepBoost=Effects.boost(engine.raceprepBoost,spec,rpm,spec.stockRevLimit,engine.throttle or 0,dt)
            M.publishBoost(engine,spec,rpm,dt,devices)
        end
    end
    InductionSound.update(devices,dt)
end
function M.onExtensionUnloaded()if InductionSound then InductionSound.reset()end end
M.onReset=M.apply
return M
