-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local input=dofile(assert(arg[1]));local B=dofile('server/RacePrep/ProgressionBackfill.lua')
local Skill=dofile('server/RacePrep/Skill.lua');local Rating=dofile('server/RacePrep/DriverRating.lua')
input.score=function(e) return Rating.score(e and e.rating or Skill.START) end
B.run(input.state,input,function(key) return Skill.hash(input.skills.salt,key) end,{licences={}},function(id,run) return (input.moderation.blocked or {})[id]==true or (run and (input.moderation.removed or {})[run]==true) end)
local function quote(s)
 return '"'..s:gsub('\\','\\\\'):gsub('"','\\"'):gsub('[%z\1-\31]',function(c) return string.format('\\u%04x',c:byte()) end)..'"'
end
local function encode(v)
 if type(v)=='string' then return quote(v) elseif type(v)=='boolean' or type(v)=='number' then return tostring(v) elseif v==nil then return 'null' end
 local out={}
 if #v>0 then for _,x in ipairs(v) do out[#out+1]=encode(x) end;return '['..table.concat(out,',')..']' end
 local keys={};for k in pairs(v) do keys[#keys+1]=k end;table.sort(keys)
 for _,k in ipairs(keys) do out[#out+1]=quote(k)..':'..encode(v[k]) end;return '{'..table.concat(out,',')..'}'
end
print(encode(input.state))
