-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Driver skill rating for the RacePrep server plugin (Elo style).
--
-- Identity: BeamMP guests get a new name every session, so players are keyed
-- by their BeamMP account id when they are logged in, otherwise by a salted
-- hash of their IP address. The IP itself is never stored. The salt is random
-- per server and kept in skills.json. If a player's home IP changes they get
-- a new profile; an admin can join two profiles in skills.json "aliases"
-- ({ "old key": "kept key" }).
--
-- Update after each race, from the finishing order (finishers by time, then
-- the others by distance covered): every pair of drivers is one Elo game,
-- K split over the field. The car matters: each PI point of car advantage
-- counts as CAR_ELO_PER_PI rating points in the expected result, so beating
-- a driver in a much slower car earns less.
--
-- Plain Lua 5.1 arithmetic only, so it runs on BeamMP's server Lua and on
-- LuaJIT (tests).

local S = {}

S.START = 1500
S.K = 32
S.PROVISIONAL_RACES = 5     -- double K for a driver's first races
S.CAR_ELO_PER_PI = 3        -- 100 PI (about 7 s per 2-minute lap) = 300 Elo

-- 32-bit helpers without bit operators (portable Lua)
local TWO32 = 4294967296
local function mul32(a, b)
    local ah, al = math.floor(a / 65536), a % 65536
    return ((ah * b % 65536) * 65536 + al * b) % TWO32
end
local function xor8(a, b) -- a: 32-bit, b: byte
    local lo = a % 256
    local r, bit = 0, 1
    for _ = 1, 8 do
        if (lo % 2) ~= (b % 2) then r = r + bit end
        lo, b, bit = math.floor(lo / 2), math.floor(b / 2), bit * 2
    end
    return a - (a % 256) + r
end
local function fnv1a(s, basis)
    local h = basis
    for i = 1, #s do
        h = mul32(xor8(h, s:byte(i)), 16777619)
    end
    return h
end

--- salted 64-bit (two 32-bit FNV-1a) hex digest
S.hash = function(salt, text)
    local s = tostring(salt) .. "|" .. tostring(text)
    return string.format("%08x%08x", fnv1a(s, 2166136261), fnv1a(s .. "#", 3332679913))
end

S.newSalt = function()
    local parts = {}
    for i = 1, 4 do
        parts[i] = string.format("%08x", math.random(0, 2147483646))
    end
    return table.concat(parts)
end

--- player key from BeamMP identifiers ({ip=..., beammp=..., discord=...})
S.key = function(store, identifiers)
    if type(identifiers) ~= "table" then
        return nil
    end
    local key
    if identifiers.beammp and tostring(identifiers.beammp) ~= "" then
        key = "bmp:" .. tostring(identifiers.beammp)
    elseif identifiers.ip and tostring(identifiers.ip) ~= "" then
        key = "ip:" .. S.hash(store.salt, identifiers.ip)
    end
    -- merged profiles
    local seen = 0
    while key and store.aliases and store.aliases[key] and seen < 10 do
        key, seen = store.aliases[key], seen + 1
    end
    return key
end

S.newStore = function()
    return { version = 1, salt = S.newSalt(), players = {}, aliases = {} }
end

S.player = function(store, key)
    local p = store.players[key]
    if not p then
        p = { rating = S.START, races = 0, wins = 0, podiums = 0, names = {} }
        store.players[key] = p
    end
    return p
end

local function expected(ra, rb)
    return 1 / (1 + 10 ^ ((rb - ra) / 400))
end

--- update ratings from a finished race.
--- entries: ordered best first, { key, name, pi (number or nil) }
--- returns { [key] = delta }
S.update = function(store, entries, now)
    local n = #entries
    local deltas = {}
    if n < 2 then
        return deltas
    end
    local before = {}
    for _, e in ipairs(entries) do
        before[e.key] = S.player(store, e.key).rating
        deltas[e.key] = 0
    end
    for i = 1, n - 1 do
        for j = i + 1, n do
            local a, b = entries[i], entries[j]
            local carEdge = (a.pi and b.pi) and (a.pi - b.pi) * S.CAR_ELO_PER_PI or 0
            local ea = expected(before[a.key] + carEdge, before[b.key])
            local pa, pb = store.players[a.key], store.players[b.key]
            local ka = S.K * (pa.races < S.PROVISIONAL_RACES and 2 or 1) / (n - 1)
            local kb = S.K * (pb.races < S.PROVISIONAL_RACES and 2 or 1) / (n - 1)
            deltas[a.key] = deltas[a.key] + ka * (1 - ea) -- a finished ahead of b
            deltas[b.key] = deltas[b.key] - kb * (1 - ea)
        end
    end
    for i, e in ipairs(entries) do
        local p = store.players[e.key]
        p.rating = math.floor((p.rating + deltas[e.key]) * 10 + 0.5) / 10
        p.races = p.races + 1
        if i == 1 then p.wins = p.wins + 1 end
        if i <= 3 then p.podiums = p.podiums + 1 end
        p.lastSeen = now
        if e.name then
            p.names[e.name] = now or 0
            -- keep the 5 most recent names (guest names change every session)
            local list = {}
            for name, at in pairs(p.names) do list[#list + 1] = { name = name, at = tonumber(at) or 0 } end
            table.sort(list, function(x, y) return x.at > y.at end)
            for k = 6, #list do p.names[list[k].name] = nil end
        end
        deltas[e.key] = math.floor(deltas[e.key] * 10 + 0.5) / 10
    end
    return deltas
end

return S
