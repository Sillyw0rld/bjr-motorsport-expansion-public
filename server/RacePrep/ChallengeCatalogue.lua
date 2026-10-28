-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Virtual empty boards, bounded pages and frozen daily/weekly publications.
local path=debug.getinfo(1).source:gsub('^@',''):gsub('\\','/'):match('^(.*)/')
local C=dofile(path..'/Challenges.lua');local R=dofile(path..'/Rivals.lua');local Rating=dofile(path..'/RatingStore.lua')
local B={}
function B.rulesKey(hash,rules,preset,kind,options)
 local suffix=''
 if preset and preset.id then suffix=suffix..':preset:'..preset.id end
 if kind and kind~='bestLap'then suffix=suffix..':challenge:'..kind..':'..R.canonical(options or {})end
 return hash('rules',R.canonical(rules)..suffix)
end
function B.key(c,class)
 return R.key(c,class)
end
function B.new(api)
 local state=api.read();local broken=state==nil and api.exists()
 if state==nil then state={schema=1,picks={}}end
 if type(state)~='table' or state.schema~=1 or type(state.picks)~='table'then broken=true end
 if not broken then for id,p in pairs(state.picks)do
  if type(id)~='string' or type(p)~='table' or type(p.id)~='string' or type(p.board)~='table' or type(p.board.id)~='string' or type(p.board.rules)~='table' or type(p.starts)~='number' or type(p.ends)~='number' or (p.xp~=100 and p.xp~=250) or (p.target~=nil and (type(p.target)~='table' or type(p.target.time)~='number' or not p.target.verified))then broken=true;break end
 end end
 local cache={};local self={};local function settings()return C.settings(api.settings())end
 local function available(g)
  local race=api.race(g.raceID);if not race or api.layout(race)~=g.layout then return false end
  if not settings().types[g.type or 'bestLap']then return false end
  local rules,preset=api.rules(g.raceID),g.preset
  if preset then local current=api.preset(preset.id);if not current or not current.offered then return false end;rules=api.presetRules(current)end
  if g.type=='tyreSaver' and rules.tyreWear~='on'then return false end
  local options=C.options(g.type or 'bestLap',race,settings());if not options then return false end
  return B.rulesKey(api.hash,rules,preset,g.type,options)==g.rulesKey
 end
 self.available=available
 function self.board(race,preset,class,kind)
  if not C.TYPES[kind] or not settings().types[kind] or Rating.classOf(select(1,api.band(class)) or -1)~=class then return end
  local rules=preset and api.presetRules(preset)or api.rules(race.id)
  if rules.allowedClasses and not rules.allowedClasses[class]then return end
  local lo,hi=api.band(class);if rules.piMin and hi<rules.piMin or rules.piMax and lo>rules.piMax then return end
  if kind=='tyreSaver' and rules.tyreWear~='on'then return end
  local options=C.options(kind,race,settings());if not options then return end
  local p=preset and{id=preset.id,name=preset.name,category=preset.category}or nil
  local g={raceID=race.id,raceName=race.name,layout=api.layout(race),rulesKey=B.rulesKey(api.hash,rules,p,kind,options),rules=rules,preset=p,class=class,type=kind,options=options,bests={},level=api.level()}
  g.id=B.key(g,class);cache[g.id]=g
  local stored=api.groups()[g.id];if stored then g.bests=stored.bests end
  return g
 end
 function self.get(id)
  local g=cache[id] or api.groups()[id]
  if g and available(g)then return g end
 end
 function self.currentRules(g)
  if g.preset then local p=api.preset(g.preset.id);return p and api.presetRules(p)end
  return api.rules(g.raceID)
 end
 local function boundCache()
  local size=0;for _ in pairs(cache)do size=size+1 end;if size>4096 then cache={}end
 end
 function self.page(q,driver)
  q=type(q)=='table'and q or {};boundCache()
  local class=type(q.class)=='string'and q.class or 'B';if not api.band(class)then class='B'end
  local page=math.max(1,math.min(1000,math.floor(tonumber(q.page)or 1)));local rows={};local count=0
  local preset=q.preset and q.preset~=''and api.preset(q.preset)or nil
  if q.preset and q.preset~=''and(not preset or not preset.offered)then return{items={},error='This preset is unavailable.'}end
  for _,race in ipairs(api.races())do
   for _,kind in ipairs(C.ORDER)do if not q.type or q.type==''or q.type==kind then
    local g=self.board(race,preset,class,kind)
    if g then count=count+1;if count>(page-1)*50 and #rows<50 then
     local view=R.view({[g.id]=g},driver,api.blocked)[1]
     view.type=kind;view.typeName=C.TYPES[kind].name;view.options=g.options;view.preset=g.preset;view.empty=#view.rows==0
     view.ghost=C.TYPES[kind].ghost;view.rules=g.rules;view.thresholds={}
     local leader=view.rows[1]
     if leader then for i,ratio in ipairs({1.02,1.05,1.10})do
      local value=C.value(kind,leader.time*ratio)
      if kind=='cleanStreak' or kind=='tyreSaver'then value=math.ceil(value)end
      if kind=='consistency'then value=math.min(1000,value)end
      view.thresholds[#view.thresholds+1]={name=({'Gold','Silver','Bronze'})[i],time=kind=='bestLap'and value or nil,metric=kind~='bestLap'and{type=kind,value=value,unit=C.TYPES[kind].unit}or nil}
     end end
     rows[#rows+1]=view
    end end
   end end
  end
  return{items=rows,page=page,pages=math.max(1,math.ceil(count/50)),total=count,class=class,preset=q.preset or '',types=C.TYPES}
 end
 local function ranked(g)
  local rows={};for _,r in pairs(g.bests or {})do if r.verified and not api.blocked(r.driver,r.runID)then rows[#rows+1]=r end end
  table.sort(rows,function(a,b)return a.time<b.time end);return rows
 end
 function self.rotations()
  if broken then return{},'Challenge publications are damaged; restore challenges.json.'end
  local now=api.now();local day=math.floor(now/86400);local week=math.floor((now+259200)/604800);local map=api.level();if not map then return{}end
  local cfg=settings();local out={};local nextState=api.copy(state);local changed=false
  local types={};for _,kind in ipairs(C.ORDER)do if cfg.types[kind]then types[#types+1]=kind end end
  if #types==0 then return{}end
  local used={}
  if cfg.weekly then for slot=2,3 do local p=state.picks['weekly:'..week..':'..tostring(map)..':'..slot];if p then used[p.board.type or 'bestLap']=true end end end
  for slot=1,3 do
   local daily=slot==1;local enabled=daily and cfg.daily or not daily and cfg.weekly
   local period=daily and day or week;local id=(daily and 'daily:' or 'weekly:')..period..':'..tostring(map)..':'..slot
   local pick=state.picks[id]
   if pick then used[pick.board.type or 'bestLap']=true end
   if enabled then
    if not pick then
     local selected
     for ki=1,#types do
      local kind=types[(period+slot+ki-2)%#types+1]
      if not used[kind]then
       local layouts=api.races();local presets=api.presets();local classes=api.classes()
       for n=1,#layouts do
        local race=layouts[(period+slot+n-2)%#layouts+1]
        for j=1,#presets do
         local preset=presets[(period+slot+j-2)%#presets+1]
         for k=1,#classes do
          local class=classes[(period+slot+k-2)%#classes+1]
          selected=self.board(race,preset,class,kind);if selected then break end
         end
         if selected then break end
        end
        if selected then break end
       end
      end
      if selected then break end
     end
     if selected then
      local rows=ranked(selected);local target=rows[math.ceil(#rows/2)]
      pick={id=id,kind=daily and 'daily'or'weekly',xp=daily and 100 or 250,starts=daily and day*86400 or week*604800-259200,ends=daily and(day+1)*86400 or(week+1)*604800-259200,published=now,level=map,board=api.copy(selected),target=target and api.copy(target)}
      pick.board.bests={};nextState.picks[id]=pick;changed=true
     end
    end
    if pick then used[pick.board.type or 'bestLap']=true
     local p=api.copy(pick);p.available=available(pick.board)and(not pick.target or not api.blocked(pick.target.driver,pick.target.runID))
     p.message=p.available and(p.target and 'Beat the published target'or'No times yet: set your first verified score')or'Published layout, rules, type or target is unavailable.'
     out[#out+1]=p;cache[p.board.id]=p.board;local g=api.groups()[p.board.id];if g then cache[p.board.id].bests=g.bests end
    end
   end
  end
  if changed then
   for id,p in pairs(nextState.picks)do if p.ends<now-8*604800 then nextState.picks[id]=nil end end
   if not api.write(nextState)then return{},'Could not save challenge publications; previous data retained.'end;state=nextState
  end
  return out
 end
 function self.publicRotations()
  local picks,why=self.rotations();local out={}
  for _,p in ipairs(picks)do out[#out+1]={id=p.id,kind=p.kind,xp=p.xp,starts=p.starts,ends=p.ends,available=p.available,message=p.message,board={id=p.board.id,raceName=p.board.raceName,raceID=p.board.raceID,class=p.board.class,type=p.board.type,typeName=C.TYPES[p.board.type or'bestLap'].name,preset=p.board.preset},target=p.target and{time=p.target.time,metric=p.target.metric,name=p.target.name}}end
  return out,why
 end
 function self.rotation(id)for _,p in ipairs(self.rotations())do if p.id==id and p.available then return p end end end
 return self
end
return B
