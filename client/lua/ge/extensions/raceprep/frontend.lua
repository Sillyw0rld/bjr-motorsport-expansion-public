-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Only the standalone career package supplies this marker. Multiplayer stays default.
local F={}
-- Never cache a negative: a level/mission transition can remount the mod VFS
-- between extension loads, and a read taken in that gap must not pin the
-- whole session to the multiplayer shape. Re-probe until the marker reads
-- positive, then latch (a build cannot lose its marker mid-session).
local career
local function detect()
 if career==nil then
  local config=jsonReadFile and jsonReadFile('/lua/ge/extensions/raceprep/frontend.json')
  career=(type(config)=='table' and config.frontend=='ascension') or nil
 end
 return career==true
end
function F.isCareer() return detect() end
function F.host()
 return require(detect() and 'ge/extensions/raceprep/career/host' or 'ge/extensions/raceprep/bjr/host')
end
return F
