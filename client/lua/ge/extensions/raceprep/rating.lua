-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Formula v2 / v6 and virtual laps, ported from beamng-car-rating/calib.
-- AGPL-3.0-or-later (see LICENSE). Constants are supplied by the seed; never refit the scale.
-- v6 (constants.v6, 2026-10-15; calib/fit3/REPORT-2026-10-15.md) reads the
-- car files as the instrumented rig measured them: aero downforce fully
-- counted, drivetrain efficiency and AWD loss as measured, traction with
-- longitudinal weight transfer, and a chassis-softness penalty (body roll per
-- g from the stock springs and sway bars of the fitted parts, never the tune).
local M = {}
local G, RHO, V200 = 9.81, 1.2, 200 / 3.6
M.classes = { "E", "D", "C", "B", "A", "S", "R", "P", "X" }

function M.classOf(pi)
    for _, band in ipairs({ {999,"X"}, {901,"P"}, {801,"R"}, {701,"S"},
            {601,"A"}, {501,"B"}, {401,"C"}, {301,"D"} }) do
        if pi >= band[1] then return band[2] end
    end
    return "E"
end

local function axle(name) return name and name:sub(1, 1):upper() == "F" and "F" or "R" end
local function finite(x) return type(x) == "number" and x == x and math.abs(x) < math.huge end
M.finite = finite
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

