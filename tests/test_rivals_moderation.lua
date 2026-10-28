-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
local M=dofile('server/RacePrep/RivalsModeration.lua')
local P=dofile('server/RacePrep/Persistence.lua')
local now=100;local saved,logs,changed={},0,0;local fail=false
local api={now=function() return now end,read=function() end,exists=function() return false end,copy=P.copy,
 allowed=function(pid) return pid==1 end,actor=function() return 'staff' end,known=function(d,r,a) return d=='driver' and (a~='remove' or r=='run') end,
 write=function(v) if fail then return false end;saved=v;return true end,log=function() logs=logs+1 end,changed=function() changed=changed+1 end}
local m=M.new(api)
assert(not m.handle(2,{action='block',driver='driver'}),'staff permission enforced')
assert(m.handle(1,{action='remove',driver='driver',runID='run'}));assert(m.blocked('driver','run') and not m.blocked('driver','other'))
now=103;assert(m.handle(1,{action='block',driver='driver'}));assert(m.blocked('driver','other') and #m.list()==1)
now=106;fail=true;assert(not m.handle(1,{action='unblock',driver='driver'}));assert(m.blocked('driver'))
now=109;fail=false;assert(m.handle(1,{action='unblock',driver='driver'}));assert(not m.blocked('driver') and m.blocked('driver','run'))
assert(#saved.audit==3 and logs==3 and changed==3,'successful moderation is persisted and audited')
api.read=function() return 'broken' end;api.exists=function() return true end
local corrupt=M.new(api);assert(corrupt.blocked('anyone') and not corrupt.handle(1,{action='block',driver='driver'}),'damaged moderation storage fails closed')
print('PASS: permission-gated, persistent and audited moderation; unblock, time removal, failed writes and corrupt state')
