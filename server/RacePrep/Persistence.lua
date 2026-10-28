-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Checked replacement; preserve the previous file if any write/rename fails.
local P={}
function P.write(path,value)
 local encoded=Util.JsonPrettify(Util.JsonEncode(value))
 local f=io.open(path..'.tmp','w');if not f then return false end
 local wrote=f:write(encoded);local closed=f:close()
 if not wrote or not closed then os.remove(path..'.tmp');return false end
 if os.rename(path..'.tmp',path) then return true end
 -- Windows refuses replacement of an existing target. Move the old file
 -- aside first and restore it if publication fails; never delete it first.
 local old=io.open(path,'r');if not old then os.remove(path..'.tmp');return false end;old:close()
 if not os.rename(path,path..'.bak') then os.remove(path..'.tmp');return false end
 if os.rename(path..'.tmp',path) then os.remove(path..'.bak');return true end
 os.rename(path..'.bak',path);os.remove(path..'.tmp');return false
end
function P.copy(value)
 if type(value)~='table' then return value end
 local out={};for k,v in pairs(value) do out[k]=P.copy(v) end;return out
end
return P
