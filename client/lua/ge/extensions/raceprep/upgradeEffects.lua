-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Shared units and car-specific upgrade effects. No rating scale is changed.
local E = {}
E.KG_TO_LB = 2.20462262185
E.NM_TO_LBFT = 0.73756214928
E.W_PER_HP = 745.699871582
E.G = 9.80665
E.RHO = 1.2041
E.V200 = 200 / 3.6
E.KITS = {
    street = {label='Street', share=.08, liftDrag=2},
    sport = {label='Sport', share=.20, liftDrag=2.5},
    race = {label='Race', share=.60, liftDrag=3},
}

function E.peaks(engines)
    -- Sum engines at matching RPM before finding peaks; never sum different
    -- engines' individual maxima at different RPM as if simultaneous.
    local curve = {}
    for _, engine in ipairs(engines or {}) do
        for _, point in ipairs(engine.torque or {}) do
            curve[point[1]] = (curve[point[1]] or 0) + point[2]
        end
    end
    local watts, torque = 0, 0
    for rpm, nm in pairs(curve) do
        watts = math.max(watts, nm * rpm * 2 * math.pi / 60)
        torque = math.max(torque, nm)
    end
    if #(engines or {})==1 then
        local engine=engines[1]
        if engine.maxPowerHp then watts=engine.maxPowerHp*E.W_PER_HP end
        if engine.maxTorque then torque=engine.maxTorque end
    end
    return {hp=watts/E.W_PER_HP, kw=watts/1000, nm=torque, lbft=torque*E.NM_TO_LBFT}
end

function E.powerGain(engines, percent)
    local p = E.peaks(engines)
    local factor = math.max(0, math.min(35, tonumber(percent) or 0)) / 100
    return {hp=p.hp*factor, kw=p.kw*factor, nm=p.nm*factor, lbft=p.lbft*factor}
end

function E.summary(st)
    local front, rear, nf, nr = 0, 0, 0, 0
    for _, wheel in ipairs(st.wheels or {}) do
        if tostring(wheel.name):sub(1,1):upper() == 'F' then front,nf=front+wheel.y,nf+1
        else rear,nr=rear+wheel.y,nr+1 end
    end
    if nf == 0 or nr == 0 or not st.mass or not st.comY then return nil end
    front,rear=front/nf,rear/nr
    if rear-front <= .1 then return nil end
    local split = (rear-st.comY)/(rear-front)
    local p = E.peaks(st.engines)
    p.massKG,p.massLB = st.mass,st.mass*E.KG_TO_LB
    p.frontShare,p.rearShare = split,1-split
    return p
end

function E.aeroBudget(massKG, stockFrontKG, stockRearKG, kit)
    local spec = assert(E.KITS[kit], 'Unknown aero kit')
    assert(massKG and massKG > 0, 'No car mass')
    stockFrontKG,stockRearKG=stockFrontKG or 0,stockRearKG or 0
    local stock = stockFrontKG+stockRearKG
    local maxTotal = math.max(stock,massKG*spec.share)
    return {stockFrontKG=stockFrontKG,stockRearKG=stockRearKG,maxKG=maxTotal,
            maxLB=maxTotal*E.KG_TO_LB,extraKG=maxTotal-stock,liftDrag=spec.liftDrag}
end

function E.aeroSetting(budget, requestedFrontLB, requestedRearLB)
    -- Both sliders share one total budget. Clamp even if a custom .pc bypasses
    -- the UI; preserve the car's existing axle downforce at every setting.
    local f=math.max(0,(requestedFrontLB or 0)/E.KG_TO_LB-budget.stockFrontKG)
    local r=math.max(0,(requestedRearLB or 0)/E.KG_TO_LB-budget.stockRearKG)
    local sum=f+r
    if sum > budget.extraKG and sum > 0 then
        local scale=budget.extraKG/sum
        f,r=f*scale,r*scale
    end
    local extra=f+r
    local dragN=extra*E.G/budget.liftDrag
    return {frontKG=budget.stockFrontKG+f,rearKG=budget.stockRearKG+r,
            extraDragN=dragN,extraCdA=dragN/(.5*E.RHO*E.V200^2)}
end
return E
