-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Renders the real RacePrep / RaceResults window code with mocked imgui and
-- BeamJoy (harness modelled on an earlier ready-UI integration test).
-- luajit tests/test_ui.lua   (from the repo root)
local root = 'client/lua/'
package.path = root .. '?.lua;' .. package.path
table.includes = function(t, v) for _, x in pairs(t or {}) do if x == v then return true end end return false end
math.clamp = function(n, a, b) return math.max(a, math.min(b, n)) end
string.var = function(s) return s end
ImVec2 = function(x, y) return { x = x, y = y } end
local style = { WINDOW_FLAGS = { NO_COLLAPSE = 1, NO_SCROLL_WITH_MOUSE = 2 },
    TEXT_COLORS = { HIGHLIGHT = 1, ERROR = 2, DISABLED = 3, SUCCESS = 4, DEFAULT = 5 },
    BTN_PRESETS = { SUCCESS = 1, INFO = 2, WARNING = 3 } }
BJI = { Utils = { Style = style, UI = { PrettyDelay = tostring } } }
local race = { state = 1, STATES = { GRID = 1 }, raceID = 1, raceName = 'Test Race', settings = { laps = 1 },
    grid = { timeout = 120000, participants = { 1 }, ready = {}, startPositions = { {} }, readyTime = 0 },
    isParticipant = function() return true end, isReady = function() return false end }
BJI_Scenario = { TYPES = { RACE_MULTI = 1 }, get = function() return race end, canReplaceVehicle = function() return true end }
local car = { getID = function() return 1 end }
BJI_Veh = { getCurrentVehicleOwn = function() return car end, isCurrentVehicleOwn = function() return true end,
    getCurrentModel = function() return 'test' end, getModelLabel = function() return 'Test Car' end }
BJI_Context = { User = { playerID = 1 }, BJC = { Race = { GridTimeout = 120 } } }
local canEdit = false
BJI_Perm = { canSpawnVehicle = function() return true end, hasPermission = function() return canEdit end, PERMISSIONS = { SET_CONFIG = 1 } }
BJI_Tournament = { canJoinActivity = function() return true end }
extensions = { core_vehicle_manager = { getVehicleData = function() return { vdata = { variables = {} }, config = { vars = {} } } end } }
local rules = { fuel = true, aero = true, diff = true, diffModes = { open = true, lsd = true, locked = true }, centreSplit = true }
bjiRacePrep = {
    getRules = function() return rules end, diffReports = { [1] = {} }, diffSettings = {},
    aids = { [1] = { abs = true, hastc = true, tc = false } },
    isServerManaged = function() return true end, hasRaceOverride = function() return false end,
    hasRoadTemperature = function() return false end,
}
raceprepRatings = { getVehicle = function() return { pi = 550, pi_speed = 555, pi_technical = 545, class = 'B', source = 'measured' } end,
    badge = function(e) return e.class .. ' ' .. e.pi end,
    getPlayer = function() return { pi = 550, pi_speed = 555, pi_technical = 545, class = 'B', source = 'measured' } end }
-- parts rule module stub: the real one is tested in-game
local violation = nil
package.preload['ge/extensions/raceprep/partsRules'] = function()
    return { CATEGORIES = { { key = 'engine', label = 'Engine' }, { key = 'suspension', label = 'Suspension and brakes' } },
        violation = function() return violation, violation and { 'Nitrous fitted: 50kW Shot Size (Camso_n2o_shot)' } or {} end }
end
TABLE_COLUMNS_FLAGS = { WIDTH_FIXED = 1, WIDTH_STRETCH = 2 }; TABLE_FLAGS = { SIZING_STRETCH_PROP = 1, ALTERNATE_ROW_BG = 2 }
local texts, buttons, captured = {}, {}, nil
Button = function(id, label, options)
    buttons[id] = label
    if id == 'raceprep-ready' then captured = { label = label, disabled = options and options.disabled } end
    return false
end
Text = function(s) table.insert(texts, tostring(s)) end
SameLine = function() end; TooltipText = function() end; Separator = function() end; ProgressBar = function() end
Indent = function() end; Unindent = function() end
local tableOpen = false
BeginTable = function() tableOpen = true return true end; EndTable = function() tableOpen = false end
TableNewRow = function() end; TableNextColumn = function() end
Combo = function() return nil end; SliderFloat = function() return nil end
BoolPtr = function(v) return { [0] = v } end
ui_imgui = { Checkbox = function() return false end }
local activeTab = 'Race'
BeginTabBar = function() return true end; EndTabBar = function() end
BeginTabItem = function(name) return name == activeTab end; EndTabItem = function() end

local window = dofile(root .. 'ge/extensions/BJI/ui/windows/RacePrep.lua')
local stamp = 0
local function draw()
    stamp = stamp + 10; texts, buttons, captured = {}, {}, nil
    window.body({ now = stamp, players = { [1] = { playerName = 'Driver' } } })
