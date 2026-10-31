-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Read canonical (default-tuning) data without altering the player's vehicle.
-- Engine torque getters run on a shallow device copy, never initialize engines.
-- Derived from the project's rpstatic collector.
local M={}
local function round(x,n)
    if type(x)~="number" then return x end
    local k=10^(n or 3)
    return math.floor(x*k+0.5)/k
end
local function points(rows,xkey,ykey,filter)
    local out={{0,0}}
    for _,row in ipairs(tableFromHeaderTable(rows or {}) or {}) do
        if not filter or filter(row) then out[#out+1]={row[xkey],row[ykey]} end
    end
    return out
end
local function shadowModule(name,device,data)
    -- Separate module locals: requiring the live turbo/SC module and calling
    -- init would reset the actual car. Suppress the stock init's telemetry and
    -- damage writes while preparing this private reference instance.
    local path='/lua/vehicle/'..name..'.lua'
    local source=assert(readFile(path),'Missing rating reference module: '..name)
    local factory=assert(load(source,'@'..path))()
    local oldDamage,oldElectrics=damageTracker,electrics
    damageTracker=setmetatable({setDamage=function() end},{__index=oldDamage})
    electrics=setmetatable({values=deepcopy(oldElectrics.values)},{__index=oldElectrics})
    local ok,err=pcall(factory.init,device,deepcopy(data))
    damageTracker,electrics=oldDamage,oldElectrics
    if not ok then error(err) end
    return factory
end
local function engineData(data)
    local out={}
    for _,actual in pairs(powertrain.getDevicesByCategory("engine") or {}) do
        local jd=data[actual.name]
        assert(jd,"Missing canonical engine data")
        local copy={}
        for k,x in pairs(actual) do copy[k]=x end
        copy.getTorqueData=actual._raceprepTorqueGetter or actual.getTorqueData
        copy.wearFrictionCoef,copy.damageFrictionCoef=1,1
        copy.wearDynamicFrictionCoef,copy.damageDynamicFrictionCoef=1,1
        copy.friction,copy.dynamicFriction=jd.friction or 0,jd.dynamicFriction or 0
        copy.idleRPM=jd.idleRPM or actual.idleRPM
        if actual.type=="camsoEngine" then
            local raw=points(jd.torque,"rpm","torque",function(r) return r.throttle==99 end)
            local pressure=points(jd.torque,"rpm","Pressure",function(r) return r.throttle==99 end)
            local maxRPM=0
            for _,p in ipairs(raw) do maxRPM=math.max(maxRPM,p[1]) end
            copy.maxRPM=math.min(jd.maxRPM or maxRPM,maxRPM)
            if jd.hasRevLimiter~=false then copy.maxRPM=math.min(copy.maxRPM,jd.revLimiterRPM or copy.maxRPM) end
            copy.torqueThrottleMap={[99]=createCurve(raw)}
            copy.torqueCurve=copy.torqueThrottleMap[99]
            copy.peakPressureCurve=createCurve(pressure)
            copy.frictionTorqueTable=createCurve(points(jd.frictionTorque,"rpm","torque"))
            copy.turbocharger={isExisting=jd.turbocharger~=nil and data[jd.turbocharger]~=nil}
            copy.supercharger={isExisting=jd.supercharger~=nil and data[jd.supercharger]~=nil}
        elseif actual.type=="combustionEngine" or actual.type=="electricMotor" then
            local base=createCurve(points(jd.torque,"rpm","torque"))
            local mult=jd.torqueModMult and createCurve(points(jd.torqueModMult,"rpm","torque")) or {}
            local intake=jd.torqueModIntake and createCurve(points(jd.torqueModIntake,"rpm","torque")) or {}
            local exhaust=jd.torqueModExhaust and createCurve(points(jd.torqueModExhaust,"rpm","torque")) or {}
            local maxRPM=math.min(jd.maxRPM or #base,#base)
            copy.maxRPM=jd.hasRevLimiter~=false and (jd.revLimiterRPM or maxRPM) or maxRPM
            copy.torqueCurve={}
            for rpm=0,maxRPM do copy.torqueCurve[rpm]=(base[rpm] or 0)*(mult[rpm] or 1)+
                (intake[rpm] or intake[#intake] or 0)+(exhaust[rpm] or exhaust[#exhaust] or 0) end
            copy.turbocharger={isExisting=false}
            copy.supercharger={isExisting=false}
            if jd.turbocharger and data[jd.turbocharger] then
                assert(not jd.turbochargerLuaFileName or jd.turbochargerLuaFileName=='powertrain/turbocharger',
                    'Unsupported custom turbo module')
                copy.turbocharger=shadowModule('powertrain/turbocharger',copy,data[jd.turbocharger])
            end
            if jd.supercharger and data[jd.supercharger] then
                assert(not jd.superchargerLuaFileName or jd.superchargerLuaFileName=='powertrain/supercharger',
                    'Unsupported custom supercharger module')
                copy.supercharger=shadowModule('powertrain/supercharger',copy,data[jd.supercharger])
            end
        else error("Unsupported engine normalization: "..tostring(actual.type)) end
        copy.nitrousOxideInjection={isExisting=false}
        -- native engines: rated without the nitrous shot (2026-10-17). Their
        -- final torque curve adds it permanently (Rockbouncer N2O: 1014 Nm at
        -- 4-5k rpm against 564 Nm measured with nitrous off); nitrous is
        -- limited and governed by race rules. Automation engines unchanged.
        if jd.nitrousOxideInjection and data[jd.nitrousOxideInjection] and actual.type=='camsoEngine' then
            assert(not jd.nitrousOxideLuaFileName or jd.nitrousOxideLuaFileName=='powertrain/nitrousOxideInjection',
                'Unsupported custom nitrous module')
            copy.nitrousOxideInjection=shadowModule('powertrain/nitrousOxideInjection',copy,data[jd.nitrousOxideInjection])
        end
        local td=copy:getTorqueData()
        local curve=td.curves[td.finalCurveName] or td.curves[1]
        local torque={}
        local step=math.max(100,math.floor((td.maxRPM or 8000)/80/50)*50)
        for rpm=0,math.floor(td.maxRPM or 0),step do
            local t=curve.torque[rpm] or curve.torque[rpm+1]
            if t then
                torque[#torque+1]={rpm,round(t,1)}
            end
        end
        local maxRPM=td.maxRPM
        if actual.type=='camsoEngine' and data.engineSpec then
            local effects=require('common/raceprep/engineEffects')
            local spec=deepcopy(data.engineSpec)
            spec.pressurePoints={}
            for rpm=0,spec.stockRevLimit,100 do spec.pressurePoints[#spec.pressurePoints+1]={rpm,copy.peakPressureCurve[rpm] or 1} end
            -- "pi": race sliders at their best setting, turbo lag discounted
            torque,maxRPM=effects.curve(torque,spec.stockRevLimit,spec,'pi')
            local peak=0
            for _,p in ipairs(torque) do if p[1]*p[2]>peak then peak=p[1]*p[2];td.maxPowerRPM=p[1] end end
        end
        if actual.type=='combustionEngine' and data.engineSpec and data.engineSpec.native then
            assert(data.nativeBase,'Native engine factory reference unavailable')
            local reference
            for _,candidate in ipairs(engineData(data.nativeBase)) do if candidate.name==actual.name then reference=candidate end end
            assert(reference,'Native engine factory identity unavailable')
            if reference then
                data.engineSpec.nativeTier=data.nativeBase.nativeTier
                local scale
                if data.statsLive then
                    scale=(data.nativeEngineScales or {})[actual.name] or 1
                    for _,p in ipairs(torque) do p[2]=p[2]*scale end
                else
                    local rated=torque
                    if data.nativeBase.nativeMax then
                        for _,candidate in ipairs(engineData(data.nativeBase.nativeMax)) do if candidate.name==actual.name then rated=candidate.torque;maxRPM=candidate.maxRPM end end
                    end
                    torque,scale=require('common/raceprep/engineEffects').limitNative(rated,reference.torque,deepcopy(data.engineSpec))
                end
                local peak=0;for _,p in ipairs(torque) do if p[1]*p[2]>peak then peak=p[1]*p[2];td.maxPowerRPM=p[1] end end
                data._nativeEngineScales=data._nativeEngineScales or {};data._nativeEngineScales[actual.name]=scale
                if not data.preview and not data.statsLive then
                    extensions.load('raceprepPower')
                    raceprepPower.applyNativeScale(actual,scale)
                end
            end
        end
        out[#out+1]={name=actual.name,type=actual.type,maxRPM=maxRPM,maxPowerRPM=td.maxPowerRPM,torque=torque}
    end
    return out
end
function M.collect(data,requestID)
    local ok,result=pcall(function()
        local mass,sumY=0,0
        for _,n in pairs(data.nodes) do
            local m=n.nodeWeight or 0
            mass,sumY=mass+m,sumY+m*n.pos.y
        end
        local ws={}
        for _,w in pairs(data.wheels or {}) do
            local a,b=data.nodes[w.node1],data.nodes[w.node2]
            ws[#ws+1]={name=w.name,radius=round(w.radius,4),tireWidth=round(w.tireWidth,4),
                noLoadCoef=round(w.noLoadCoef,4),fullLoadCoef=round(w.fullLoadCoef,4),
                loadSensitivitySlope=round(w.loadSensitivitySlope,8),frictionCoef=w.frictionCoef,compound=w.compound,brakeTorque=round(w.brakeTorque or 0,1),abs=w.abs,
                y=round((a.pos.y+b.pos.y)*0.5,3)}
        end
        table.sort(ws,function(a,b) return a.name<b.name end)
        local gb,fd={},{}
        for _,device in pairs(data.powertrain or {}) do
            local jd=deepcopy(device)
            tableMergeRecursive(jd,data[jd.name] or {})
            if tostring(jd.type):lower():find("gearbox") then
                local forward={}
                -- JBeam gear arrays include reverse and neutral at the front.
                for _,ratio in ipairs(jd.gearRatios or {}) do if ratio>0 then forward[#forward+1]=round(ratio,4) end end
                gb[#gb+1]={name=jd.name,forward=forward,type=jd.type}
            elseif jd.type=="differential" then fd[#fd+1]={name=jd.name,ratio=round(jd.gearRatio or 1,4)}
            elseif jd.type=="shaft" and jd.gearRatio and jd.gearRatio~=1 then
                fd[#fd+1]={name=jd.name,ratio=round(jd.gearRatio,4),shaft=true}
            end
        end
        -- rating: a kit counts at its maximum; stats (statsLive): the sliders as set
        if data.raceprepAero and not data.statsLive then
            local kit=data.raceprepAero
            data.downforceModel=deepcopy(data.downforceModel or {})
            data.dragModel=deepcopy(data.dragModel or {})
            data.downforceModel.downforceTargetFront=kit.ratedFrontN
            data.downforceModel.downforceTargetRear=kit.ratedRearN
            data.downforceModel.targetSpeedKMH=200
            data.dragModel.vehicleArea=kit.ratedCdA
            -- formula v6 rates the kit's extra drag on its own (stock CdA kept)
            data.raceprepKitBaseCdA=kit.baseCdA
        elseif data.raceprepAero then
            data.raceprepKitBaseCdA=data.raceprepAero.baseCdA
        end
        -- formula v6: centre-of-gravity height above the tyre contact patches,
        -- wheelbase and front track from the design-time nodes; stock springs
        -- (average per axle) and sway bars of the fitted parts
        local geometry,suspension
        do
            -- optional: incomplete node positions only skip the v6 inputs
            local cz,ground,fy,ry,nf,nr,fx=0,math.huge,0,0,0,0,{}
            local complete=true
            for _,n in pairs(data.nodes) do
                -- positions are vec3 objects in the game (not plain tables)
                local z=n.pos and tonumber(n.pos.z)
                if z then cz=cz+(n.nodeWeight or 0)*z else complete=false end
            end
            for _,w in pairs(complete and data.wheels or {}) do
                local a,b=data.nodes[w.node1],data.nodes[w.node2]
                if a and b and w.radius and tonumber(a.pos.x) and tonumber(b.pos.x) then
                    local y,z,x=(a.pos.y+b.pos.y)*0.5,(a.pos.z+b.pos.z)*0.5,(a.pos.x+b.pos.x)*0.5
                    ground=math.min(ground,z-w.radius)
                    if tostring(w.name):sub(1,1):upper()=='F' then fy,nf=fy+y,nf+1;fx[#fx+1]=x else ry,nr=ry+y,nr+1 end
                end
            end
            table.sort(fx)
            if complete and mass>0 and nf>0 and nr>0 and ground<math.huge then
                geometry={cogHeight=round(cz/mass-ground,4),wheelbase=round(math.abs(ry/nr-fy/nf),4),
                    trackF=#fx>=2 and round(fx[#fx]-fx[1],4) or nil}
            end
            local sp=(data.suspension or {}).springs or {}
            local bars=(data.suspension or {}).bars or {}
            if sp.spring_FL and sp.spring_FR and sp.spring_RL and sp.spring_RR then
                suspension={springF=(sp.spring_FL+sp.spring_FR)/2,springR=(sp.spring_RL+sp.spring_RR)/2,
                    barF=bars.torsionBarFront or 0,barR=bars.torsionBarRear or 0}
            end
        end
        local shift=data.vehicleController or {}
        local driven,drivenWheels={F=false,R=false},{}
        for _,w in pairs(wheels.wheels or {}) do
            if w.isPropulsed then
                driven[w.name:sub(1,1):upper()=='F' and 'F' or 'R']=true
                drivenWheels[w.name]=true
            end
        end
        local drive=driven.F and driven.R and 'AWD' or driven.F and 'FWD' or driven.R and 'RWD' or nil
        local kind=require('common/raceprep/engineKind').detect(powertrain.getDevicesByCategory('engine'),data)
        local engines=engineData(data)
        if data.preview then
            if data.previewDrive then
                drive=data.previewDrive;drivenWheels={}
                for _,w in ipairs(ws) do local front=w.name:sub(1,1):upper()=='F';if drive=='AWD'or drive=='4WD'or (drive=='FWD')==front then drivenWheels[w.name]=true end end
            elseif kind.kind~='automation' then
                -- A draft may connect an axle that is not driven on the live
                -- car. Resolve the future graph instead of its live wheel flags.
                local names={};for _,e in ipairs(engines)do names[e.name]=true end
                drivenWheels={};local front,rear=false,false
                for _,row in pairs(data.powertrain or {})do
                    local wheel=(data[row.name]or{}).connectedWheel or row.connectedWheel
                    if wheel then
                        local path=require('common/raceprep/driveline').resolve(data.powertrain,data,{[wheel]=true},names)
                        if path then drivenWheels[wheel]=true;if wheel:sub(1,1):upper()=='F'then front=true else rear=true end end
                    end
                end
                drive=front and rear and'AWD'or front and'FWD'or rear and'RWD'or nil
            end
        end
        local driveline
        if kind.kind~='automation' then
            local names={}
            for _,e in ipairs(engines) do names[e.name]=true end
            local effective,err,paths=require('common/raceprep/driveline').resolve(data.powertrain,data,drivenWheels,names)
            driveline={paths=paths,error=err,normalized=effective~=nil}
            if effective then fd=effective end
        end
        if kind.kind=='electric' and #gb==0 then
            -- Fixed-drive motors never upshift at their power peak. Give the
            -- existing evaluator the canonical motor limit, not an ICE-like
            -- inferred shift point that truncates their high-speed torque.
            shift={}
            for key,value in pairs(data.vehicleController or {}) do shift[key]=value end
            local maxRPM=0
            for _,e in ipairs(engines) do maxRPM=math.max(maxRPM,e.maxRPM or 0) end
            shift.highShiftUpRPM=maxRPM
        end
        return {mass=round(mass,1),comY=round(sumY/mass,3),geometry=geometry,suspension=suspension,
            engineKind=kind,engines=engines,wheels=ws,nativeEngineScales=data._nativeEngineScales,
            gearboxes=gb,finalDrives=fd,driveline=driveline,shift={highShiftUpRPM=shift.highShiftUpRPM,topSpeedLimit=tonumber(shift.topSpeedLimit)},drive=drive,
            aero=data.downforceModel and {downforceTargetFront=data.downforceModel.downforceTargetFront,
                downforceTargetRear=data.downforceModel.downforceTargetRear,targetSpeedKMH=data.downforceModel.targetSpeedKMH,
                vehicleArea=(data.dragModel or {}).vehicleArea,kitBaseCdA=data.raceprepKitBaseCdA} or {vehicleArea=(data.dragModel or {}).vehicleArea}}
    end)
    if not ok then result={error=tostring(result)} end
    obj:queueGameEngineLua(string.format('raceprepRatings.onStatic(%d,%q,%s)',obj:getID(),requestID,serialize(result)))
end
-- Live shop statistics are kept separate from the canonical PI input.
function M.snapshot(token)
    local ok,result=pcall(function()
        local mass,sumY=0,0
        for _,node in pairs(v.data.nodes or {}) do
            local weight=obj:getNodeMass(node.cid)
            mass,sumY=mass+weight,sumY+weight*node.pos.y
        end
        local ws={}
        for _,wheel in pairs(v.data.wheels or {}) do
            local a,b=v.data.nodes[wheel.node1],v.data.nodes[wheel.node2]
            if a and b then ws[#ws+1]={name=wheel.name,y=(a.pos.y+b.pos.y)*.5} end
        end
        local live,base={},{}
        local function sample(engine)
            local td=engine:getTorqueData()
            local curve=td.curves[td.finalCurveName] or td.curves[1]
            local points={}
            for rpm=0,math.floor(td.maxRPM or 0),100 do
                local value=curve.torque[rpm] or curve.torque[rpm+1]
                if value then points[#points+1]={rpm,value} end
            end
            return {name=engine.name,torque=points,maxPowerHp=td.maxPower,maxTorque=td.maxTorque}
        end
        for _,engine in pairs(powertrain.getDevicesByCategory('engine') or {}) do
            live[#live+1]=sample(engine)
            local shadow={}
            for key,value in pairs(engine) do shadow[key]=value end
            if engine.type=='camsoEngine' and engine._raceprepPowerBase then
                shadow.torqueThrottleMap=engine._raceprepPowerBase.torque
                shadow.frictionTorqueTable=engine._raceprepPowerBase.friction
                shadow.torqueCurve=shadow.torqueThrottleMap[99]
                shadow.getTorqueData=engine._raceprepTorqueGetter or engine.getTorqueData
                if engine.raceprepEngineSpec then shadow.maxRPM=engine.raceprepEngineSpec.stockRevLimit end
            end
            -- Stage gains describe engine power, not an extra nitrous shot.
            shadow.nitrousOxideInjection={isExisting=false}
            local reference=sample(shadow)
            if engine.type=='camsoEngine' then
                local pressure=engine._raceprepPowerBase and engine._raceprepPowerBase.pressure or engine.peakPressureCurve
                if pressure then
                    reference.pressurePoints={}
                    for rpm=0,math.floor(shadow.maxRPM or 0),100 do
                        reference.pressurePoints[#reference.pressurePoints+1]={rpm,pressure[rpm] or 1}
                    end
                end
            end
            base[#base+1]=reference
        end
        return {mass=mass,comY=sumY/mass,wheels=ws,engines=live,stageBaseEngines=base}
    end)
    if not ok then result={error=tostring(result)} end
    obj:queueGameEngineLua(string.format('raceprepRatings.onLiveSnapshot(%d,%q,%s)',obj:getID(),token,serialize(result)))
end
return M
