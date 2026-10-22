-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local reads,lists=0,0
local files,data={},{}
for i=1,25 do
 local path=string.format('2026-10-18_%06d_Race.json',i)
 files[#files+1]=path
 data['history/'..path]={key='run-'..i,runID='run-'..i,level='imola',raceID=1,raceName='Imola',laps=3,
  rows={{name='Driver '..i,car='Car '..i,pi=500+i,class='B',best={time=60000+i*100},status='FIN',total=200000,position=1}}}
end
files[#files+1]='2026-10-18_999999_qualifying.json'
files[#files+1]='2026-10-18_888888_bad.json';data['history/2026-10-18_888888_bad.json']='corrupt'
files[#files+1]='2026-10-18_777777_other.json';data['history/2026-10-18_777777_other.json']={key='other',level='other',rows={}}
files[#files+1]='2026-10-18_666666_invalid.json';data['history/2026-10-18_666666_invalid.json']={key='invalid',level='imola',raceID=1,rows={{best={time=5000,invalid=true}}}}
local H=dofile('server/RacePrep/ResultHistory.lua').new{path='history',list=function() lists=lists+1;return files end,
 read=function(path) reads=reads+1;return data[path] end}
local v=H.view('/levels/imola/info.json');assert(#v.items==20 and v.limit==20)
assert(v.records['1'].time==60100 and v.records['1'].pi==501 and v.records['1'].car=='Car 1','best valid lap includes its original car/PI outside the latest 20')
assert(v.items[2].key=='run-25','newest first, with other maps/qualifying/corrupt data excluded')
local before=reads;assert(H.view('imola')==v and reads==before and lists==1,'cache prevents repeat scans')
H.invalidate();H.view('imola');assert(reads>before and lists==2)
assert(#H.view('other').items==1,'current-map isolation')
assert(data['history/2026-10-18_000001_Race.json'].rows[1].pi==501,'view does not rewrite records')
print('PASS: bounded read-only history, newest first, map isolation, valid record attribution and scan cache')
