-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- offline test: luajit tests/test_racepath.lua (run from the repo root)
package.path = "client/lua/ge/extensions/raceprep/?.lua;" .. package.path
local P = require("racePath")
local R = 200
local function at(angle) return { x = R * math.cos(angle), y = R * math.sin(angle), z = 0 } end
-- checkpoints at 90, 180, 270, 360 degrees; finish line = checkpoint 4 at angle 0
local cps = { at(math.pi / 2), at(math.pi), at(3 * math.pi / 2), at(2 * math.pi) }
local path = P.new(nil, cps, at(-0.05), 4)
local function check(name, got, want, tol)
    local ok = math.abs(got - want) <= tol
    print(string.format("%-46s %10.1f  want %8.1f  %s", name, got, want, ok and "ok" or "FAIL"))
    if not ok then os.exit(1) end
end
check("lap length before recording (chords)", P.lapLength(path), 4 * math.sqrt(2) * R, 1)
-- drive two laps at 2 degree steps, reporting the checkpoint just passed
local lap, wp = 1, 0
local angle = -0.05
while lap <= 2 do
    angle = angle + math.rad(1)
    local passed = math.floor((angle + 1e-9) / (math.pi / 2))  -- checkpoints passed in total
    lap = math.floor(passed / 4) + 1
    wp = passed % 4
    P.record(path, lap, wp, at(angle))
end
check("lap length after recording (circle)", P.lapLength(path), 2 * math.pi * R, 15)
check("progress at 45 deg, lap 2", P.progress(path, 2, 0, at(math.rad(45))), 2 * math.pi * R + math.rad(45) * R, 15)
check("progress at 135 deg, lap 2", P.progress(path, 2, 1, at(math.rad(135))), 2 * math.pi * R + math.rad(135) * R, 15)
-- leaderboard lagging: car already past checkpoint 2 but still reported at wp 1
check("progress at 185 deg reported wp 1 (lag)", P.progress(path, 2, 1, at(math.rad(185))), 2 * math.pi * R + math.rad(185) * R, 15)
-- lap end reported as lap 1 wp 4 (= lap 2 wp 0)
check("progress at 10 deg as lap 1 wp 4", P.progress(path, 1, 4, at(math.rad(10))), 2 * math.pi * R + math.rad(10) * R, 15)
-- monotonic along a lap
local prev = -1e9
for deg = 1, 359 do
    local p = P.progress(path, 2, math.floor(deg / 90), at(math.rad(deg)))
    if p < prev - 0.5 then print("non-monotonic at", deg, p, prev) os.exit(1) end
    prev = p
end
print("monotonic over lap 2: ok")
print("recorded segments:", P.recordedCount(path))
