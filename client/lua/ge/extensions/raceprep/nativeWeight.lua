-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Native Additional Modification holder; no Automation slot/variable assumptions.
local N={STAGES={
 {key='stock',label='Stock body',scale=1,percent=0},
 {key='street',label='Street body',scale=.96,percent=4},
 {key='sport',label='Sport body',scale=.93,percent=7},
 {key='race',label='Race body',scale=.85,percent=15}, -- no extra PI: the formula counts the lower mass (owner 2026-10-21)
}}
local function model(d) return d and ((d.vdata or {}).model or (d.config or {}).model) end
function N.native(d,catalog)
 local native=false
 for _,p in pairs((d and d.vdata or {}).powertrain or {}) do
  local kind=p.type or p[1];if kind=='camsoEngine' then return false end
  if kind=='combustionEngine' or kind=='electricMotor' then native=true end
 end
 return native or (catalog and catalog.nativeBodies and catalog.nativeBodies.models and catalog.nativeBodies.models[model(d)]~=nil) or false
end
function N.find(key) for _,s in ipairs(N.STAGES) do if s.key==key then return s end end end
local function copy(t) if type(t)~='table' then return t end local o={} for k,v in pairs(t) do o[k]=copy(v) end return o end
local function node(t,id)
 for name,c in pairs(t and t.children or {}) do if name==id then return c end local found=node(c,id);if found then return found end end
end
function N.parts(catalog,car)
 local p=catalog and catalog.nativeBodies and catalog.nativeBodies.models and catalog.nativeBodies.models[car]
 if not p then return end
 local out=copy(p);out.stages={}
 local holder=(catalog.parts or {})[out.holder]
 if not (holder and holder.native==true and holder.model==car and holder.kind=='bodyHolder') then return end
 for name,info in pairs(catalog.parts or {}) do
  if info.native==true and info.model==car and info.kind=='body' and N.find(info.stage) then out.stages[info.stage]=name end
 end
 return out
end
function N.available(d,catalog)
 local p=N.native(d) and N.parts(catalog,model(d))
 return p and node((d.config or {}).partsTree,p.holderSlot)~=nil or false
end
function N.stage(d,catalog)
 local p=N.parts(catalog,model(d))
 for _,name in pairs((d and d.vdata or {}).activeParts or {}) do
  for key,part in pairs(p and p.stages or {}) do if name==part then return N.find(key) end end
 end
 return N.find('stock')
end
function N.applyTree(tree,catalog,car,key)
 local p=N.parts(catalog,car);local st=N.find(key)
 if not p or not st or (key~='stock' and not p.stages[key]) then return nil,'This native car has no matching body stage.' end
 local out=copy(tree);local holder=node(out,p.holderSlot)
 if not holder then return nil,'Native Additional Modification slot is missing.' end
 local current=holder.chosenPartName or '';local own=(catalog.parts or {})[current]
 if current~='' and not (own and own.native==true and own.model==car and
  (own.kind=='bodyHolder' or own.kind=='aero')) then return nil,'Remove the fitted Additional Modification before fitting a body stage.' end
 if key=='stock' then
  if current==p.holder then holder.chosenPartName='';holder.children={}
  elseif holder.children then holder.children[p.bodySlot]={id=p.bodySlot,chosenPartName='',children={}} end
 else
  if current=='' then holder.chosenPartName=p.holder;holder.children={} end
  holder.children=holder.children or {}
  holder.children[p.bodySlot]={id=p.bodySlot,chosenPartName=p.stages[key],children={}}
 end
 return out
end
function N.rows(d,catalog,mass)
 if not N.available(d,catalog) then return {} end
 local fitted=N.stage(d,catalog);local stock=tonumber(mass) and mass/fitted.scale
 local out={}
 for _,s in ipairs(N.STAGES) do out[#out+1]={key=s.key,label=s.label,percent=s.percent,fitted=s==fitted,
  kg=stock and math.floor(stock*(1-s.scale)+.5),bonus=s.bonus and math.floor(s.bonus*100+.5)} end
 return out
end
function N.problem(d,catalog)
 if not N.native(d) then return end
 local scale=tonumber(((d.vdata or {}).raceprepBody or {}).scale)
 if scale and math.abs(scale-N.stage(d,catalog).scale)>1e-6 then return 'Native body scale does not match its fitted Race Prep part.' end
end
return N
