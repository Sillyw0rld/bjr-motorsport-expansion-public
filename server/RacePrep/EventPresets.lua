-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Server-owned presets. Lobby rules are immutable snapshots, never saved race rules.
local P={CATEGORIES={'Racing','Class cups','Endurance','Spec series','Fun','Build to class'}}
local path=debug.getinfo(1).source:gsub('^@',''):gsub('\\','/'):match('^(.*)/')
local Rating=dofile(path..'/RatingStore.lua')
local function copy(v) if type(v)~='table' then return v end;local t={};for k,x in pairs(v) do t[k]=copy(x) end;return t end
local function text(v,n) return type(v)=='string' and #v>0 and #v<=n and not v:find('%c') end
local function includes(t,v) for _,x in ipairs(t) do if x==v then return true end end;return false end
function P.band(class)
 local first,last
 for pi=100,999 do if Rating.classOf(pi)==class then first=first or pi;last=pi end end
 return first,last
end
function P.builtins()
 local stock={engine='none',induction='factory',engineConversion=false,drivetrainConversion='off',compound='road',width=0,weight='none',brakes='factory',radiators=false}
 local items={}
 local function add(id,name,category,description,patch,pick,laps)
  items[#items+1]={id=id,name=name,category=category,description=description,patch=patch,staffPick=pick==true,offered=true,defaultLaps=laps or 5,builtin=true}
 end
 add('stock','Stock Cup','Racing','Factory-level caps, road tyres and no nitrous.',{nitrous=false,upgrades=stock},true)
 add('streetA','Street A · road tyres · no swaps','Racing','A class, road tyres, Sport parts, no conversions.',{piMin=601,piMax=700,allowedClasses={E=false,D=false,C=false,B=false,A=true,S=false,R=false,P=false,X=false},nitrous=false,upgrades={engine='sport',engineConversion=false,drivetrainConversion='off',compound='road',width=0,weight='sport',brakes='sport'}},true)
 add('bclass','B-class road cars','Racing','B class, road/sport tyres and Sport parts.',{piMin=501,piMax=600,allowedClasses={E=false,D=false,C=false,B=true,A=false,S=false,R=false,P=false,X=false},nitrous=false,upgrades={engine='sport',compound='sport',weight='sport',brakes='sport'}},true)
 add('spec','Spec-car preparation','Spec series','Fixed setup and factory parts. Staff choose the required server model.',{tuning=false,aero=false,diff=false,nitrous=false,upgrades=stock})
 add('endurance','Endurance preparation','Endurance','Fuel, tyre wear and track-limit penalties; no pit servicing is added.',{fuel=true,tyreWear='on',trackLimits='penalty',cutPenaltyAfter=3,cutPenaltySeconds=5,nitrous=false},true,20)
 add('open','Open class','Racing','Open PI and upgrades with clean-lap track limits.',{piMin=false,piMax=false,trackLimits='invalid'})
 for _,class in ipairs({'E','D','C','B','A','S','R','P','X'}) do
  local lo,hi=P.band(class);local classes={};for _,c in ipairs({'E','D','C','B','A','S','R','P','X'}) do classes[c]=c==class end
  add('cup-'..class,class=='X' and 'X Unlimited' or class..' Cup','Class cups',class..' class · '..lo..'–'..hi..' PI · upgrades within class.',{piMin=lo,piMax=hi,allowedClasses=classes,trackLimits='invalid'})
 end
 add('reverse','Reverse grid','Fun','Top six reversed. Clean laps and six laps of racing.',{gridOrder='reverse',gridReverseTop=6,trackLimits='invalid'},false,6)
 add('rookie','Rookie cup','Racing','D-class road cars. Open to Rookie licences and above.',{piMin=301,piMax=400,minLicence='',nitrous=false,upgrades=stock,trackLimits='invalid'})
 add('gt','GT-style','Racing','A–S class, aero allowed, driver-choice ABS and TC.',{piMin=601,piMax=800,aero=true,abs='driver',tc='driver',nitrous=false,trackLimits='invalid'})
 add('muscle','Muscle · factory Barstow','Spec series','Factory Gavril Barstow, rear drive, no conversions.',{specModel='barstow',specConfig='',nitrous=false,upgrades=stock})
 items[#items].description='Factory Gavril Barstow: rear drive, no conversions. Available when that server car is listed.'
 add('sprint','Short sprint','Racing','Three laps, standing start, clean-lap track limits.',{startType='standing',trackLimits='invalid'},false,3)
 add('clean','Clean racing','Racing','Safety scoring, no nitrous, track-limit penalties and tyre wear.',{safetyRating=true,trackLimits='penalty',tyreWear='on',nitrous=false})
 for _,class in ipairs({'D','C','B','A','S','R'})do
  local lo,hi=P.band(class);local allowed={};for _,c in ipairs({'E','D','C','B','A','S','R','P','X'})do allowed[c]=c==class end
  add('build-'..class,'Build to '..class,'Build to class','Any car whose factory PI is at or below '..hi..'; upgrade into '..class..'.',{targetClass=class,piMin=lo,piMax=hi,allowedClasses=allowed,trackLimits='invalid'})
 end
 return items
end
local function sameProvided(raw,clean)
 if type(raw)~='table' then return raw==clean end
 if type(clean)~='table' then return false end
 for k,v in pairs(raw) do if not sameProvided(v,clean[k]) then return false end end;return true
end
function P.new(api)
 local disk=api.read();local broken=disk==nil and api.exists()
 if disk==nil then
  disk={schema=1,serial=0,builtinVersion=231,items=P.builtins(),sessions={}}
  for _,car in ipairs(api.cars and api.cars() or {}) do
   disk.items[#disk.items+1]={id='spec:'..car.model,name=('Spec '..car.name):sub(1,80),description=('Factory '..car.name..' · '..(car.config or 'all factory variants')):sub(1,500),category='Spec series',staffPick=false,offered=true,builtin=true,defaultLaps=5,
    patch={seriesName=('Spec '..car.name):sub(1,80),specModel=car.model,specConfig=car.config or '',tuning=false,aero=false,diff=false,nitrous=false,upgrades=copy(disk.items[1].patch.upgrades),parts={engine='stock',drivetrain='stock',suspension='stock',tyres='stock',body='stock'}}}
  end
 end
 local function validate(raw)
  if type(raw)~='table' or not text(raw.name,80) or not text(raw.description,500) or not includes(P.CATEGORIES,raw.category) or type(raw.patch)~='table' then return nil,'Choose a name, description, category and valid rules.' end
  local rules=api.sanitize(raw.patch)
  if not sameProvided(raw.patch,rules) then return nil,'Invalid or unsupported preset rule.' end
  local laps=raw.defaultLaps or 5
  if type(laps)~='number' or laps~=math.floor(laps) or laps<1 or laps>1000 then return nil,'Choose 1–1000 default laps.' end
  return {id=raw.id,name=raw.name,description=raw.description,category=raw.category,staffPick=raw.staffPick==true,offered=raw.offered==true,defaultLaps=laps,patch=copy(raw.patch),builtin=raw.builtin==true}
 end
 local function validState(s)
  if type(s)~='table' or (s.builtinVersion~=nil and(type(s.builtinVersion)~='number'or s.builtinVersion<0 or s.builtinVersion%1~=0)) or s.schema~=1 or type(s.serial)~='number' or s.serial<0 or type(s.items)~='table' or #s.items>256 then return false end
  local ids,picks={},0
  for _,r in ipairs(s.items) do
   if not validate(r) or not text(r.id,64) or not r.id:match('^[%w:_-]+$') or ids[r.id] then return false end
   ids[r.id]=true;if r.staffPick then picks=picks+1 end
  end
  if s.sessions~=nil then
   if type(s.sessions)~='table' then return false end
   local count=0;for id,r in pairs(s.sessions) do count=count+1;if type(id)~='string' or type(r)~='table' or type(r.rules)~='table' or type(r.preset)~='table' or not text(r.preset.id,64) or not text(r.preset.name,80) then return false end end
   if count>128 then return false end
   for _,r in pairs(s.sessions) do local normalized=api.sanitize(r.rules);if not sameProvided(r.rules,normalized) or not sameProvided(normalized,r.rules) then return false end end
  end
  return picks<=4
 end
 local migrate=type(disk)=='table'and disk.schema==1 and (disk.builtinVersion==nil or type(disk.builtinVersion)=='number'and disk.builtinVersion<231)
 if migrate and type(disk.sessions)=='table'then for _,r in pairs(disk.sessions)do if type(r)=='table'and type(r.rules)=='table'and r.rules.targetClass==nil then r.rules.targetClass=''end end end
 if not validState(disk) then broken=true end
 if migrate and not broken then
  local nextDisk=copy(disk);local ids={};for _,r in ipairs(nextDisk.items)do ids[r.id]=true end
  for _,r in ipairs(P.builtins())do if r.category=='Build to class'and not ids[r.id]then nextDisk.items[#nextDisk.items+1]=r end end
  nextDisk.builtinVersion=231
  if #nextDisk.items>256 or not api.write(nextDisk)then broken=true else disk=nextDisk end
 end
 local self={}
 function self.session(id) return not broken and copy((disk.sessions or {})[tostring(id)]) or nil end
 function self.sessions()
  local out={};if not broken then for id,r in pairs(disk.sessions or {}) do if not r.closed then out[id]=copy(r) end end end;return out
 end
 function self.assign(id,selection)
  if broken or not id then return false end
  local s=copy(disk);s.sessions=s.sessions or {}
  local count=0;for key,r in pairs(s.sessions) do if r.closed then s.sessions[key]=nil else count=count+1 end end
  if count>=128 then return false end
  s.sessions[tostring(id)]=copy(selection)
  if not api.write(s) then return false end;disk=s;return true
 end
 function self.close(id)
  if broken or not (disk.sessions or {})[tostring(id)] then return end
  local s=copy(disk);s.sessions[tostring(id)].closed=true
  if api.write(s) then disk=s;return true end
 end
 function self.broken() return broken end
 function self.get(id) if broken then return end;for _,r in ipairs(disk.items) do if r.id==id then return copy(r) end end end
 function self.view(staff)
  local out={items={},categories=P.CATEGORIES,error=broken and 'Preset library unavailable; restore presets.json from backup.' or nil}
  if not broken then for _,r in ipairs(disk.items) do if staff or r.offered and (not r.patch.specModel or r.patch.specModel=='' or not api.hasModel or api.hasModel(r.patch.specModel)) then out.items[#out.items+1]=copy(r) end end end;return out
 end
 function self.rules(preset) return api.sanitize(preset.patch) end
 function self.action(p,staff)
  if not staff then return false,'Rules permission required.' end
  if broken then return false,'Preset file damaged; restore its backup.' end
  local nextState=copy(disk);local index
  for i,r in ipairs(nextState.items) do if r.id==p.id then index=i end end
  if p.action=='remove' then if not index then return false,'Preset not found.' end;table.remove(nextState.items,index)
  elseif p.action=='save' or p.action=='duplicate' then
   local raw=p.action=='duplicate' and index and copy(nextState.items[index]) or p.preset
   if type(raw)~='table' then return false,'Preset not found.' end
   raw=copy(raw)
   if p.action=='duplicate' then raw.name=raw.name:sub(1,73)..' (copy)';raw.staffPick=false;raw.offered=false;index=nil end
   if not index then nextState.serial=nextState.serial+1;raw.id='custom-'..nextState.serial;raw.builtin=false else raw.id=nextState.items[index].id;raw.builtin=nextState.items[index].builtin end
   local item,why=validate(raw);if not item then return false,why end
   if index then nextState.items[index]=item else nextState.items[#nextState.items+1]=item end
  else return false,'Unknown preset action.' end
  if not validState(nextState) then return false,'Keep at most four staff picks and 256 presets.' end
  if not api.write(nextState) then return false,'Preset library could not be saved; previous version retained.' end
  disk=nextState;return true
 end
 -- Only layout, lap count, start and preset ID are accepted from a player.
 function self.open(pid,p,open)
  if broken then return false,'Preset library unavailable.' end
  for key in pairs(p) do if key~='action' and key~='preset' and key~='raceID' and key~='laps' and key~='start' then return false,'Players cannot change preset rules.' end end
  local preset=self.get(p.preset);if not preset or not preset.offered then return false,'This preset is not offered to players.' end
  local why=api.eligibility(pid,p.raceID);if why then return false,why end
  local laps=tonumber(p.laps);if not laps or laps%1~=0 or laps<1 or laps>1000 or not includes({'standing','rolling'},p.start) then return false,'Choose a layout, 1–1000 laps and a start type.' end
  local chosen=copy(preset);local rules=self.rules(chosen);rules.startType=p.start
  if rules.specModel and rules.specModel~='' and api.hasModel and not api.hasModel(rules.specModel) then return false,'This preset requires a car no longer available on the server.' end
  open({preset={id=chosen.id,name=chosen.name,category=chosen.category},rules=rules,raceID=p.raceID,laps=laps,start=p.start})
  return true
 end
 return self
end
return P
