-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Presentation and eligibility only. Existing saved Elo and safety stay intact.
local R={grades={'F','E','D','C','B','A','S'}}
function R.score(elo)
 local n=tonumber(elo) or 1500
 if n~=n then n=1500 end
 return math.floor(1000+math.max(0,math.min(3000,n))*4/3+.5)
end
function R.grade(safety)
 local n=tonumber(safety) or 0
 if n>=4.5 then return 'S' elseif n>=4 then return 'A' elseif n>=3 then return 'B'
 elseif n>=2 then return 'C' elseif n>=1 then return 'D' elseif n>=.5 then return 'E' end
 return 'F'
end
function R.rank(grade)
 for i,g in ipairs(R.grades) do if g==grade then return i end end
 return 0
end
function R.refusal(rules,skill,profile)
 if (rules.minSkill or 0)>0 then
  if not skill or (skill.races or 0)<5 then return 'Complete five rated races before entering this skill-limited event.' end
  if R.score(skill.rating)<rules.minSkill then return 'This event requires skill '..rules.minSkill..' or higher.' end
 end
 if R.rank(rules.minSafety)>0 then
  if not profile or (profile.safetyRaces or 0)<5 then return 'Complete five races with safety scoring before entering this safety-limited event.' end
  if R.rank(R.grade(profile.safety))<R.rank(rules.minSafety) then return 'This event requires safety '..rules.minSafety..' or higher.' end
 end
end
return R
