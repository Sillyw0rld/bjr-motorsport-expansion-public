-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Detect the mounted BJR client before loading the shared Race Prep runtime.
-- Load order among downloaded ZIPs is not guaranteed; legacy init also probes.
if FS:fileExists('/lua/ge/extensions/beamjoy/main.lua') then
 local _bjr=load('raceprepBJR')
 setExtensionUnloadMode('raceprepBJR','manual')
end
local _ = load('bjiRacePrep')
setExtensionUnloadMode('bjiRacePrep', 'manual')
local _ratings = load('raceprepRatings')
setExtensionUnloadMode('raceprepRatings', 'manual')
-- track temperature (was the separate road_temperature mod): feeds KTS too
local _road = load('roadTemperature')
setExtensionUnloadMode('roadTemperature', 'manual')
