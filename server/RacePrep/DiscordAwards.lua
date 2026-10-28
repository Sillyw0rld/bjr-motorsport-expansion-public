-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Opt-in, nonblocking curl delivery. Never calls BJR internals or exposes URLs
-- to clients. Ambiguous/interrupted sends are held, never automatically resent.
local D={}
local function prefix(text,limit)
 if #text<=limit then return text end
 local nextByte=text:byte(limit+1)
 if nextByte and nextByte>=128 and nextByte<=191 then
  while limit>0 and text:byte(limit)>=128 and text:byte(limit)<=191 do limit=limit-1 end
  limit=limit-1
 end
 return text:sub(1,math.max(0,limit))
end
local function clean(v)
 return prefix(tostring(v or ''):gsub('%c',' '):gsub('[`*_~|<>]',''):gsub('@','@\226\128\139'),180)
end
function D.new(api)
 local loaded=api.read(api.path..'/awards-discord-queue.json')
 local broken=loaded==nil and api.exists(api.path..'/awards-discord-queue.json')
 local store=loaded or {schema=1,items={}}
 if type(store)~='table' or store.schema~=1 or type(store.items)~='table' then broken=true end
 if not broken then for _,job in ipairs(store.items) do if type(job)~='table' or type(job.id)~='string' or type(job.body)~='table' or type(job.token)~='string' or not job.token:match('^%x+$') or #job.token>64 or not ({queued=true,running=true,sent=true,failed=true})[job.status] then broken=true;break end end end
 if broken then api.log('Discord awards queue is damaged; restore its backup before sending.') end
 if not broken then for _,job in ipairs(store.items) do if job.status=='running' then api.log('Interrupted Discord award post held for manual review; see awards-discord-queue.json.');break end end end
 local self={};local active,warned
 local function save(nextStore)
  if not api.write(api.path..'/awards-discord-queue.json',nextStore) then return false end
  store=nextStore;return true
 end
 local function config()
  local c=api.read(api.path..'/awards-discord.json')
  if type(c)~='table' or c.enabled~=true then return end
  if type(c.webhook)~='string' or not c.webhook:match('^https://discord%.com/api/webhooks/%d+/[%w_%-]+$') then
   if not warned then api.log('Discord awards enabled but webhook is invalid; check awards-discord.json.');warned=true end
   return
  end
  warned=nil;return c
 end
 local windows=package.config:sub(1,1)=='\\'
 local function quote(p)
  -- cmd.exe expands these even inside quotes. Refuse unsafe install paths.
  if windows then if p:find('[%%!"\r\n]') then return end;return '"'..p..'"' end
  return "'"..p:gsub("'","'\\''").."'"
 end
 function self.enqueue(res)
  if broken or not config() or not res.runID or #(res.awards or {})==0 then return end
  local id=tostring(res.runID)
  for _,job in ipairs(store.items) do if job.id==id then return end end
  local fields={}
  for _,a in ipairs(res.awards) do
   local names={};for i,w in ipairs(a.winners or {}) do if i<=12 then names[#names+1]=clean(w.name)..(a.id=='fastest' and string.format(' · %.3f s',w.value/1000) or a.id~='clean' and ' · +'..tostring(w.value)..' places' or '') end end
   fields[#fields+1]={name=clean(a.label),value=prefix(table.concat(names,'\n'),1000),inline=false}
  end
  local nextStore=api.copy(store)
  -- Keep a bounded dedup/history tail, but never discard a pending post.
  if #nextStore.items>=200 then
   for i,j in ipairs(nextStore.items) do if j.status=='sent' or j.status=='failed' then table.remove(nextStore.items,i);break end end
  end
  if #nextStore.items>=200 then api.log('Discord award queue full; result retained in race history.');return end
  nextStore.items[#nextStore.items+1]={id=id,token=api.token(id),status='queued',body={allowed_mentions={parse={}},embeds={{title=((res.kind=='rivals-record' and 'Rivals record · ' or 'Race awards · ')..clean(res.raceName)):sub(1,250),fields=fields,color=16747050}}}}
  if not save(nextStore) then api.log('Could not queue Discord awards; result retained in history.') end
 end
 function self.record(p)
  return self.enqueue({kind='rivals-record',runID='rivals-record:'..p.runID,raceName=p.raceName,
   awards={{id='fastest',label='New record · '..tostring(p.class),winners={{name=p.name,value=p.time}}}}})
 end
 function self.tick()
  if broken then return end
  if active then
   local f=io.open(active.status,'r');local code=f and f:read('*a');if f then f:close() end
   local http=type(code)=='string' and code:match('^%d%d%d$') and tonumber(code)
   if not http and api.now()-active.at<25 then return end
   local nextStore=api.copy(store);local job
   for _,entry in ipairs(nextStore.items) do if entry.id==active.id then job=entry;break end end
   if not job then active=nil;return end
   job.status=http and http>=200 and http<300 and 'sent' or 'failed';job.http=http;job.finished=api.now()
   if not save(nextStore) then return end
   for _,p in ipairs({active.status,active.body,active.config,active.response}) do os.remove(p) end
   if job.status~='sent' then api.log('Discord awards failed/uncertain; held without retry. See awards-discord-queue.json.') end
   active=nil;return
  end
  local c=config();if not c then return end
  for i,j in ipairs(store.items) do if j.status=='queued' then
   local prefix=api.path..'/awards-discord-job-'..j.token
   local status,body,cfg,response=prefix..'.status',prefix..'.json',prefix..'.cfg',prefix..'.response'
   local qstatus,qbody,qcfg,qresponse=quote(status),quote(body),quote(cfg),quote(response)
   if not qstatus or not qbody or not qcfg or not qresponse then api.log('Discord awards: unsupported shell characters in installation path.');return end
   local b=io.open(body,'w');if not b then return end;local wrote=b:write(api.encode(j.body));local closed=b:close();if not wrote or not closed then return end
   local f=io.open(cfg,'w');if not f then return end
   wrote=f:write('url = "'..c.webhook..'"\nheader = "Content-Type: application/json"\n');closed=f:close();if not wrote or not closed then return end
   os.remove(status)
   local nextStore=api.copy(store);nextStore.items[i].status='running'
   if not save(nextStore) then return end
   local cmd='curl --silent --show-error --max-time 15 --config '..qcfg..' --data-binary @'..qbody..' --output '..qresponse..' --write-out "%{http_code}" > '..qstatus..' 2> '..(windows and 'NUL' or '/dev/null')
   if windows then cmd='start "" /B cmd /C "'..cmd..'"' else cmd='('..cmd..') &' end
   active={id=j.id,status=status,body=body,config=cfg,response=response,at=api.now()}
   api.execute(cmd);return
  end end
 end
 return self
end
return D
