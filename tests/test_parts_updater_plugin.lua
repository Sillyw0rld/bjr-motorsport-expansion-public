-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- PartsUpdater.lua: background run at startup, then reloadmods typed in tmux or the admin told
local U=dofile('server/RacePrep/PartsUpdater.lua')
local function make(env,os_)
  local o={path='Resources/Server/RacePrep',osName=os_ or 'Linux',t=0,cmds={},logs={},warns={},files={},env=env or {}}
  o.exists=function(p) return p:find('parts_updater.py',1,true)~=nil end
  o.read=function(p) return o.files[p] end
  o.remove=function(p) o.removed=(o.removed or 0)+1;o.files[p]=nil end
  o.execute=function(c) o.cmds[#o.cmds+1]=c end
  o.getenv=function(k) return o.env[k] end
  o.now=function() return o.t end
  o.log=function(m) o.logs[#o.logs+1]=m end
  o.logWarn=function(m) o.warns[#o.warns+1]=m end
  return o
end
local R='Resources/Server/RacePrep/updater/tools/last-run.json'
-- tmux (sandboxed service): runs in the background, then types reloadmods itself
local o=make({TMUX='/run/beammp/tmux.sock,123,0',TMUX_PANE='%0'})
assert(U.start(o) and o.cmds[1]:find('python3 %-I') and o.cmds[1]:find('&$'),'background python3 run on Linux')
assert(U.poll()==false,'waits for the result')
o.files[R]={status='updated',newCars={'car_a','car_b'},seconds=60,finishedAt=0}
assert(U.poll()==true and U.delivered=='auto')
assert(o.cmds[2]=='tmux -S "/run/beammp/tmux.sock" send-keys -t "%0" reloadmods Enter',o.cmds[2])
-- plain console: tells the admin
o=make();U.start(o);o.files[R]={status='updated',newCars={'car_a'},finishedAt=0}
assert(U.poll() and U.delivered=='manual' and #o.cmds==1 and o.warns[1]:find('reloadmods'))
-- Windows: start /B python, never tmux
o=make({TMUX='x,1,0',TMUX_PANE='%0'},'Windows');U.start(o)
assert(o.cmds[1]:find('^start "" /B python %-I'));o.files[R]={status='updated',newCars={'c'},finishedAt=0};U.poll()
assert(#o.cmds==1 and U.delivered=='manual','no tmux on Windows')
-- up to date / failure / no result
o=make();U.start(o);o.files[R]={status='up-to-date',newCars={},finishedAt=0};assert(U.poll() and #o.cmds==1 and o.logs[2]:find('every car'))
o=make();U.start(o);o.files[R]={status='failed',error='boom',finishedAt=0};assert(U.poll() and o.warns[1]:find('boom') and o.warns[1]:find('previous parts'))
o=make();U.start(o);o.t=601;assert(U.poll() and o.warns[1]:find('10 minutes'))
-- not bundled: nothing runs
o=make();o.exists=function() return false end;assert(U.start(o)==false and #o.cmds==0)
-- the previous start's result is ignored and never deleted (BeamMP file monitor)
o=make();o.t=1000;o.files[R]={status='up-to-date',newCars={},finishedAt=500};U.start(o)
assert(not o.removed,'result file not deleted');assert(U.poll()==false,'stale result ignored')
o.files[R]={status='up-to-date',newCars={},finishedAt=1000};assert(U.poll()==true)
-- Public release: launcher owns generation, never spawn Python or reload live assets.
o=make();o.exists=function(p) return p:find('preflight-required.json',1,true)~=nil end
assert(U.start(o)==false and #o.cmds==0 and o.logs[1]:find('preflight'))
print('PASS: parts updater runs in the background at startup; reloadmods via tmux, else the admin is told; failures keep the server running')
