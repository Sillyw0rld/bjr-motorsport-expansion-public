-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
package.path='client/lua/?.lua;'..package.path
local h={ready=function() return true end,playerID=function() return 1 end,vehicle=function() end,canEdit=function() return true end,session=function() return beamjoy_raceRunner.session end}
package.loaded['ge/extensions/raceprep/bjr/host']=h
local director={lights={phase='red',count=5},falseStart=false,data={runID='run',falseStarts={['1']=0}},yellow=function() return 'YELLOW' end}
local session={remaining=function() return 12345 end,currentLapTime=function() return 9000 end,currentLapCuts=function() return 0 end,active=function() return true end}
package.loaded['ge/extensions/raceprep/director']=director;package.loaded['ge/extensions/raceprep/session']=session
beamjoy_raceRunner={session={id='run',state='RACE',raceId=1,settings={},participants={{playerID=1,playerName='Ana'},{playerID=2,playerName='Ben'}}},raceStartTimeMs=0}
raceprepRatings={getPlayer=function(pid) return pid==1 and {class='A',pi=739} or nil end}
beamjoy_races={data={{id=1,name='Track',gates={{},{}}}}};getCurrentLevelIdentifier=function() return 'test' end
local d=dofile('client/lua/ge/extensions/raceprep/bjr/driving.lua')
bjiRacePrep={rolling={phase='formation',pace=80,warning='Do not pass before green'}}
local packet=d.packet(1000,1)
assert(packet.signals.noPassing=='Do not pass before green','spatial formation warning reaches independent HUD')
assert(packet.signals.lights.count==5 and packet.signals.yellow=='YELLOW' and packet.signals.falseStart,'signals and a zero-second false-start penalty')
-- race timing is BJR's own (BJRaceHud); the packet adds class / PI per BJR playerName
assert(packet.race.state=='RACE' and packet.race.raceName=='Track' and packet.race.badges.Ana.pi==739 and packet.race.badges.Ben==nil)
assert(packet.timing==nil,'no BJR:ME race timing any more')
-- track limits pill for a few seconds after my cut, with the race's penalty rule
bjiRacePrep.getRules=function() return {trackLimits='penalty',cutPenaltyAfter=3,cutPenaltySeconds=5} end
session.raceCut={raceID=1,count=2,at=1}
packet=d.packet(1010,2);local lim=packet.signals.limits
assert(lim and lim.cuts==2 and lim.mode=='penalty' and lim.after==3 and lim.seconds==5,'limits pill')
packet=d.packet(1020,7);assert(packet.signals.limits==nil,'pill hides after a few seconds')
beamjoy_raceRunner.session.id='run2';packet=d.packet(1030,7.1);assert(session.raceCut==nil,'a new race run starts the cut count again')
beamjoy_raceRunner.session.id='run'
session.currentAnnouncement=function() return {text='Qualifying has started',stage='qualifying'} end
packet=d.packet(1040,7.2);assert(packet.announcement.stage=='qualifying');session.currentAnnouncement=nil
beamjoy_raceRunner.session.state='FINISHED';packet=d.packet(1100,1.1);assert(not next(packet.signals),'race end clears signals')
beamjoy_raceRunner.session=nil;session.data={id='q',state='running',track={level='test'},rows={}}
packet=d.packet(1200,1.2);assert(packet.practice and packet.practice.currentLap==9000,'free-roam overlay producer independent of menu')
session.status=function() return {timing=false,message='Return to free roam'} end
beamjoy_raceRunner.session={id='other',state='RACE',raceId=1,participants={}}
packet=d.packet(1300,1.3);assert(packet.practice.blocked and packet.practice.reason=='Return to free roam','session diagnostic survives another native activity')
session.status=function() error('bad status') end
packet=d.packet(1400,1.4);assert(packet.signals.yellow=='YELLOW' and packet.practice.blocked,'broken session diagnostics cannot suppress race flags')
beamjoy_raceRunner.session=nil
-- Exercise the real entry point with its setup window closed.
package.loaded['ge/extensions/raceprep/upgrades']={};package.loaded['ge/extensions/raceprep/tuningPolicy']={}
local count=0
package.loaded['ge/extensions/raceprep/bjr/driving']={packet=function() count=count+1;return {active=true,signals={yellow='YELLOW'}} end,reset=function() end}
FS={fileExists=function() return false end};AddEventHandler=function() end;GetCurrentTimeMillis=function() return 1000 end
local received={};guihooks={trigger=function(event,p) received[event]=p end}
local m=dofile('client/lua/ge/extensions/raceprepBJR.lua');m.snapshot=function() return {} end
m.dispatch{action='refresh'};assert(not m.visible)
for _=1,60 do m.onUpdate(1/60) end
assert(count>=15 and received.RacePrepBJRDriving.signals.yellow=='YELLOW','closed window still pushes driving signals frequently')
-- F6: when no race, session or signal is active, RacePrepBJRDriving is sent
-- once to clear overlays and then skipped until an overlay becomes active
local triggers=0
guihooks={trigger=function(event,p) received[event]=p;if event=='RacePrepBJRDriving' then triggers=triggers+1 end end}
package.loaded['ge/extensions/raceprep/bjr/driving'].packet=function() count=count+1;return {active=true,signals={}} end
for _=1,60 do m.onUpdate(1/60) end
assert(triggers==1,'idle freeroam skips repeated RacePrepBJRDriving digests, got '..triggers)
m.onExtensionUnloaded();assert(received.RacePrepBJRDriving.active==false,'unload clears the overlay')
print('PASS: signals, BJR race state with class/PI badges, track-limits pill, announcement, race end/free roam, closed-window push and unload')
