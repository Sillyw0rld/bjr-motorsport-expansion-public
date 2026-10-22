-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Stable installed-parts identity; tuning, paint, fuel and current mode excluded.
-- FNV-1a 32-bit (identity/cache key, not a security signature).
local ok,bit=pcall(require,"bit")
if not ok then bit=rawget(_G,"bit32") end
local M={}
local function xorByte(a,b)
    local out,p=0,1
    for _=1,8 do
        if a%2~=b%2 then out=out+p end
        a,b,p=math.floor(a/2),math.floor(b/2),p*2
    end
    return out
end
function M.canonical(parts)
    local keys={}
    for path,part in pairs(parts or {}) do
        if type(path)=="string" and type(part)=="string" and part~="" then keys[#keys+1]=path end
    end
    table.sort(keys)
    local out={}
    for _,path in ipairs(keys) do
        local part=parts[path]
        out[#out+1]=#path..":"..path..#part..":"..part
    end
    return table.concat(out,"\n")
end
function M.hash(parts)
    local h=2166136261
    local s=M.canonical(parts)
    for i=1,#s do
        h=bit and bit.bxor(h,s:byte(i)) or h-h%256+xorByte(h%256,s:byte(i))
        if h<0 then h=h+4294967296 end
        h=(h*403+(h%256)*16777216)%4294967296
    end
    return string.format("%08x",h)
end
function M.key(model,config,parts)
    return model.."/"..config.."/"..M.hash(parts)
end
function M.flatten(tree,out)
    out=out or {}
    if tree and tree.partPath and tree.chosenPartName and tree.chosenPartName~="" then out[tree.partPath]=tree.chosenPartName end
    for _,child in pairs(tree and tree.children or {}) do M.flatten(child,out) end
    return out
end
return M
