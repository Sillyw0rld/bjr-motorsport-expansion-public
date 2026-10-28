-- Small deterministic JSON encoder for browser fixtures, never production data.
local function quote(s)
 return '"'..s:gsub('[%z\1-\31\\"]',function(c) if c=='"' or c=='\\' then return '\\'..c end;return string.format('\\u%04x',c:byte()) end)..'"'
end
local function encode(v)
 if type(v)=='string' then return quote(v) elseif type(v)=='boolean' then return tostring(v) elseif type(v)=='number' then assert(v==v and math.abs(v)<math.huge);return tostring(v) elseif v==nil then return 'null' end
 assert(type(v)=='table');local array,count=true,0
 for k in pairs(v) do count=count+1;if type(k)~='number' then array=false end end
 local out={};if array and #v==count and count>0 then for _,x in ipairs(v)do out[#out+1]=encode(x)end;return '['..table.concat(out,',')..']' end
 local keys={};for k in pairs(v)do keys[#keys+1]=k end;table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 for _,k in ipairs(keys)do out[#out+1]=quote(tostring(k))..':'..encode(v[k])end;return '{'..table.concat(out,',')..'}'
end
return encode