end
local function hasText(s)
    for _, t in ipairs(texts) do if t:find(s, 1, true) then return true end end
    return false
end
local ok = true
local function check(name, cond) print(string.format('%-60s %s', name, cond and 'ok' or 'FAIL')) ok = ok and cond end

draw()
check('Race tab draws, Ready enabled with a clean car', captured and not captured.disabled)
check('driving aids line shown', hasText('Driving aids:') and hasText('Traction control: off'))
violation = 'nitrous not allowed'
draw()
check('Ready blocked by a parts/nitrous violation', captured and captured.disabled and captured.label:find('nitrous not allowed', 1, true))
check('offending part listed', hasText('Nitrous fitted: 50kW Shot Size'))
violation = nil

-- results module present with a last result: reopen button
local results = require('ge/extensions/raceprep/results')
results.last = { raceName = 'Test Race', laps = 2, date = 'now', sectorBounds = { 1, 2 }, rows = {
    { playerID = 1, position = 1, name = 'Driver', car = 'Test Car', status = 'FIN', laps = 2, total = 120000,
        best = { lap = 2, time = 59000, sectors = { 20000, 19000, 20000 } }, fastestLap = true,
        lapList = { { lap = 1, time = 61000, sectors = { 21000, 20000, 20000 } }, { lap = 2, time = 59000, sectors = { 20000, 19000, 20000 } } },
        bestSectors = { 20000, 19000, 20000 }, theoretical = 59000 },
    { playerID = 2, position = 2, name = 'Other', car = 'Car B', status = 'DNF', laps = 1, lapsDown = 1, lapList = {} } } }
results.visible = false
draw()
check('Last race results button offered', buttons['raceprep-last-results'] ~= nil)

