-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Native tyre inventory uses the fitted factory source, not one size/model.
-- Original Automation sources and slots do not enter this namespace.
local M={}
local order={stock=1,sport=2,semi_slick=3,race_supersoft=4,race_soft=5,race_medium=6,race_hard=7}
local function source(catalog,model,part)
 local info=(catalog.parts or {})[part]
 if info and (not info.native or info.model~=model or info.kind~='tyre') then return end
 local key=model..'/'..(info and info.stockPart or part or '')
 local s=catalog.nativeTyres and catalog.nativeTyres.sources and catalog.nativeTyres.sources[key]
 if s and s.native==true and s.model==model then return s,info end
end
function M.enabled(catalog,model,vd)
 if not catalog.nativeTyres or not model then return false end
 for _,p in pairs(vd and vd.powertrain or {}) do
  if p.type=='camsoEngine' or p[1]=='camsoEngine' then return false end
 end
 for _,s in pairs(catalog.nativeTyres.sources or {}) do
  if s.native==true and s.model==model then return true end
 end
 return false
end
function M.rows(catalog,model,tree)
 local rows={}
 local function walk(node,path)
  for slot,child in pairs(node and node.children or {}) do
   local childPath={};for i,v in ipairs(path) do childPath[i]=v end;childPath[#childPath+1]=slot
   local s,info=source(catalog,model,child.chosenPartName)
   if s and s.slotType==slot then
    local stockTitle=string.format('%g mm Stock (%s)',s.nominalWidthMM,
      s.compoundReferenceAssumed and 'Race slick' or s.compound)
    local options={{name=s.part,title=stockTitle,compound='stock',offsetMM=0}}
    for _,name in pairs(s.variants or {}) do
     local p=(catalog.parts or {})[name]
     if p and p.native==true and p.model==model and p.stockPart==s.part and p.slotType==slot then
      options[#options+1]={name=name,title=p.name,compound=p.compound,offsetMM=p.offsetMM,
       tooltip=string.format('Nominal width %g mm; physical contact width %g mm. Native factory structure; compound donor %s.',
        p.nominalWidthMM,p.physicsWidthMM,p.donorModel)}
     end
    end
    table.sort(options,function(a,b)
     local ca,cb=order[a.compound] or 99,order[b.compound] or 99
     if ca~=cb then return ca<cb end
     return a.offsetMM<b.offsetMM
    end)
    rows[#rows+1]={group='tyres',nativeTyre=true,axle=s.axle,path=childPath,slot=slot,
     title=s.axle=='front' and 'Front tyres' or 'Rear tyres',current=child.chosenPartName,
     currentTitle=info and info.name or stockTitle,options=options,
     nativeStock={part=s.part,widthMM=s.nominalWidthMM,physicsWidthMM=s.tireWidthMM,
      compound=s.compoundReferenceAssumed and 'race' or s.compound},
     fitted={part=child.chosenPartName,compound=info and info.compound~='stock' and info.compound or
      (s.compoundReferenceAssumed and 'race' or s.compound),offsetMM=info and info.offsetMM or 0,
      unknownSlickGrade=s.compoundReferenceAssumed==true and (not info or info.compound=='stock')}}
   else walk(child,childPath) end
  end
 end
 walk(tree,{})
 table.sort(rows,function(a,b) return a.axle<b.axle end)
 return rows
end
return M
