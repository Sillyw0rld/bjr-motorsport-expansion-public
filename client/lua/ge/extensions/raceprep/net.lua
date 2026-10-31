-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Client -> server events without BeamMP's zlib warning.
-- The launcher compresses every packet over 400 bytes; the server unpacks it
-- into a buffer 5x the compressed size and, when that is too small (JSON parts
-- lists, results), retries with a 30 MB buffer ("zlib uncompress() failed,
-- trying with a larger buffer size"), which caused lag spikes. Payloads over
-- CHUNK bytes go as uncompressed pieces under 400 bytes; the server's
-- RacePrepChunk joins them and fires the original event (2026-10-21).
local N={CHUNK=300}
local serial=0
local Frontend=require('ge/extensions/raceprep/frontend')
function N.available() return Frontend.isCareer() or type(rawget(_G,'TriggerServerEvent'))=='function' end
function N.on(event,handler,source)
 if Frontend.isCareer() then return require('ge/extensions/raceprep/career/bus').on(event,handler,source) end
 local register=rawget(_G,'AddEventHandler')
 if type(register)=='function' then register(event,handler,source);return true end
 return false
end
function N.send(event,payload)
 if Frontend.isCareer() then return require('ge/extensions/raceprep/career/bus').send(event,payload) end
 local trigger=rawget(_G,'TriggerServerEvent')
 if type(trigger)~='function' then return false end
 payload=tostring(payload or '')
 if #payload<=N.CHUNK then return trigger(event,payload) end
 serial=serial%99999+1
 local n=math.ceil(#payload/N.CHUNK)
 for i=1,n do
  local result=trigger('RacePrepChunk',serial..'|'..i..'|'..n..'|'..event..'|'..payload:sub((i-1)*N.CHUNK+1,i*N.CHUNK))
  if result==false then return false end
 end
 return true
end
return N
