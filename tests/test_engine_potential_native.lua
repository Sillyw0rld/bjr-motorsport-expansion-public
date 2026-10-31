package.path='client/lua/?.lua;'..package.path
local P=dofile('client/lua/vehicle/extensions/raceprepPower.lua')
local e={name='mainEngine',type='combustionEngine',torqueCurve={[0]=100,[1000]=200},friction=20,dynamicFriction=.01}
e.getTorqueData=function(self)return {maxPower=self.torqueCurve[1000]-self.friction,maxTorque=self.torqueCurve[1000]}end
local ev={name='electric',type='electricMotor',torqueCurve={[0]=300}}
powertrain={getDevicesByCategory=function()return{e,ev}end}
P.applyNativeScales({mainEngine=.8,electric=.1})
assert(e.torqueCurve[1000]==160 and e.friction==16 and ev.torqueCurve[0]==300)
P.applyNativeScales({mainEngine=.8});assert(e.torqueCurve[1000]==160,'cached spawn/reset does not compound')
P.applyNativeScales({mainEngine=.6});assert(e.torqueCurve[1000]==120 and e.friction==12,'changed policy derives from unmodified curve')
-- The scale is from canonical/rated tuning; it is never recalculated from a
-- reduced boost slider, so lowering boost cannot be silently cancelled out.
local reducedBoost=.5
assert(e.torqueCurve[1000]*reducedBoost==60)
assert(not P.applyNativeScale(ev,.5)and ev.torqueCurve[0]==300)
assert(not pcall(P.applyNativeScale,e,math.huge))
print('PASS: cached native scales, no compounding, policy replacement, tuning range and unchanged electric motors')