-- Rules tab: read-only summary for every driver
canEdit = false; activeTab = 'Rules'
rules = { aero = true, diff = true, allowedClasses = { C = false }, nitrous = false, startType = 'rolling', paceSpeed = 90, tc = 'off' }
local okRules, err = pcall(draw)
check('Rules summary draws for drivers', okRules and hasText('Car classes') and hasText('E, D, B, A, S, R, P, X'))
check('summary shows nitrous, rolling start, aids', hasText('banned') and hasText('rolling, pace 90 km/h') and hasText('forced off'))
if not okRules then print('  error: ' .. tostring(err)) end
-- the editor (drawn inside BeamJoy's Race Settings for admins)
canEdit = true; texts = {}
local okEd, errEd = pcall(window.drawRulesEditor, 1, 'Test Race')
check('rules editor draws (classes, parts, nitrous, aids, start)', okEd and hasText('Parts') and hasText('Driving aids') and hasText('Start'))
if not okEd then print('  error: ' .. tostring(errEd)) end
canEdit = false; texts = {}
window.drawRulesEditor(1, 'Test Race')
check('editor hidden without SetConfig permission', not hasText('Parts'))

-- results window
local W = dofile(root .. 'ge/extensions/BJI/ui/windows/RaceResults.lua')
results.visible = true
check('results window state visible', W.getState())
texts, buttons = {}, {}
local okRes, err2 = pcall(W.body, { now = 0 })
check('results window draws', okRes and hasText('Test Race') and hasText('Winner') and hasText('+1 lap'))
if not okRes then print('  error: ' .. tostring(err2)) end
-- select a driver: the lap table
Button = function(id, label) buttons[id] = label return id == 'raceprep-results-row-1' end
texts = {}
okRes, err2 = pcall(W.body, { now = 0 })
Button = function(id, label) buttons[id] = label return false end
texts = {}
okRes, err2 = pcall(W.body, { now = 0 })
check('lap breakdown for the selected driver', okRes and hasText('Driver - Test Car') and hasText('Best sectors combined'))
if not okRes then print('  error: ' .. tostring(err2)) end
-- Race Settings hook (bjiRacePrep adds the rules section under BeamJoy's window)
local origCalled = 0
BJI_Win_RaceSettings = { settings = { multi = true, raceID = 9, raceName = 'MOSPORT' }, minSize = ImVec2(470, 260), maxSize = ImVec2(700, 260),
    body = function() origCalled = origCalled + 1 end }
BJI_Win_RacePrep = window
BJI.Windows = { Race = true }; BJI_Windows = { windows = { insert = function() end }, showStates = {} }
BJI_Context.GUI = { registerWindow = function() end }
AddEventHandler = function() end
GetCurrentTimeMillis = function() return 0 end
local initialSessionWindow=dofile(root..'ge/extensions/BJI/ui/windows/RaceSession.lua')
BJI_Windows.windows[1]=initialSessionWindow
local runtimeMod = dofile(root .. 'ge/extensions/bjiRacePrep.lua')
local okHook, errHook = pcall(runtimeMod.onUpdate, 0.1)
local currentSession=require('ge/extensions/raceprep/session')
currentSession.data={id='startup-regression',state='running',rows={}}
BJI_Scenario.isFreeroam=function() return true end
check('pre-scanned session window uses refreshed shared state',initialSessionWindow.getState())
check('runtime update runs with BeamJoy present', okHook)
if not okHook then print('  error: ' .. tostring(errHook)) end
canEdit = true; texts = {}
local clicked = false
Button = function(id, label) buttons[id] = label; if id == 'raceprep-racesettings-rules' and not clicked then clicked = true return true end return false end
BJI_Win_RaceSettings.body({ now = 0 })
check('BeamJoy Race Settings body still drawn', origCalled == 1)
check('rules toggle added to Race Settings', buttons['raceprep-racesettings-rules'] ~= nil)
check('editor shown for the race being set up', hasText('This race: MOSPORT') or hasText('Parts'))
check('window enlarged while rules are open', BJI_Win_RaceSettings.minSize.y >= 600)
BJI_Win_RaceSettings.settings.multi = false; texts = {}; buttons = {}
BJI_Win_RaceSettings.body({ now = 0 })
check('no rules section for solo races', buttons['raceprep-racesettings-rules'] == nil)
-- vehicle selector: only cars the race rules allow
local listRace = { raceID = 4, STATES = { GRID = 1 }, state = 1 }
listRace.getModelList = function()
    return {
        hawk_fm5 = { key = 'hawk_fm5', label = 'Hawk FM5', configs = { a = { key = 'a', label = 'FM5' } } },
        neonna_gt = { key = 'neonna_gt', label = 'Neonna', configs = { b = { key = 'b', label = 'GT' } } },
        bianka = { key = 'bianka', label = 'Bianka', configs = { c = { key = 'c', label = 'Elita' }, d = { key = 'd', label = 'Elita S' } } },
        newcar = { key = 'newcar', label = 'New', configs = { e = { key = 'e', label = 'unrated' } } },
    }
end
BJI_Scenario = { TYPES = { RACE_MULTI = 1 }, get = function() return listRace end }
local ratingsByConfig = { ['hawk_fm5/a'] = { class = 'C', pi = 497 }, ['neonna_gt/b'] = { class = 'E', pi = 250 },
    ['bianka/c'] = { class = 'C', pi = 478 }, ['bianka/d'] = { class = 'B', pi = 540 } }
raceprepRatings.getConfig = function(m, c) return ratingsByConfig[m .. '/' .. c] end
runtimeMod.rules = { default = {}, races = { ['4'] = { allowedClasses = { C = false }, piMin = 300 } } }
runtimeMod.onUpdate(0.1)
local listed = listRace.getModelList()
local names = {}
for k, m in pairs(listed) do for ck in pairs(m.configs) do names[k .. '/' .. ck] = true end end
check('class C and PI below 300 hidden', not names['hawk_fm5/a'] and not names['neonna_gt/b'] and not names['bianka/c'])
check('allowed config of a mixed model kept', names['bianka/d'] == true)
check('unrated cars still listed', names['newcar/e'] == true)
runtimeMod.rules = { default = {}, races = {} }
local all = 0 for _, m in pairs(listRace.getModelList()) do for _ in pairs(m.configs) do all = all + 1 end end
check('no limits: full list', all == 5)
-- Session window rendering and scenario visibility.
local session = require('ge/extensions/raceprep/session')
local freeroam=true
BJI_Scenario.isFreeroam=function() return freeroam end
getCurrentLevelIdentifier=function() return 'test' end
BeginTree=function() return true end;EndTree=function() end
session.data={id='ui-session',label='Qualifying',raceName='Test',state='running',type='qualifying',remaining=60000,
    track={level='test'},gridOrder='qualifying',gridPatch=false,rows={{pos=1,playerID=1,name='Driver',best=60000,bestSectors={20000,19000,21000},laps=1}}}
session.laps={{time=60000,valid=true,cuts=0,sectors={20000,19000,21000}}}
local sw=dofile(root..'ge/extensions/BJI/ui/windows/RaceSession.lua')
texts={};sw.body({})
check('session standings and own laps draw',sw.getState() and hasText('Driver') and hasText('1:00.000'))
check('best-lap sector values and lap history draw',hasText('20.000') and hasText('19.000') and hasText('S1 20.000'))
check('missing grid patch is explained',hasText('not installed'))
freeroam=false;check('session window hidden outside free roam',not sw.getState())
freeroam=true;session.data.track.level='other';texts={};sw.body({})
check('session map mismatch explained',hasText('another map'))
session.data.state='ended';check('finished session stays visible briefly',sw.getState())
print(ok and 'ALL OK' or 'FAILURES')
os.exit(ok and 0 or 1)
