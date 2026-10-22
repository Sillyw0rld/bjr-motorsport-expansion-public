-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
-- client events in uncompressed pieces (2026-10-21): no packet over 400 bytes,
-- so the launcher never zlib-compresses one and BeamMP never retries its
-- unpack with a 30 MB buffer; the server joins them and fires the event
local s=io.open('server/RacePrep/RacePrep.lua'):read('*a')
local i=assert(s:find('-- Large client events',1,true));local j=assert(s:find("MP.RegisterEvent('RacePrepChunk'",1,true))
local fired={}
local env=setmetatable({MP={TriggerLocalEvent=function(ev,pid,data) fired[#fired+1]={ev=ev,pid=pid,data=data} end}},{__index=_G})
local chunk=assert(loadstring(s:sub(i,j-1)..'\nreturn RacePrepChunk'));setfenv(chunk,env)
local join=chunk()
local packets={}
TriggerServerEvent=function(ev,data) packets[#packets+1]={ev=ev,data=data};return true end
local N=require('ge/extensions/raceprep/net')
-- small payloads go as they are
N.send('RacePrepSetRules','{"a":1}')
assert(#packets==1 and packets[1].ev=='RacePrepSetRules' and packets[1].data=='{"a":1}','small payload unchanged')
-- a large, very compressible payload (a parts list) goes in pieces
local parts={} for k=1,400 do parts[#parts+1]=string.format('"/main/body/slot_%03d":"rp_part_%03d"',k,k) end
local big='{"parts":{'..table.concat(parts,',')..'}}'
packets={}
assert(N.send('RacePrepComputedRating',big)==true)
assert(#packets==math.ceil(#big/N.CHUNK),'one packet per piece')
for _,p in ipairs(packets) do
 assert(p.ev=='RacePrepChunk')
 assert(#('E:'..p.ev..':'..p.data)<400,'every packet stays under the launcher compression limit')
 join(3,p.data)
end
assert(#fired==1 and fired[1].ev=='RacePrepComputedRating' and fired[1].pid==3 and fired[1].data==big,'server joins the pieces and fires the original event')
-- out of order / interleaved / foreign events are dropped, never fired half
fired={}
join(3,packets[2].data);join(3,packets[1].data)
assert(#fired==0,'a piece out of order drops the message')
join(4,'1|1|1|onPlayerJoin|x');join(4,'1|1|1|RacePrepChunk|x')
assert(#fired==0,'only RacePrep events, never the chunk event itself')
join(5,'1|1|5000|RacePrepX|x');assert(#fired==0,'piece count limit')
print('PASS: net: large client events in uncompressed pieces under 400 bytes, joined on the server')