function M.buildCar(st, drive)
    assert(type(st) == "table" and finite(st.mass) and st.mass > 0, "No usable vehicle mass")
    local ws = { F = {}, R = {} }
    -- native inboard brakes (ATV): virtual wheels with brake torque but no
    -- tyre; their braking is shared by both axles, they are not tyres
    local inboard = 0
    for _, w in ipairs(st.wheels or {}) do
        if w.noLoadCoef == nil and w.tireWidth == nil and finite(w.brakeTorque) and finite(w.radius) and w.radius > 0 then
            inboard = inboard + w.brakeTorque / w.radius
            goto nextWheel
        end
        assert(finite(w.y) and finite(w.radius) and w.radius > 0 and
            finite(w.tireWidth) and w.tireWidth > 0 and finite(w.noLoadCoef) and w.noLoadCoef > 0,
            "Unsupported wheel data")
        table.insert(ws[axle(w.name)], w)
        ::nextWheel::
    end
    assert(#ws.F > 0 and #ws.R > 0 and finite(st.comY), "Front/rear wheel geometry unavailable")
    local ys = {}
    for _, a in ipairs({"F","R"}) do
        local y = 0
        for _, w in ipairs(ws[a]) do y = y + w.y end
        ys[a] = y / #ws[a]
    end
    local wb = ys.R - ys.F
    assert(math.abs(wb) > 0.1, "Unsupported wheelbase")
    local share = (ys.R - st.comY) / wb
    assert(share > 0.01 and share < 0.99, "Unsupported weight distribution")
    local c = { mass = st.mass + 40, w = {F=share,R=1-share}, axle={}, df200={}, torque={}, gears={} }
    for _, a in ipairs({"F","R"}) do
        local coef, width, brake = 0, 0, 0
        for _, w in ipairs(ws[a]) do
            coef, width = coef + w.noLoadCoef, width + w.tireWidth * 1000
            brake = brake + (w.brakeTorque or 0) / w.radius
        end
        -- ABS (v7): false only when the car's wheels say so (Automation data has no flag)
        local abs = true
        for _, w in ipairs(ws[a]) do if w.abs == false then abs = false end end
        c.axle[a] = {coef=coef/#ws[a],width=width,brakeF=brake+inboard/2,radius=ws[a][1].radius,abs=abs,
            driven=drive=="AWD" or drive=="4WD" or ((drive=="FWD") == (a=="F"))}
    end
    local ae = st.aero or {}
    local ts = ae.targetSpeedKMH or 200
    assert(ts > 0, "Invalid aero reference speed")
    local factor = (200/ts)^2
    c.df200.F, c.df200.R = (ae.downforceTargetFront or 0)*factor, (ae.downforceTargetRear or 0)*factor
    c.cda = ae.vehicleArea or 0.7
    if finite(ae.kitBaseCdA) and ae.kitBaseCdA > 0 then c.kitBaseCdA = ae.kitBaseCdA end
    -- native (BeamNG) cars: aero is triangles, not Automation's area and
    -- downforce targets. nativeAero is the engine's own force on the car under
    -- a 200 km/h headwind (static probe): true CdA and per-axle downforce in N.
    -- electric drive (v7 native): single reduction, measured wheel/motor power 0.95
    c.electric = type(st.engineKind) == "table" and st.engineKind.kind == "electric"
    local na = st.nativeAero
    if type(na) == "table" and finite(na.cdA) and na.cdA > 0 and finite(na.dfF200) and finite(na.dfR200) then
        c.nativeAero = true
        c.cda = na.cdA
        c.df200.F, c.df200.R = na.dfF200, na.dfR200
    end
    local curve, maxRPM, peakRPM = {}, 0, 0
    for _, e in ipairs(st.engines or {}) do
        maxRPM, peakRPM = math.max(maxRPM,e.maxRPM or 0), math.max(peakRPM,e.maxPowerRPM or 0)
        for _, p in ipairs(e.torque or {}) do curve[p[1]] = (curve[p[1]] or 0) + p[2] end
    end
    assert(next(curve), "No supported engine torque curve")
    if maxRPM == 0 then maxRPM = 8000 end
    if peakRPM == 0 then peakRPM = maxRPM end
    c.shiftRPM = math.min(math.max((st.shift or {}).highShiftUpRPM or 0,peakRPM*1.05),maxRPM)
    -- v7 native: top gear runs to the rev limiter; an ECU speed limiter
    -- (vehicleController.topSpeedLimit, m/s) caps top speed
    c.maxRPM = maxRPM
    local limit = tonumber((st.shift or {}).topSpeedLimit)
    if finite(limit) and limit > 5 then c.topSpeedLimit = limit end
    for r,t in pairs(curve) do table.insert(c.torque,{r,t}) end
    table.sort(c.torque,function(a,b) return a[1]<b[1] end)
    local final, found, shafts = 0, false, 1
    for _, f in ipairs(st.finalDrives or {}) do
        if f.shaft then shafts = shafts * ((f.ratio or 0)>0 and f.ratio or 1)
        elseif f.ratio then final, found = math.max(final,f.ratio), true end
    end
    final = (found and final or 1) * shafts
    local gb = st.gearboxes and st.gearboxes[1] and st.gearboxes[1].forward or {1}
    for _, gr in ipairs(gb) do if gr>0 then table.insert(c.gears,gr*final) end end
    c.cvt, c.peakW = #c.gears==0, 0
    -- gearbox type for the shift-time term: manual / sequential / dct / cvt / automatic
    local gtype = tostring(st.gearboxes and st.gearboxes[1] and st.gearboxes[1].type or ""):lower()
    c.gearType = "other"
    for _, k in ipairs({"manual","sequential","dct","cvt","automatic"}) do
        if gtype:sub(1,#k)==k then c.gearType=k break end
    end
    for _, p in ipairs(c.torque) do c.peakW=math.max(c.peakW,p[2]*p[1]*2*math.pi/60) end
    -- v6 inputs: CoG height / wheelbase / front track, stock springs and sway
    -- bars (absent on old data: no weight transfer, no softness penalty)
    local geo, sus = st.geometry, st.suspension
    if type(geo) == "table" and finite(geo.cogHeight) and finite(geo.wheelbase) and geo.wheelbase > 0.5 then
        c.hL = geo.cogHeight / geo.wheelbase
        if type(sus) == "table" and finite(sus.springF) and finite(sus.springR) and sus.springF + sus.springR > 0 then
            c.soft = { h = geo.cogHeight, track = math.max(0.8, tonumber(geo.trackF) or 1.5), kF = sus.springF, kR = sus.springR,
                bars = (tonumber(sus.barF) or 0) + (tonumber(sus.barR) or 0) }
        end
    end
    return c
end

--- body roll per g (degrees) from the stock suspension; nil without data
function M.rollPerG(c, cbar)
    local s = c.soft
    if not s then return nil end
    local K = (s.kF + s.kR) * s.track * s.track / 2 + (cbar or 20) * s.bars
    if K <= 0 then return nil end
    return math.deg(c.mass * G * s.h / K)
end

local function torqueAt(c,rpm)
    local curve=c.torque
    if rpm<curve[1][1] or rpm>curve[#curve][1] then return 0 end
    for i=1,#curve-1 do
        local a,b=curve[i],curve[i+1]
        if a[1]<=rpm and rpm<=b[1] then return a[2]+(b[2]-a[2])*(rpm-a[1])/math.max(b[1]-a[1],1) end
    end
    return curve[#curve][2]
end
local function loads(c,v,eta)
    local q=(v/V200)^2
    return {F=c.mass*G*c.w.F+eta*c.df200.F*q,R=c.mass*G*c.w.R+eta*c.df200.R*q}
end
local function mu(c,a,n,p)
    local ax=c.axle[a]
    return p[1]*ax.coef^p[2]*(math.max(n,1)/ax.width/5000)^(-p[3])
end
local function curves(c,p)
    local lat,brk,acc={}, {}, {}
    local pl,pb,pa=p.cornering,p.braking,p.accel
    local eff=pa[1]*(c.axle.F.driven and c.axle.R.driven and (pa[3] or 1) or 1)
    local top
    local gearAt={}
    for kmh=10,450,10 do
        local v=kmh/3.6
        local n=loads(c,v,pl[4])
        local af=mu(c,"F",n.F,pl)*n.F/(c.mass*c.w.F)
        local ar=mu(c,"R",n.R,pl)*n.R/(c.mass*c.w.R)
        assert(af>0 and ar>0,"Unsupported axle lift")
        table.insert(lat,{v,(af^-6+ar^-6)^(-1/6)})
        local f=0
        for _,a in ipairs({"F","R"}) do f=f+math.min(pb[1]*mu(c,a,n[a],pl)*n[a],pb[2]*c.axle[a].brakeF) end
        table.insert(brk,{v,(f+0.5*RHO*c.cda*v*v)/c.mass})
        local best=c.cvt and eff*c.peakW/math.max(v,1) or 0
        local bestGear
        local r=c.axle.R.radius
        for i,gr in ipairs(c.gears) do
            local rpm=v/r*gr*60/(2*math.pi)
            if i==1 then rpm=math.max(rpm,3000) end
            if rpm>=1000 and rpm<=c.shiftRPM*1.02 then
                local f=torqueAt(c,rpm)*gr*eff/r
                if f>best then best,bestGear=f,i end
            end
        end
        gearAt[#acc+1]=bestGear
        local trac=0
        for _,a in ipairs({"F","R"}) do if c.axle[a].driven then trac=trac+pa[2]*mu(c,a,n[a],pl)*n[a] end end
        local acceleration=(math.min(best,trac)-0.5*RHO*c.cda*v*v-0.015*c.mass*G)/c.mass
        if not top and acceleration<=0 then top=v end
        table.insert(acc,{v,math.max(acceleration,0)})
    end
    -- Shift time per gearbox type (p.shift, seconds): within each gear but
    -- the top one, acceleration over the gear's speed range dv loses the
    -- shift: a_eff = a / (1 + a * t / dv). Manual gearboxes lose the most.
    local t=p.shift and tonumber(p.shift[c.gearType]) or 0
    if t>0 and not c.cvt then
        local span,topGear={},0
        for i,g in pairs(gearAt) do
            local v=acc[i][1]
            local s=span[g] or {v,v}
            span[g]={math.min(s[1],v),math.max(s[2],v)}
            topGear=math.max(topGear,g)
        end
        for i,point in ipairs(acc) do
            local g=gearAt[i]
            if g and g~=topGear and point[2]>0 then
                local dv=math.max(1,span[g][2]-span[g][1])
                point[2]=point[2]/(1+point[2]*t/dv)
            end
        end
    end
    return {lat=lat,brk=brk,acc=acc,top=top or 450/3.6}
end
local function curvesV6(c,p,v6)
    -- Race Prep aero kit: its extra drag measured x kitDrag of the rated figure
    -- (top speed and high-speed acceleration of 14 kit builds, 2026-10-15)
    if c.kitBaseCdA and v6.kitDrag then
        local k={}
        for key,value in pairs(c) do k[key]=value end
        k.cda=c.kitBaseCdA+v6.kitDrag*(c.cda-c.kitBaseCdA)
        c=k
    end
    local lat,brk,acc={}, {}, {}
    local pl={v6.cornering[1],v6.cornering[2],v6.cornering[3],v6.cornering[4]}
    local pb,ac=v6.braking or p.braking,v6.accel
    -- native aero is the measured force itself: no file-area drag factor and
    -- all of the downforce (v7)
    if c.nativeAero then pl[4]=1 end
    local dragScale=c.nativeAero and 1 or ac.drag
    local eff=ac.eff*(c.axle.F.driven and c.axle.R.driven and ac.awd or 1)
    local roll=M.rollPerG(c,v6.softness.cbar)
    local f=v6.latScale/(1+v6.softness.q*math.max(0,(roll or 0)-v6.softness.r0))
    if not roll then f=v6.latScale end
    -- v7: native cars run BeamNG's own tyres, which the tyre simulation treats
    -- differently from Automation's; their grip and braking are scaled on
    -- their own (fitted on the native fleet; Automation cars are pure v6)
    local nat=c.nativeAero and v6.native or nil
    -- native electric drive: its own measured efficiency, AWD loss included
    if nat and c.electric and nat.evEff then eff=nat.evEff
    -- native gearboxes: measured wheel/engine power per gearbox type (AWD included)
    elseif nat and nat.eff and nat.eff[c.gearType] then eff=nat.eff[c.gearType] end
    local nbrk=nat and nat.brake or 1
    if nat then
        f=(nat.lat or 1)/(1+(nat.q or 0)*math.max(0,(roll or 0)-(nat.r0 or 0)))
        if not roll then f=nat.lat or 1 end
    end
    local top
    for kmh=10,450,10 do
        local v=kmh/3.6
        local n=loads(c,v,pl[4])
        local af=mu(c,"F",n.F,pl)*n.F/(c.mass*c.w.F)
        local ar=mu(c,"R",n.R,pl)*n.R/(c.mass*c.w.R)
        assert(af>0 and ar>0,"Unsupported axle lift")
        table.insert(lat,{v,(af^-6+ar^-6)^(-1/6)*f})
        local fb=0
        for _,a in ipairs({"F","R"}) do
            -- v7: native axles without ABS lock their wheels at full braking
            local lock=(nat and c.axle[a].abs==false) and (nat.noAbs or 1) or 1
            fb=fb+math.min(pb[1]*mu(c,a,n[a],pl)*n[a],pb[2]*c.axle[a].brakeF)*lock
        end
        table.insert(brk,{v,(fb*nbrk+0.5*RHO*c.cda*v*v)/c.mass})
        local best=c.cvt and eff*c.peakW/math.max(v,1) or 0
        local r=c.axle.R.radius
        for i,gr in ipairs(c.gears) do
            local rpm=v/r*gr*60/(2*math.pi)
            if i==1 then rpm=math.max(rpm,3000) end
            local cap=(nat and i==#c.gears and c.maxRPM) or c.shiftRPM*1.02
            if rpm>=1000 and rpm<=cap then
                local fw=torqueAt(c,rpm)*gr*eff/r
                if fw>best then best=fw end
            end
        end
        local drag=0.5*RHO*c.cda*dragScale*v*v+0.015*c.mass*G
        -- longitudinal weight transfer: the rear gains m a h / L under acceleration
        local a=(best-drag)/c.mass
        for _=1,6 do
            local dN=c.mass*math.max(0,a)*(c.hL or 0)
            local N={F=math.max(1,n.F-dN),R=n.R+dN}
            local trac=0
            for _,ax in ipairs({"F","R"}) do if c.axle[ax].driven then trac=trac+ac.kt*mu(c,ax,N[ax],pl)*N[ax] end end
            local aNew=(math.min(best,trac)-drag)/c.mass
            if math.abs(aNew-a)<1e-4 then a=aNew break end
            a=0.5*(a+aNew)
        end
        if nat and c.topSpeedLimit and v>=c.topSpeedLimit then a=0 end
        if not top and a<=0 then top=nat and c.topSpeedLimit and math.min(v,c.topSpeedLimit) or v end
        table.insert(acc,{v,math.max(a,0)})
    end
    return {lat=lat,brk=brk,acc=acc,top=top or 450/3.6,roll=roll}
end
local function interp(points,v)
    if v<=points[1][1] then return points[1][2] end
    for i=1,#points-1 do
        local a,b=points[i],points[i+1]
        if a[1]<=v and v<=b[1] then return a[2]+(b[2]-a[2])*(v-a[1])/(b[1]-a[1]) end
    end
    return points[#points][2]
end
local FAST={{1100},{20,90},{20,90},{600},{350,90},{900},{120,90},{500},{200,180},{400},{45,90}}
local TECH={{350},{15,180},{250},{35,90},{25,90},{200},{70,90},{150},{50,120},{300},{120,90},{90,60},{180},{30,90}}
local function lap(cur,spec)
    local lim={}
    for _,s in ipairs(spec) do
        local length=s[2] and s[1]*s[2]*math.pi/180 or s[1]
        local speed=cur.top
        if s[2] then
            speed=1
            for _=1,60 do speed=math.min(cur.top,math.sqrt(math.max(interp(cur.lat,speed),0.1)*s[1])) end
        end
        for _=1,math.max(1,math.floor(length/2)) do table.insert(lim,speed) end
    end
    local v, speed={},lim[#lim]
    for _=1,2 do
        for i=1,#lim do speed=math.min(lim[i],math.sqrt(math.max(speed*speed+4*math.max(interp(cur.acc,speed),0),1))); v[i]=speed end
    end
    speed=v[1]
    for _=1,2 do
        for i=#lim,1,-1 do speed=math.min(v[i],math.sqrt(speed*speed+4*interp(cur.brk,speed)));v[i]=speed end
    end
    local time=0
    for _,x in ipairs(v) do time=time+2/x end
    return time
end
function M.compute(st,constants,drive)
    local ok,result=pcall(function()
        local v6=constants.v7 or constants.v6
        local cur=v6 and curvesV6(M.buildCar(st,drive),constants.params,v6) or curves(M.buildCar(st,drive),constants.params)
        local mix={}
        for _,s in ipairs(FAST) do table.insert(mix,s) end
        for _,s in ipairs(TECH) do table.insert(mix,s) end
        local times={mix=lap(cur,mix),fast=lap(cur,FAST),tech=lap(cur,TECH)}
        local cor=v6 and v6.correction or constants.correction
        local ratio=math.exp(cor.alpha+cor.beta*math.log(times.mix))/times.mix
        local out={source="computed",method=constants.v7 and "formula-v7" or v6 and "formula-v6" or "formula-v2-corrected",assumptions="Sport / 40 kg fuel / warm KTS tyres"}
        if cur.roll then out.rollPerG=math.floor(cur.roll*100+0.5)/100 end
        out.raw={}
        for k,field in pairs({mix="pi",fast="pi_speed",tech="pi_technical"}) do
            local scale=constants.scale[k]
            local value=scale[1]-scale[2]*math.log(times[k]*ratio)
            assert(finite(value),"Invalid rating")
            local raw=math.max(100,math.floor(value+0.5))
            out.raw[field]=raw
            out[field]=M.curve(raw,constants or false)
        end
        out.class=M.classOf(out.pi)
        return out
    end)
    if ok then return result end
    return nil,tostring(result)
end
-- Forza-style performance figures from the same curves as PI (Setup panel).
-- Fed with the car as tuned (raceprepRatings.getStats); PI itself never is.
local MPH=0.44704
function M.performance(st,constants,drive)
    local ok,result=pcall(function()
        local v6=constants.v7 or constants.v6
        local cur=v6 and curvesV6(M.buildCar(st,drive),constants.params,v6) or curves(M.buildCar(st,drive),constants.params)
        local function time(v1,v2)
            local t,dv=0,0.05
            for v=v1,v2-dv/2,dv do
                local a=interp(cur.acc,v+dv/2)
                if a<0.05 then return nil end
                t=t+dv/a
            end
            return t
        end
        local function stop(v0)
            local s,dv=0,0.05
            for v=0,v0-dv/2,dv do s=s+(v+dv/2)*dv/math.max(interp(cur.brk,v+dv/2),0.1) end
            return s
        end
        return {zeroTo60=time(0,60*MPH),sixtyTo100=time(60*MPH,100*MPH),brake60=stop(60*MPH),brake120=stop(120*MPH),
            lat60=interp(cur.lat,60*MPH)/G,lat120=interp(cur.lat,120*MPH)/G,topSpeed=cur.top}
    end)
    if ok then return result end
    return nil,tostring(result)
end
function M.violation(rules,entry,status)
    local classes=rules.allowedClasses or {}
    local restricted=rules.piMin or rules.piMax
    for _,c in ipairs(M.classes) do if classes[c]==false then restricted=true end end
    if not entry then return restricted and (status or "Waiting for car rating") or nil end
    if classes[entry.class]==false then return "Class "..entry.class.." is not allowed" end
    if rules.piMin and entry.pi<rules.piMin then return string.format("PI %d is below minimum %d",entry.pi,rules.piMin) end
    if rules.piMax and entry.pi>rules.piMax then return string.format("PI %d exceeds maximum %d",entry.pi,rules.piMax) end
end
return M
