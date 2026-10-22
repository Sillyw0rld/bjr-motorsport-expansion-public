-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Shift time per gearbox type in the rating formula (constants.params.shift).
-- luajit tests/test_gearbox.lua   (repo root)
local fixture = dofile("tests/fixtures/rating-golden.lua")
local rating = dofile("client/lua/ge/extensions/raceprep/rating.lua")
local function deep(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = deep(v) end return o end
local seen = {}
local manual, other
for _, f in ipairs(fixture.fixtures) do
    local gtype = tostring(f.static.gearboxes and f.static.gearboxes[1] and f.static.gearboxes[1].type or "")
    if gtype:find("^manual") and not manual then manual = f end
    if (gtype:find("^dct") or gtype:find("^sequential")) and not other then other = f end
end
assert(manual and other, "fixture needs a manual and a DCT/sequential car")
local base = fixture.constants
local slow = deep(base); slow.params.shift = { manual = 0.4, sequential = 0, dct = 0 }
local m0, m1 = rating.compute(manual.static, base, manual.drive), rating.compute(manual.static, slow, manual.drive)
local o0, o1 = rating.compute(other.static, base, other.drive), rating.compute(other.static, slow, other.drive)
assert(m1.pi < m0.pi, "manual shift time lowers PI")
assert(o1.pi == o0.pi, "DCT/sequential unaffected at 0 s")
assert(rating.compute(manual.static, deep(base), manual.drive).pi == m0.pi, "no shift constants: unchanged (golden values)")
print(string.format("PASS: gearbox shift time: %s (manual) %d -> %d PI at 0.4 s; %s unchanged at %d",
    manual.model, m0.pi, m1.pi, other.model, o0.pi))
